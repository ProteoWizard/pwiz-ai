# SignUp Module - Inner Workings

The `signup` module (module name `SignUp`) lives under
`server/modules/MacCossLabModules/signup`. It is deployed only on **skyline.ms**
and provides two related capabilities.

1. **Self-service account signup** - a person without a LabKey account submits
   their details, receives a confirmation email, sets a password, and is
   automatically added to a folder-configured project group.
2. **Self-service group change** - an already-logged-in user moves their own
   membership from one project group to another, but only along transitions a
   site admin has pre-authorized.

A key thing to understand up front is that these two capabilities use
**different** configuration and are triggered by **different** clients. They are
easy to conflate because both add a user to a group. See "Two group mechanisms"
below.

Source: `signup/src/org/labkey/signup/`. Controller
`SignUpController.java`, module `SignUpModule.java`, schema `SignUpSchema.java`,
manager `SignUpManager.java`, admin JSP `SignUpAdmin.jsp`, signup web part JSP
`signupPage.jsp`.

---

## Module wiring

- `SignUpModule.init()` registers the controller under the `signup` name and
  registers the `signup` DB schema.
- `doStartup` adds a container listener and a user listener (both `SignUpListener`)
  and adds a "SignUp" link to the admin console Configuration section, gated by
  `SiteAdminPermission`.
- `getRequireSitePermission()` returns true, so the module is site-permission
  gated.
- One web part factory, "Sign Up", renders `signupPage.jsp`.
- Property categories (all defined as constants on `SignUpModule`):
  - `SIGNUP_CATEGORY = "signup"` - **per-container** property map.
  - `SIGNUP_GROUP_NAME = "groupId"` - key in the per-container map that maps to a project permissions group name. A user who submits a signup request from this container, is added to the project group when they confirm their signup request.
  - `SIGNUP_GROUP_TO_GROUP = "groupToGroup"` - a single **site-global** property
    map (no container) holding the allowed group-change transition rules.

---

## Data model

Two tables in the `signup` schema. Both are only visible through the query schema
to users with `AdminPermission` in the container (`SignUpSchema.createTable`
returns null otherwise).

### signup.temporaryuser

Holds a pending signup between the initial request and email confirmation.

| Column | Type | Notes |
|---|---|---|
| userid | SERIAL PK | |
| email | VARCHAR(255) UNIQUE | one pending row per email |
| firstname, lastname, organization | VARCHAR(255) | |
| key | VARCHAR(64) | the confirmation token sent in the email |
| Container | EntityId | folder the signup happened in |
| labkeyUserId | USERID | set once the account is created |

The query view adds a computed `ConfirmationURL` column that renders the
`ConfirmAction` URL (email + key) for admins.

### signup.movedusers

An audit trail of completed self-service group changes. One row is inserted on
each successful `ChangeGroupsApiAction`.

| Column | Type | Notes |
|---|---|---|
| id | SERIAL PK | |
| labkeyUserId | USERID | the user who moved |
| oldgroup | USERID | group id moved from |
| newgroup | USERID | group id moved to |

The query view renders `oldgroup`/`newgroup` as group names rather than raw ids.

---

## Actions reference (SignUpController)

| Action | Permission | Purpose |
|---|---|---|
| `ShowSignUpAdminAction` | SiteAdmin | Renders `SignUpAdmin.jsp` (the admin config page). |
| `AddPropertyAction` | SiteAdmin | Sets the per-folder signup target group (`SIGNUP_GROUP_NAME`). |
| `RemovePropertyAction` | SiteAdmin | Clears the per-folder signup target group. |
| `AddGroupChangeProperty` | SiteAdmin | Adds an `oldgroup -> newgroup` transition rule to the global map. |
| `RemoveGroupChangeProperty` | SiteAdmin | Removes a transition rule from the global map. |
| `BeginAction` | Read | JSP-based signup form handler (web part path). Sends the confirmation email. |
| `SignUpApiAction` | NoPermission | API signup handler (wiki-form path). Sends the confirmation email. |
| `ConfirmAction` | NoPermission | Email-link target. Creates the account, sets the password, does the initial group join. |
| `ChangeGroupsApiAction` | Login | Self-service group change. Moves the caller between two pre-authorized groups. |

