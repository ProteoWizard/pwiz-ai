# LabKey Selenium Testing Guide

Patterns and commonly used methods for writing Selenium tests for LabKey Server modules.

## Test Structure

### Class hierarchy

- **`BaseWebDriverTest`** (BWDT) — handles browser launch, login, screenshots on failure. Parent classes `LabKeySiteWrapper` and `WebDriverWrapper` provide LabKey-specific and general browser functionality.
- **Helper classes** — high-level tasks spanning many steps (e.g. `APIContainerHelper`, `APIUserHelper`).
- **Page classes** — encapsulate a single page/action. Methods return the same page for chaining.
- **Component classes** — encapsulate smaller UI components (data region, combo box, window).

Prefer helper, page, and component classes over directly interacting with WebDriver.

### Module test directory structure

Tests live in `test/src/` inside the module directory. No `test/build.gradle` is needed — the `org.labkey.build.module` plugin automatically discovers `test/src/`. After creating a new `test/src/` directory, click **"Sync All Gradle Projects"** in IntelliJ.

```
mymodule/
  test/
    sampledata/mymodule/    ← sample data files (XML, zip, etc.)
    src/org/labkey/test/tests/mymodule/
      MyModuleTest.java
```

### Base class pattern

**`PostgresOnlyTest`** — Implement this marker interface for modules that only support PostgreSQL (not SQL Server). The test runner will skip these tests on SQL Server instances.

```java
@Category({External.class, MacCossLabModules.class})
@BaseWebDriverTest.ClassTimeout(minutes = 10)
public class MyTest extends BaseWebDriverTest implements PostgresOnlyTest
{
    private static final String PROJECT_NAME = "MyTest" + TRICKY_CHARACTERS_FOR_PROJECT_NAMES;

    @BeforeClass
    public static void setupProject() { MyTest init = getCurrentTest(); init.doSetup(); }

    @Before
    public void navigateToProject() { goToProjectHome(PROJECT_NAME); }

    @Test
    public void testFeature() { ... }

    @Override protected String getProjectName() { return PROJECT_NAME; }
    @Override protected void doCleanup(boolean afterTest) { new APIContainerHelper(this).deleteProject(PROJECT_NAME, afterTest); }
    @Override public List<String> getAssociatedModules() { return List.of("mymodule"); }
    @Override protected BrowserType bestBrowser() { return BrowserType.CHROME; }
}
```

### Test lifecycle

| Annotation | Runs | Use for |
|---|---|---|
| `@BeforeClass` | Once before all tests | Project creation, module enable, post test data |
| `@Before` | Before each `@Test` method | Navigate to a known starting point (e.g. project home) |
| `doCleanup()` | Before first test and after last test (if passed) | Idempotent cleanup (delete project) |
| `@After` | After each `@Test` method | Restore state modified during the test |

**Do not use `@AfterClass`** — it interferes with LabKey test harness cleanup.

## Navigation

```java
goToProjectHome(PROJECT_NAME);                          // Navigate to project home
goToProjectFolder(PROJECT_NAME, "subfolder");            // Navigate to a subfolder
goToModule("ModuleName");                                // Navigate to module's begin action
goBack();                                                // Browser back button
clickAndWait(Locator.linkWithText("Tab Name"));          // Click a tab or link
clickAndWait(Locator.linkContainingText("Partial"));     // Partial text match
clickAndWait(Locator.linkWithText("link").index(2));     // Click the 3rd matching link (0-based)
```

**Direct URL navigation** — use only when UI navigation is impractical:

```java
beginAt(WebTestHelper.buildRelativeUrl("module", PROJECT_NAME, "action", Map.of("param1", value1)));
```

## Locators

```java
Locator.id("elementId")                                  // By ID
Locator.name("fieldName")                                // By name attribute
Locator.css("input[type='submit'][value='Submit']")      // CSS selector
Locator.linkWithText("exact text")                       // Link by exact text
Locator.linkContainingText("partial")                    // Link by partial text
Locator.tagWithClass("div", "css-class")                 // Tag with CSS class
Locator.xpath("//table[@id='myTable']//tr[2]/td[1]")    // XPath expression
Locator.linkWithText("text").index(N)                    // Nth match (0-based)
```

## Form Interaction

```java
setFormElement(Locator.name("fieldName"), "value");      // Set input value
selectOptionByValue(Locator.id("select"), "optionValue");// Select dropdown option
getSelectedOptionText(Locator.id("select"));             // Read current selection
clickAndWait(Locator.css("input[type='submit']"));       // Submit form

// Select that triggers page navigation (e.g. onChange handler)
doAndWaitForPageToLoad(() -> selectOptionByValue(select, "optionValue"));
```

## Assertions

```java
assertTextPresent("text1", "text2", "text3");            // All present on page
assertTextNotPresent("should not appear");               // Not on page
assertTextPresentInThisOrder("first", "second", "third");// Present in order
assertElementPresent(Locator.id("myElement"));
assertElementPresent(Locator.css(".my-class"), 3);       // Exactly 3 matches
assertElementNotPresent(Locator.id("removed"));
```

**Scoped text assertions** — assert text order within a specific element, not the whole page:

```java
String tableText = getText(Locator.xpath("//table[contains(@class,'myclass')]"));
assertTextPresentInThisOrder(new TextSearcher(tableText), "first", "second", "third");
```

## Waiting

```java
waitForElement(Locator.id("dynamicElement"));
waitForText("Expected text after AJAX");
waitForText(10000, "text with custom timeout");          // Custom timeout in ms
waitFor(() -> someCondition(), "Failure message", 10000);// Custom condition
```

**AJAX + page reload pattern** — when a click triggers an AJAX POST followed by `location.reload()`:

```java
click(locator);
waitForText(expectedText);                               // Wait for visible change

click(locator);
acceptAlert();                                           // If there's a confirm dialog
waitForElement(Locator.xpath("//img[@id='flag'][@title='" + expectedTitle + "']"));
```

## Alerts, Element Properties

```java
String alertText = acceptAlert();                        // Accept (OK) and return text
String alertText = cancelAlert();                        // Dismiss (Cancel) and return text
String text = getText(locator);                          // Visible text
String value = getAttribute(locator, "attributeName");   // HTML attribute
String value = getFormElement(Locator.name("input"));    // Input value
```

## Test Utilities

- **`TestFileUtils.getSampleData("mymodule/myfile.xml")`** — resolves a file from the module's `test/sampledata/` directory.
- **`WebTestHelper.buildURL("module", containerPath, "action")`** — builds a server URL for an action.
- **`WebTestHelper.getHttpClient()`** — returns an authenticated `CloseableHttpClient` (use with try-with-resources).
- **`APITestHelper.injectCookies(request)`** — injects session cookies (including CSRF token) into an `HttpPost` or `HttpGet` request.
- **`WebTestHelper.getRemoteApiConnection()`** — returns a `Connection` for the LabKey remote API.
- **`SelectRowsCommand`** / **`SelectRowsResponse`** — query a schema/table, get rows as `List<Map<String, Object>>`.

## Test Design Guidelines

- Each `@Test` method should be independent — don't rely on test execution order.
- Use `@BeforeClass` for expensive one-time setup; `@Before` for lightweight per-test navigation.
- **Test what users do** — interact with UI elements rather than constructing URLs.
- **Verify what users see** — assert visible text and element state, not implementation details.
- **Toggle tests** — verify initial state → toggle → verify changed state → toggle back → verify original state restored.
- Extract **navigation and assertion helpers** when the same pattern is used more than once.
- Use **`static final` constants** for locators and strings referenced in multiple places.
