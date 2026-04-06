# LabKey Modules — Coding Patterns

General patterns for writing actions, forms, views, unit tests, and Selenium tests in LabKey Server modules.

## Action Types and Method Signatures

### SimpleViewAction — read-only HTML page

Use when you need a GET-only page that displays information without accepting form input.

```java
@RequiresPermission(AdminOperationsPermission.class)
public static class MyAction extends SimpleViewAction<MyForm>
{
    @Override
    public ModelAndView getView(MyForm form, BindException errors)
    {
        // Build and return a view (HtmlView, VBox, JspView, etc.)
    }

    @Override
    public void addNavTrail(NavTree root)
    {
        root.addChild("Page Title");
    }
}
```

### Page title requirement

Every `SimpleViewAction` must set a page title via `addNavTrail`. Without it, the LabKey test framework logs a warning that becomes a **test failure on TeamCity**:

```
Action doesn't define a page title: mymodule-myAction
```

The page `<title>` is derived from the last child added to the nav trail — **not** from `view.setTitle()` (that only sets the webpart frame header). The fix is always in `addNavTrail`:

```java
@Override
public void addNavTrail(NavTree root)
{
    root.addChild("My Page Title");
}
```

`view.setTitle()` can optionally also be set on the `JspView` to control the webpart frame header, but it does not satisfy the test framework's title check.

### FormViewAction — GET form + POST handler

Use when a page needs to both display a form (GET) and process its submission (POST). This is the most commonly used action type for interactive pages. On GET, `getView()` renders the form. On POST, `validateCommand()` and `handlePost()` process the submission. If validation fails or `handlePost()` returns false, `getView()` is called again with `reshow=true` so the form can redisplay with error messages.

```java
@RequiresPermission(AdminOperationsPermission.class)
public static class MyFormAction extends FormViewAction<MyForm>
{
    @Override
    public void validateCommand(MyForm form, Errors errors)
    {
        // Reject bad input — called before handlePost()
    }

    @Override
    public ModelAndView getView(MyForm form, boolean reshow, BindException errors)
    {
        // Build and return the form view
        // reshow=true means we're redisplaying after a failed POST
        JspView view = new JspView<>("/org/labkey/mymodule/view/myForm.jsp", form, errors);
        view.setFrame(WebPartView.FrameType.PORTAL);
        view.setTitle("My Form");
        return view;
    }

    @Override
    public boolean handlePost(MyForm form, BindException errors) throws Exception
    {
        // Process the form submission
        // Return true on success (redirects to getSuccessURL)
        // Return false on failure (reshows form with errors)
    }

    @Override
    public ActionURL getSuccessURL(MyForm form)
    {
        return new ActionURL(SomeAction.class, getContainer());
    }

    @Override
    public void addNavTrail(NavTree root)
    {
        root.addChild("My Form");
    }
}
```

### FormHandlerAction — POST-only, redirects on success

Use when you only need to handle a POST (no GET form rendering). The form is typically rendered by a different action or embedded in a JSP, and this action only processes the submission.

```java
@RequiresPermission(AdminOperationsPermission.class)
public static class MyPostAction extends FormHandlerAction<MyForm>
{
    @Override
    public void validateCommand(MyForm form, Errors errors)
    {
        // Reject bad input
    }

    @Override
    public boolean handlePost(MyForm form, BindException errors) throws Exception
    {
        // Do work; return true on success, false on failure
    }

    @Override
    public ActionURL getSuccessURL(MyForm form)
    {
        return new ActionURL(SomeAction.class, getContainer()).addParameter("id", form.getId());
    }
}
```

### Other action types

| Base class | Use case | Key methods |
|---|---|---|
| `ReadOnlyApiAction<F>` | GET JSON API | `execute()` returns `ApiSimpleResponse` |
| `MutatingApiAction<F>` | POST JSON API | `execute()` returns `ApiSimpleResponse` |
| `ConfirmAction<F>` | Confirmation dialog | `getConfirmView()`, `handlePost()` |

## Form Classes

### Spring parameter binding

LabKey uses Spring parameter binding to automatically populate form bean properties from HTTP request parameters. When you define a form class with getter/setter pairs, Spring matches request parameter names to setter methods and populates the form before your action code runs. This means:
- No manual `request.getParameter()` calls
- Type conversion is automatic (String → int, etc.)
- Form values survive reshowing after validation errors (the form bean is passed back to `getView()`)