Note the two signup entry points. `BeginAction` backs the "Sign Up" web part JSP
and requires Read. `SignUpApiAction` is the API the external wiki form posts to.
Both do the same work and share helpers
(`validateSignupForm`, `parseAndValidateEmail`, `createUserAndSendEmail`).

### Which pages trigger which action (skyline.ms)

The externally reachable actions are triggered by **wiki/HTML pages stored in the
LabKey database**, not by anything in the module source. That is why grepping the
enlistment finds no callers. As of this writing (verified 2026-07-23):

| Action | Triggered by | Mechanism |
|---|---|---|
| `SignUpApiAction` | Wiki page `signup-form` in `/home/support` (`https://skyline.ms/home/support/wiki-page.view?name=signup-form`) | Form posts to `signup-SignUpApi.view`. |
| `ConfirmAction` | The link in the confirmation email sent by the signup handler | User clicks `signup-confirm.view?email=...&key=...`. |
| `ChangeGroupsApiAction` | The "Agree & Register" button on the Skyline-daily register page at `/home/software/Skyline/daily/register-form/` | Posts `signup/ChangeGroupsApi.view` with an `oldgroup`/`newgroup` pair. |
| `BeginAction` | The "Sign Up" web part JSP (`signupPage.jsp`) | Alternative to the wiki form. Not the path used by the live `/home/support` page. |

If a new self-service transition is ever added, it will be a new DB-stored page
posting a different `oldgroup`/`newgroup`, not a module code change.

---

## Two group mechanisms

This is the most confusing part of the module, so it gets its own section.

### 1. Initial join on confirmation (per-folder `SIGNUP_GROUP_NAME`)

- Configured by a site admin on the admin page under "Add new user group rule".
  It stores, per folder, the **name** of a group in that folder's project.
- Applied automatically inside `ConfirmAction.handlePost` when the user clicks the
  email link and sets a password. The new account is added to that folder's
  configured group.
- This is a one-way join that happens once, at account creation. It is **not** the
  group-change feature.

### 2. Self-service transition (global `SIGNUP_GROUP_TO_GROUP`)

- Configured by a site admin under "Add group conversion rule / Group A -> Group B"
  on the admin page. The rule map is site-global (no container) and maps a source
  group id to a comma-separated list of allowed target group ids.
- The admin UI populates both dropdowns from **every project in the site**. On
  skyline.ms the live rule keeps both groups in the `/home` project.
- Applied by `ChangeGroupsApiAction` when an already-logged-in user posts a
  specific `oldgroup`/`newgroup` pair. See the flow below.

---

## Flow 1 - admin configuration

A site admin visits `signup-showSignUpAdmin.view` (also linked from the admin
console). The page (`SignUpAdmin.jsp`) has two independent config sections.

- "Add new user group rule" -> `AddPropertyAction` / `RemovePropertyAction`
  manage the per-folder `SIGNUP_GROUP_NAME`.
- "Add group conversion rule" -> `AddGroupChangeProperty` / `RemoveGroupChangeProperty`
  manage the global `SIGNUP_GROUP_TO_GROUP` transition map.

All four config actions write an audit event on success.

---

## Flow 2 - signup and confirmation

1. A prospective user opens the signup form. On skyline.ms this is the wiki page
   `/home/support` `signup-form`, which posts to `signup-SignUpApi.view`
   (`SignUpApiAction`). The "Sign Up" web part (`BeginAction`) is the alternative
   JSP path.