### Disallowed parameter names

LabKey's Spring binding framework blocks certain parameter names from being bound to form properties. The disallowed names are defined in `HasAllowBindParameter` (`server/modules/platform/api/src/org/labkey/api/action/HasAllowBindParameter.java`):

```
class, container, containerid, request, response, user, viewcontext
```

The check is **case-insensitive**. If a form property matches any of these names, the setter will never be called and the field will remain `null` — with no error or warning.

This is a security measure to prevent request parameters from overwriting framework properties (e.g., the authenticated `User` object returned by `getUser()` on the action class).

**If you need a parameter with one of these names, rename it.** For example, use `username` instead of `user`:

```java
// WRONG — "user" is disallowed; _user will always be null
private String _user;
public String getUser() { return _user; }
public void setUser(String user) { _user = user; }

// RIGHT — "username" is not disallowed
private String _username;
public String getUsername() { return _username; }
public void setUsername(String username) { _username = username; }
```

This does not affect `request.getParameter()` — only Spring form binding. Code that previously used `request.getParameter("user")` worked because it bypassed Spring binding entirely. When refactoring from manual parameter reads to form classes, watch for this.

### Use `Integer`/`Boolean` for optional parameters

Use wrapper types (`Integer`, `Boolean`) instead of primitives (`int`, `boolean`) for form fields that may be absent from the request. Primitives silently default to `0`/`false`, making it impossible to distinguish "not provided" from an explicit value. Wrapper types remain `null` when the parameter is missing, allowing proper validation:

```java
// WRONG — missing runId silently becomes 0
private int _runId;

// RIGHT — missing runId is null, can be validated
private Integer _runId;

// In the action:
if (form.getRunId() == null)
{
    response.put("success", false);
    response.put("cause", "runId is required");
    return response;
}
```

Use primitives only when a parameter is truly required and has no meaningful null state (e.g., a boolean toggle that always has a default).

### Prefer `org.apache.commons.lang3.StringUtils`

Use `org.apache.commons.lang3.StringUtils` (already a dependency) instead of `org.springframework.util.StringUtils`. The commons-lang3 version avoids coupling to Spring internals. Key equivalences:
- `StringUtils.isEmpty()` — same in both
- `StringUtils.isNotBlank()` — equivalent to Spring's `StringUtils.hasText()`

### Plain bean forms

The simplest form is a plain Java bean with no superclass. Spring binding works on any POJO — no framework base class is required:

```java
public static class MySettingsForm
{
    private String _name;
    private String _password;
    private Integer _maxRetries;

    public String getName() { return _name; }
    public void setName(String name) { _name = name; }

    public String getPassword() { return _password; }
    public void setPassword(String password) { _password = password; }

    public Integer getMaxRetries() { return _maxRetries; }
    public void setMaxRetries(Integer maxRetries) { _maxRetries = maxRetries; }
}
```

A request to `?name=Test&maxRetries=3` will automatically populate the matching fields. Use plain bean forms when you don't need return URL handling or access to the view context.

### Framework base classes

When you need additional framework features, extend one of these:

```
ReturnUrlForm                 — handles returnUrl, cancelUrl, successUrl parameters
  └─ ViewForm                 — adds getContainer(), getUser(), getRequest(), getViewContext()
```

**ReturnUrlForm** (`org.labkey.api.action.ReturnUrlForm`) — provides built-in support for return URL handling. When a page links to an action with `?returnUrl=...`, the form automatically binds it. After processing, call `getReturnActionURL()` to redirect back to the originating page:

```java
public class MyForm extends ReturnUrlForm
{
    private String _name;
    public String getName() { return _name; }
    public void setName(String name) { _name = name; }
}

// In your action:
@Override
public ActionURL getSuccessURL(MyForm form)
{
    // Returns the returnUrl if provided, otherwise falls back to the default
    return form.getReturnActionURL(new ActionURL(DefaultAction.class, getContainer()));
}
```

Key methods:
- `getReturnActionURL()` — returns the bound `returnUrl` as an `ActionURL`, or null
- `getReturnActionURL(ActionURL defaultURL)` — returns `returnUrl` or the given default
- `getCancelActionURL()` — returns `cancelUrl`, falling back to `returnUrl`
- `getSuccessActionURL()` — returns `successUrl`, falling back to `returnUrl`
- `propagateReturnURL(ActionURL url)` — adds the return URL as a parameter to another URL (for chaining)
- `generateHiddenFormField(URLHelper returnUrl)` — static helper to emit a hidden `<input>` for the return URL

**ViewForm** (`org.labkey.api.view.ViewForm`) — extends `ReturnUrlForm` and adds access to the LabKey view context. Provides `getContainer()`, `getUser()`, `getRequest()`, and `getViewContext()`. Use this when you need both return URL support and access to the current container/user.

## DOM Builder API

LabKey provides a Java DOM builder for constructing HTML in controllers (`import static org.labkey.api.util.DOM.*`).

### Imports

```java
import static org.labkey.api.util.DOM.*;               // DIV, TABLE, TR, TD, TH, INPUT, BR, SPAN, FORM, SCRIPT, ...
import static org.labkey.api.util.DOM.Attribute.*;      // action, method, name, type, value, style, href, ...
import static org.labkey.api.util.DOM.LK.ERRORS;
import static org.labkey.api.util.DOM.LK.FORM;          // CSRF-aware form (alternative to plain FORM)
import org.labkey.api.util.ButtonBuilder;
import org.labkey.api.util.LinkBuilder;
import org.labkey.api.util.HtmlString;
```

`import org.labkey.api.view.*` covers: `VBox`, `HtmlView`, `WebPartView`, `ShortURLRecord`, `JspView`, `NavTree`.

### Building a fields table

```java
new HtmlView(TABLE(cl("lk-fields-table"),
    TR(TD(cl("labkey-form-label"), "Label:"), TD("plain text value")),
    TR(TD(cl("labkey-form-label"), "Link:"), TD(LinkBuilder.simpleLink("text", "https://..."))),
    TR(TD(cl("labkey-form-label"), "Date:"), TD(DateUtil.formatDateTime(date, "yyyy-MM-dd")))
));
```

### Form with hidden inputs, table, and submit button

```java
FORM(at(method, "POST", action, postUrl),
    INPUT(at(type, "hidden", name, "id", value, someId)),
    TABLE(at(Attribute.cellpadding, "5", border, "0"), tableRows),
    BR(),
    new ButtonBuilder("Submit").submit(true).build()
)
```

### Data attributes on elements

Data attributes let you attach extra metadata to HTML elements that JavaScript can read without additional server round-trips. This is useful when a user interacts with one element (e.g. clicking a radio button) and you need to populate other form fields based on that selection:

```java
// Each radio button carries its own metadata
INPUT(at(type, "radio", name, "publicationId", value, id)
        .data("publicationType", pubType)
        .data("matchInfo", matchInfoStr))
```

```javascript
// JavaScript reads the data attributes from the selected radio to populate hidden fields
LABKEY.Utils.onReady(function() {
    document.querySelectorAll('input[name="publicationId"]').forEach(function(radio) {
        radio.addEventListener('change', function() {
            const form = this.closest('form');
            form.querySelector('input[name="publicationType"]').value = this.dataset.publicationtype;
            form.querySelector('input[name="matchInfo"]').value = this.dataset.matchinfo;
        });
    });
});
```

The `.data("publicationType", pubType)` call in the DOM builder renders as a `data-publicationtype` attribute in the HTML output (e.g. `<input data-publicationtype="PubMed" ...>`). In JavaScript, data attributes are accessed via `element.dataset` with the attribute name lowercased and hyphens removed: `data-publicationType` becomes `element.dataset.publicationtype`.

### Building links

**In JSP files** — use the `link()` and `simpleLink()` helpers from `JspBase`:

```jsp
<%-- LabKey-styled link (bold, colored) --%>
<%=link("Link Text").href(url)%>

<%-- LabKey-styled link with onClick handler instead of href --%>
<%=link("Run Action").onClick("doSomething();").build()%>

<%-- LabKey-styled link using POST (adds CSRF token) --%>
<%=link("Delete Item", deleteUrl).usePost()%>

<%-- Plain link (no LabKey styling) --%>
<%=simpleLink(text, url)%>

<%-- Avoid — manual HTML construction is error-prone --%>
<a href="<%=h(url)%>"><%=h(text)%></a>
```

**In JavaScript** — use `LABKEY.ActionURL.buildURL()` to construct URLs to controller actions:

```javascript
// Build a URL to an action in the current container
const url = LABKEY.ActionURL.buildURL('mymodule', 'myAction.view');

// Build a URL with a specific container path
const url = LABKEY.ActionURL.buildURL('mymodule', 'myAction.view', folderPath);

// Build a URL with parameters
const url = LABKEY.ActionURL.buildURL('mymodule', 'myAction.view', folderPath, {id: 123});

// Get the current page's query parameters
const params = LABKEY.ActionURL.getParameters();

// Get the current container path
const container = LABKEY.ActionURL.getContainer();
```

**In Java DOM builder code** — use `LinkBuilder`:

```java
LinkBuilder.simpleLink("text", "https://...")       // plain link
LinkBuilder.simpleLink("text", someActionURL)
LinkBuilder.labkeyLink("text", someActionURL)       // LabKey-styled link
```

### Inline JavaScript in JSP

Use `const` and `let` instead of `var` in JavaScript. Wrap DOM-manipulating scripts in `LABKEY.Utils.onReady()` to ensure the DOM is ready:

```jsp
<script type="text/javascript" nonce="<%=getScriptNonce()%>">
    LABKEY.Utils.onReady(function() {
        // DOM manipulation here
    });
</script>
```

### Composite views

```java
VBox view = new VBox();
view.setFrame(WebPartView.FrameType.PORTAL);
view.setTitle("Page Title");
view.addView(new HtmlView(TABLE(...)));
view.addView(new HtmlView(FORM(...)));
```

### Error display

```java
return new SimpleErrorView(errors);        // standard error page
// or inline:
new HtmlView(DIV(cl("labkey-error"), "Error message"))
```

## CSS Guidelines

### Naming Conventions
- Class names must be **lowercase** with **dashes** as separators, prefixed with `labkey-` (e.g. `labkey-data-region`, `labkey-col-header-filter`).
- All classes must be defined in `stylesheet.css` — check existing classes before creating new ones.

### Colors and Inline Styles
- All colors should be defined in the stylesheet, not as inline hex values. This enables site-wide theming.
- Only use inline styles when the styling is truly unique to a single element. If similar styling appears multiple times, create a reusable class.

### Common CSS Classes

| Class | Usage |
|---|---|
| `labkey-data-region` | Data region container |
| `labkey-col-header-filter` | Column header with filter |
| `labkey-row` / `labkey-alternate-row` | Normal / alternating data rows |
| `labkey-row-header` | Row identifier cells |
| `labkey-show-borders` | Adds borders (strong on headers, subtle on body) |
| `labkey-form-label` | Form field labels in `lk-fields-table` layouts |
| `labkey-error` | Error message text |
| `lk-fields-table` | Key-value fields table layout |

## Content Security Policy (CSP)

LabKey enforces a Content Security Policy that blocks inline scripts and inline event handlers.

### Script Nonces

Every `<script>` tag must include a nonce attribute. The server generates a unique nonce per request:

| Context | Nonce Syntax |
|---|---|
| JSP files | `nonce="<%=getScriptNonce()%>"` or use `<labkey:script>` (auto-adds nonce) |
| Module HTML views | `nonce="<%=scriptNonce%>"` |
| Java code | `HttpView.currentPageConfig().getScriptNonce()` |

### Inline Event Handlers Are Forbidden

Do **not** use `onclick`, `onchange`, or other inline event handler attributes. Attach handlers in a nonced `<script>` block instead:

```jsp
<%-- WRONG — CSP violation --%>
<input id="myInput" onchange="respondToChange()">

<%-- RIGHT — handler attached in script block --%>
<input id="myInput">
<script type="text/javascript" nonce="<%=getScriptNonce()%>">
LABKEY.Utils.onReady(function() {
    document.getElementById("myInput").onchange = respondToChange;
});
</script>
```

**JSP alternatives** — element builders handle this automatically:
- Use `<%=link("text").href(url).onClick("handler()")%>` — registers handler correctly
- Use `<labkey:form>` instead of `<form>`, `<labkey:input>` instead of `<input>`
- Use `addHandler("elementId", "event", "handler()")` to register handlers from Java

**Java DOM builder** — use `SelectBuilder`, `LinkBuilder`, `InputBuilder` etc. to build elements. Attach handlers via `HttpView.currentPageConfig().addHandler("myButton", "click", "doSomething()")`.