2. The handler verifies the Kaptcha (see "Abuse control"), validates the form,
   parses the email, and - if no account exists - calls `createUserAndSendEmail`.
   That inserts a `temporaryuser` row and sends the LabKey registration email
   containing a `ConfirmAction` link (email + key).
3. The user clicks the link. `ConfirmAction` verifies the email+key against
   `temporaryuser`, creates the real account, sets the password via
   `DbLoginService.attemptSetPassword`, and - if the folder has a
   `SIGNUP_GROUP_NAME` configured - joins the new account to that group.

When the submitted email already has an account, both signup handlers return the
same response as a brand-new signup. The existing-account path sends an
informational notice to the account owner (pointing to the password-reset flow)
and never modifies the account, so the response is identical whether or not the
account exists.

---

## Flow 3 - self-service group change

The one live caller of `ChangeGroupsApiAction` on skyline.ms is the **Skyline-daily
registration page**, a wiki/HTML page at
`/home/software/Skyline/daily/register-form/` ("Register for Skyline-daily").
There is no caller in the module source or in the `/home/support` wiki pages - the
trigger is page content stored in the LabKey database.

How it works:

1. A logged-in user opens the register-form page. Client JS calls
   `LABKEY.Security.getGroupsForCurrentUser`.
   - Already in one of the daily-access groups -> redirect straight to the
     Skyline-daily download.
   - Guest -> show a "sign in / sign up" prompt.
   - Logged in but in none of those groups -> show the "Agree & Register" button.
2. The user reviews the license terms and clicks "Agree & Register". The handler
   posts, with a CSRF token, to `signup/ChangeGroupsApi.view` with the source and
   target group ids.
3. `ChangeGroupsApiAction` moves the caller from the source group into the
   configured target group, records a `movedusers` row, and returns
   `USER_MOVED_SUCCESS`. The page then redirects to the Skyline-daily download.
4. `NO_PERMISSIONS` or `USER_MOVED_ERROR` shows an error pointing the user to the
   site administrator. A configured rule pointing at a disallowed target is
   refused with the same `NO_PERMISSIONS`, so it shows the same "contact the
   administrator" message.

So the transition means "grant myself access to the Skyline-daily development
release by accepting the license." It is a distinct, explicit user action and is
**not** triggered by the signup confirmation email. On skyline.ms both the source
and target groups are project groups in the same project, and the target is a
read-only group (Reader access, no write or administrative permission).

### What ChangeGroupsApiAction validates

In order (`SignUpController.ChangeGroupsApiAction.execute`):

1. Caller is logged in (`@RequiresLogin`) and non-null.
2. Caller is a member of `oldgroup` (`user.isInGroup`).
3. The global `SIGNUP_GROUP_TO_GROUP` map has an entry `oldgroup -> [...newgroup...]`.
   If not, `NO_PERMISSIONS`.
4. `validateGroupChangeTarget(oldgroup, newgroup)` re-validates the resolved groups
   before any membership change. It rejects when either group is missing, either is
   a site group (not a project group), the two groups are in different projects, or
   the target grants more than read access (write or admin permission) anywhere in
   its project tree. On rejection it returns the generic `NO_PERMISSIONS` (the same
   status as steps 2-3) and logs the specific reason server-side only.
5. Inside a transaction, `addMember(newgroup)` then `deleteMember(oldgroup)`, insert
   a `movedusers` audit row, and write a `ClientApiAuditEvent`.

The live skyline.ms transition satisfies step 4 because both groups are in the
same project and the target is read-only. The admin UI can express a rule pointing
at a write-enabled, admin, site, or cross-project target, which step 4 would reject.

---

## Abuse control (Kaptcha)

The unauthenticated email-send paths (`SignUpApiAction` and `BeginAction`) call
`verifyCaptcha` as their first step, before any email is sent - it checks the
submitted text against the challenge served by LabKey's Kaptcha servlet
(`LabKeyKaptchaServlet`). `ConfirmAction` is self-limiting because it needs a
valid key from a prior signup.