**For multiple elements** (e.g. per-row in a grid): `getPageConfig().addHandlerForQuerySelector("IMG.my-class", "error", "handleError(this);")`.

## CSRF Protection

All mutating requests (POST) must include a CSRF token. GET requests must **never** mutate server state.

| Context | How to Include CSRF Token |
|---|---|
| JSP forms | Use `<labkey:form>` instead of `<form>`, or add `<labkey:csrf />` inside `<form>` |
| `LABKEY.Ajax` | Automatic — token sent with all requests |
| JavaScript (manual) | Set hidden input `name="X-LABKEY-CSRF"` with `value` from `LABKEY.CSRF` |
| Java DOM builder | Use `DOM.LK.FORM` for CSRF-aware forms |
| HTTP header | Send `X-LABKEY-CSRF` header (LabKey client APIs do this automatically) |

## Incidental Writes on GET Actions

In dev mode, LabKey throws `IllegalStateException: MUTATING SQL executed as part of handling action: GET` if a GET action executes mutating SQL. For legitimate incidental writes (counters, audit logs, "last accessed" timestamps), wrap the write in `ignoreSqlUpdates()`:

```java
try (var ignored = SpringActionController.ignoreSqlUpdates())
{
    SkylineToolsStoreManager.get().recordToolDownload(tool);
}
```

Do **not** use this to paper over writes that belong in a `MutatingApiAction` or `FormHandlerAction`.

## Permission Annotations

Permission annotations on action classes control what permissions a user must have in the request's container to invoke the action. LabKey URLs encode the container path: `http://<hostname>/path/to/container/controllername-actionname.view`. The framework resolves the container from the URL and checks the annotated permission against the user's roles in that container before the action executes.

```java
@RequiresPermission(AdminOperationsPermission.class)     // site admin
@RequiresPermission(AdminPermission.class)               // folder admin
@RequiresAnyOf({AdminPermission.class, SomeCustomPermission.class})
```

## Database Patterns

### Schema Migration

Scripts live in `resources/schemas/dbscripts/postgresql/` named `<module>-<from>-<to>.sql`. Version numbers follow `YY.NNN` (e.g. `25.000`, `25.001`), bumping at the start of each year.

**To add a migration script:**
1. Name it `<module>-<from>-<new>.sql` where `<from>` >= the stored schema version (i.e. the to-version of the last script that ran). Use the current `getSchemaVersion()` value as `<from>` for clarity.
2. Bump `getSchemaVersion()` in the module class to `<new>`.

Gaps in the version sequence are expected and fine — the code selects scripts where `fromVersion >= storedVersion`, so a script named `25.000-25.001` will run even if the stored version is `16.2`.

```java
@Override
public @Nullable Double getSchemaVersion()
{
    return 25.001;  // to-version of the latest migration script
}
```
See the [LabKey SQL Scripts documentation](https://www.labkey.org/Documentation/wiki-page.view?name=sqlScripts) for more details on module schema versioning and upgrade scripts.


### Schema XML Column Definitions

Column definitions in `resources/schemas/<module>.xml` must match the actual database schema. If the XML defines a column that doesn't exist in the database (or vice versa), the server will report an error on startup.

```xml
<column columnName="MyField">
    <description>Human-readable description of this column</description>
</column>
```

## UserSchema — Exposing Module Tables to the Query API

### DbSchema vs UserSchema

**`DbSchema`** is a low-level wrapper around a raw database schema. It knows about tables and columns via the database catalog (and optionally a schema XML file), but it has no concept of LabKey containers, users, or permissions. It is used internally by actions and managers to execute SQL.

**`UserSchema`** is the higher-level abstraction that plugs into the LabKey query system. It is scoped to a `(User, Container)` pair and is what makes tables accessible via:
- The Query Schema Browser UI
- `SelectRowsCommand` / `UpdateRowsCommand` in Selenium tests and remote API clients
- Custom queries, saved views, and cross-folder lookups

Without a `UserSchema` registration, a module's DB tables are invisible to the query API even if they are visible in the Schema Administration page (which lists raw DB schemas, not query schemas).

### Registering a UserSchema

The standard pattern, used by `PanoramaPublicSchema`, `TargetedMSSchema`, and others:

**1. Make the schema class extend `UserSchema`:**

```java
public class MyModuleSchema extends UserSchema
{
    public static final String SCHEMA_NAME = "mymodule";

    public MyModuleSchema(User user, Container container)
    {
        super(SCHEMA_NAME, "MyModule data", user, container, getSchema());
    }

    public static void register(Module module)
    {
        DefaultSchema.registerProvider(SCHEMA_NAME, new DefaultSchema.SchemaProvider(module)
        {
            @Override
            public QuerySchema createSchema(DefaultSchema schema, Module module)
            {
                return new MyModuleSchema(schema.getUser(), schema.getContainer());
            }
        });
    }

    public static DbSchema getSchema()
    {
        return DbSchema.get(SCHEMA_NAME, DbSchemaType.Module);
    }

    @Override
    public @Nullable TableInfo createTable(@NotNull String name, @NotNull ContainerFilter cf)
    {
        // See below for how to expose columns
    }

    @Override
    public @NotNull Set<String> getTableNames()
    {
        return Set.of("mytable", "anothertable");
    }

    // Static accessors used by controller/manager code — unchanged
    public static TableInfo getTableInfoMyTable() { return getSchema().getTable("mytable"); }
}
```

**2. Call `register()` from the module's `init()` method:**

```java
@Override
protected void init()
{
    addController("mymodule", MyModuleController.class);
    MyModuleSchema.register(this);
}
```

The `SchemaProvider` base class only makes the schema available in containers where the module is active (checked via `schema.getContainer().getActiveModules().contains(module)`).

### Exposing Columns with `wrapAllColumns()`

`createTable()` must return a `TableInfo`. For simple read-only access to all DB columns, use `FilteredTable` and call `wrapAllColumns(true)`:

```java
@Override
public @Nullable TableInfo createTable(@NotNull String name, @NotNull ContainerFilter cf)
{
    TableInfo dbTable = switch (name.toLowerCase())
    {
        case "mytable"      -> getTableInfoMyTable();
        case "anothertable" -> getTableInfoAnotherTable();
        default             -> null;
    };
    if (dbTable == null)
        return null;
    FilteredTable<MyModuleSchema> table = new FilteredTable<>(dbTable, this, cf);
    table.wrapAllColumns(true);
    return table;
}
```

`wrapAllColumns(true)` copies all columns from the underlying `DbSchema` table into the `FilteredTable`, making them visible in the Query Browser and queryable via the API. Without this call, the table appears in the schema tree but shows no columns.

For tables that need custom column configuration (lookups, hidden columns, display formats), create a dedicated `TableInfo` subclass instead (as `PanoramaPublicSchema` does for its tables).

### Defining foreign key lookups

Foreign key lookups (the "Lookup" column in the Query Schema Browser) require **two things**:

**1. Schema XML** — defines the FK at the `DbSchema` level (`resources/schemas/<schemaname>.xml`):

```xml
<column columnName="userid">
    <fk>
        <fkDbSchema>testresults</fkDbSchema>
        <fkTable>user</fkTable>
        <fkColumnName>id</fkColumnName>
    </fk>
</column>
```

**2. Resolve FKs to `UserSchema` level in `createTable()`** — the schema XML FK alone is not enough. `FilteredTable.wrapAllColumns()` propagates the `DbSchema`-level FK, but the target schema shows up as `undefined` in the Query Schema Browser because the FK has no `UserSchema` context. A `UserSchema`-level FK (built with `QueryForeignKey`) is required for the hyperlink to render and for navigation to the target query grid to work.

Rather than hardcoding each FK column individually, walk all columns after `wrapAllColumns()` and convert any FK that targets this schema automatically:

```java
private void resolveSchemaForeignKeys(FilteredTable<MyModuleSchema> table, ContainerFilter cf)
{
    for (ColumnInfo col : table.getColumns())
    {
        ForeignKey fk = col.getFk();
        if (fk == null)
            continue;
        String fkTable  = fk.getLookupTableName();
        String fkCol    = fk.getLookupColumnName();
        String fkSchema = fk.getLookupSchemaName();
        // Replace FKs targeting this schema (schema comes through as null or SCHEMA_NAME
        // from the DbSchema XML). Skip FKs targeting other schemas (e.g. "core").
        if (fkTable != null && (fkSchema == null || SCHEMA_NAME.equalsIgnoreCase(fkSchema)))
        {
            var mutableCol = table.getMutableColumn(col.getName());
            if (mutableCol != null)
                mutableCol.setFk(QueryForeignKey.from(this, cf).to(fkTable, fkCol, null));
        }
    }
}
```

Call this after `wrapAllColumns()` in `createTable()`:

```java
FilteredTable<MyModuleSchema> table = new FilteredTable<>(dbTable, this, cf);
table.wrapAllColumns(true);
resolveSchemaForeignKeys(table, cf);
return table;
```

`QueryForeignKey.from(this, cf).to(tableName, pkColumn, displayColumn)` — pass `null` as `displayColumn` to let LabKey use the first non-PK text column in the target table automatically.

### Reserved column names with automatic lookups

LabKey recognizes certain column names by convention and applies lookups or special handling automatically — no `<fk>` element needed in the schema XML:

| Column name | Auto-applied behavior |
|---|---|
| `container` | FK to `core.Containers.EntityId` → displays container path/name |
| `createdby` | FK to `core.UsersData.UserId` → displays user display name |
| `modifiedby` | FK to `core.UsersData.UserId` → displays user display name |
| `created` | Treated as a date/time column |
| `modified` | Treated as a date/time column |

Custom FK columns (e.g. `userid` pointing to a module's own table) are not recognized by convention and require an explicit `<fk>` definition.

### External Schemas vs UserSchema

LabKey administrators can manually register an "External Schema" via Schema Administration → New External Schema, which wraps a raw DB schema and exposes it in the Query Browser for a specific folder. This is a quick workaround but carries caveats:

- It bypasses LabKey security and integrity checks (LabKey warns about this in the UI)
- It is fragile across upgrades (the schema page notes queries may stop working)
- It is folder-specific, not tied to the module lifecycle
- It requires manual admin setup on each server

If a module registers its own `UserSchema` via code, the code-level registration takes precedence over any External Schema with the same name in containers where the module is active. Existing saved queries and custom views continue to work (same schema and table names). After deploying the module update, delete the External Schema via Schema Administration to remove the now-dead manual registration.

## Unit Tests

Unit tests live as `public static class TestCase extends Assert` inner classes within the class being tested. They are registered in the module class's `getUnitTests()`.

```java
import org.junit.Assert;
import org.junit.Test;

public class MyService
{
    private static String doSomething(String input) { ... }

    public static class TestCase extends Assert
    {
        @Test
        public void testDoSomething()
        {
            assertEquals("expected", doSomething("input"));
        }
    }
}
```

Register in your module class:
```java
@Override
public @NotNull Set<Class<?>> getUnitTests()
{
    Set<Class<?>> set = new HashSet<>();
    // ... existing entries ...
    set.add(MyService.TestCase.class);
    return set;
}
```

Run unit tests in a browser at: `http://localhost:8080/junit-run.view?module=MyModule`

### Running unit tests from the command line (Claude Code)

The junit-run.view page requires authentication. To run tests via curl:

**Step 1: Get CSRF token and login**
```bash
# Fetch the login page to get a CSRF token and session cookie
CSRF=$(curl -s -L -c /tmp/cookies.txt "http://localhost:8080/login-login.view" \
  | grep -oP '"CSRF":"[^"]*"' | head -1 | sed 's/"CSRF":"//;s/"//')

# Login with credentials
curl -s -L -b /tmp/cookies.txt -c /tmp/cookies.txt -X POST \
  "http://localhost:8080/login-loginApi.api" \
  -H "Content-Type: application/json" \
  -H "X-LABKEY-CSRF: $CSRF" \
  -d '{"email":"user@example.com","password":"password"}'
```
A successful login returns `{"success": true, ...}`.

**Step 2: Run the tests**
```bash
curl -s -L -b /tmp/cookies.txt \
  "http://localhost:8080/junit-run.view?module=MyModule" \
  | grep -iE 'SUCCESS|FAILURE|Tests:|Failures:|ComparisonFailure|AssertionError'
```

The page renders test results inline in HTML. Key patterns to grep for:
- `SUCCESS` or `FAILURE` — overall result
- `Tests:` / `Failures:` — counts
- `ComparisonFailure` / `AssertionError` — failure details

**Important:** The LabKey server must be running with the module deployed. After code changes, rebuild and deploy before running tests:
```bash
./gradlew :server:modules:MacCossLabModules:mymodule:deployModule --console=plain
```

## Selenium Tests

For comprehensive Selenium testing patterns, methods, locators, assertions, and DRY practices, see **[labkey-selenium-testing-guide.md](labkey-selenium-testing-guide.md)**.

This section covers LabKey-specific patterns not covered in the general testing guide.

### Impersonation

```java
impersonate(USERNAME);
// ... do things as that user ...
stopImpersonating();

// Stop impersonating and stay on current page (don't go home)
stopImpersonating(false);
```

### Pipeline jobs

```java
goToDataPipeline();
int pipelineJobCount = getPipelineStatusValues().size();
// ... trigger a pipeline job ...
waitForPipelineJobsToComplete(++pipelineJobCount, "Job description", false);
goToDataPipeline().clickStatusLink(0); // View latest job log
assertTextPresent("Expected log message");
```

### Admin settings pages

```java
goToAdminConsole().goToSettingsSection();
clickAndWait(Locator.linkWithText("My Module"));
clickAndWait(Locator.linkWithText("My Settings Page"));
```

### DataRegionTable (grid interaction)

`DataRegionTable` (`org.labkey.test.util.DataRegionTable`) wraps LabKey Data Region grids — any `<table>` with a `data-region-name` attribute.

```java
DataRegionTable table = new DataRegionTable("MyTable", getDriver());
DataRegionTable table = DataRegionTable.findDataRegionWithinWebpart(this, "My Webpart");
```

**Note:** Only works with LabKey DataRegion tables (those with `data-region-name`). For plain HTML tables rendered by JSPs without a DataRegion, use `Locator.xpath()` to locate cells directly.

## File System Patterns

### Prefer NIO over `java.io.File`

Use `java.nio.file.Path` and `Files` instead of `File` for new code. `FileContentService.getFileRootPath()` already returns a `Path` — avoid calling `.toFile()` on it.

```java
// Get container file root as Path
Path fileRoot = FileContentService.get().getFileRootPath(container, FileContentService.ContentType.files);

// File existence check
Files.exists(fileRoot.resolve("docs/index.html"))

// Directory listing
try (var stream = Files.list(localToolDir))
{
    stream.map(p -> p.getFileName().toString())
          .filter(name -> !name.startsWith("."))
          .forEach(results::add);
}

// Recursive directory copy (LabKey utility — takes Path, not File)
FileUtil.copyDirectory(srcPath, destPath);
```

### WebDAV URL Construction

Use `WebdavService.getPath()` to build WebDAV URLs rather than hardcoding `/_webdav`. This respects server configuration and handles path encoding:

```java
org.labkey.api.util.Path path = WebdavService.getPath()
        .append(container.getParsedPath())
        .append(FileContentService.FILES_LINK)
        .append(new org.labkey.api.util.Path("subdir", "file.html"));
String url = AppProps.getInstance().getContextPath() + path.encode();
```

Note: `container.getParsedPath()` returns `org.labkey.api.util.Path` (LabKey's path type), not `java.nio.file.Path`. Use the fully qualified name if both are imported.

In JSPs, `h(url)` on a URL produced by `path.encode()` is correct — `h()` HTML-escapes while `encode()` URL-encodes, and they operate on different character sets without double-encoding.

### Zip Extraction with Zip-Slip Protection

```java
try (ZipFile zf = new ZipFile(zipPath.toFile()))
{
    Enumeration<? extends ZipEntry> entries = zf.entries();
    while (entries.hasMoreElements())
    {
        ZipEntry entry = entries.nextElement();
        if (entry.isDirectory()) continue;
        Path destPath = destDir.resolve(entry.getName()).normalize();
        // Zip-slip protection — normalize() resolves ".." components
        if (!destPath.startsWith(destDir.normalize()))
            throw new IOException("Zip entry outside target directory: " + entry.getName());
        Files.createDirectories(destPath.getParent());
        try (InputStream in = zf.getInputStream(entry))
        {
            Files.copy(in, destPath, StandardCopyOption.REPLACE_EXISTING);
        }
    }
}
```

`Path.startsWith()` compares path components (not characters), so a sibling path like `destExtra/` cannot falsely match `dest/`.

---

For information about feature branch workflow, branch naming conventions, and merge rules, see [labkey-feature-branch-workflow.md](labkey-feature-branch-workflow.md).
