# Add Kaptcha verification to signup module's SignUpApiAction

## Branch Information
- **Branch**: `26.3_fb_signup-kaptcha`
- **Base**: `release26.3-SNAPSHOT` (labkey)
- **Repo**: `labkey/release-branch/server/modules/MacCossLabModules/signup`
- **Created**: 2026-05-17
- **Status**: Completed
- **PR**: [#638](https://github.com/LabKey/MacCossLabModules/pull/638) (merged 2026-05-27)

## Objective

Add server-side captcha verification to the `SignUpApiAction` in the `signup` LabKey module so that the skyline.ms self-sign-up form is no longer vulnerable to the same kind of automated abuse that hit PanoramaWeb's `hosted-project-signup` form on 2026-05-14.

Signup is a two-stage flow: `SignUpApiAction` (and `BeginAction`) writes a row to the signup module's `tempusers` table and sends a confirmation email containing a one-time key; the actual LabKey user account is only created later, in `ConfirmAction`, when the recipient clicks the link and sets a password. So an unprotected signup form does not silently create real accounts, but it does enable two real abuse vectors: (1) email-bombing arbitrary third parties — the attacker controls the recipient address and the server happily sends a "confirm your registration" email to it — and (2) flooding the `tempusers` table with junk rows. Vector (1) is the more concerning one because the spam comes from skyline.ms's own mail infrastructure.

## Background

- PanoramaWeb's `hosted-project-signup` was patched 2026-05-14/15 via wiki-page + folder-permission changes (login required to post).
- skyline.ms uses a custom signup module — the form posts to `SignUpApiAction` which calls `SecurityManager.sendEmail()` + creates a `TempUser` record. There was no captcha on that action.
- LabKey already has a built-in image captcha (`LabKeyKaptchaServlet`) used by self-registration. The fix reuses that existing infrastructure rather than introducing a new dependency.

## Tasks

### 1. Server-side changes (SignUpController.java)
- [x] Add `_kaptchaText` field to `SignupForm` with getter/setter
- [x] Add `_emailConfirm` field to `SignupForm` with getter/setter
- [x] Extract shared helpers used by both `BeginAction` and `SignUpApiAction`:
  - `verifyCaptcha` — checks session attribute, logs per LoginController pattern, clears on success
  - `validateSignupForm` — blank-field checks + emailConfirm match
  - `parseAndValidateEmail` — runs `EmailValidator.isValid` first, then `ValidEmail` constructor
  - `createUserAndSendEmail` — wraps TempUser insert + sendEmail in a transaction
- [x] Both actions follow the same verification sequence: captcha → blank fields → email parse → userExists → send email
- [x] Fix API path bug: `EmailValidator.isValid` was not called (BeginAction had it, API did not)
- [x] Fix API path bug: sendEmail failure was falling through to `status=USER_ADDED`
- [x] Wrap TempUser insert + sendEmail in a transaction so the row rolls back if email delivery fails
- [x] Move BeginAction validation from `validateCommand` to `handlePost` to match API ordering

### 2. JSP form (signupPage.jsp)
- [x] Rewrite using `<labkey:form layout="horizontal">` + `<labkey:input>` taglibs
- [x] Add kaptcha image, reload link, and kaptcha text input
- [x] Add `emailConfirm` field
- [x] Remove Position field (not persisted in schema)
- [x] Form posts to current URL (no hardcoded container)

### 3. Wiki form (skyline.ms)
- [x] Source-of-truth HTML committed in the signup module
  - Final file: `signup/wiki/signup-form.html` (replaces the earlier draft at `pwiz-ai/.tmp/wiki-signup-form-updated.html`)
  - Changes: added kaptcha image + reload JS, emailConfirm field, removed Position field; LabKey UI cleanup (captcha row uses the same `form-group` / `col-sm-3` / `col-sm-9` grid as the other fields, proper `<label for>` instead of `<strong>`, inline-style block replaced with named CSS classes, inline error banner + Bootstrap `has-error` instead of `alert()`, `<button type="submit">` replacing `<input name="Submit">`, `<center>` replaced with a `skyline-signup-footer` class); captcha shows an italic "Loading…" placeholder behind the `<img>` while `/kaptcha.jpg` is in flight; `.skyline-signup-form .form-control { width: 100%; }` re-asserted so the wiki override does not shrink the inputs
- [x] Paste `signup/wiki/signup-form.html` into the wiki editor — validated on the test server; the production skyline.ms paste is the one remaining deploy step, tracked separately

### 4. Testing
- [x] Valid kaptcha + valid form: confirmation email sent, TempUser row inserted
- [x] Invalid kaptcha: error returned, no row inserted
- [x] Session expired / kaptcha not initialized: delete JSESSIONID cookie in DevTools → Application → Cookies, submit → "Captcha not initialized, please retry."
- [x] Invalid email format (e.g. "notanemail"): rejected with error message
- [x] Email / Confirm Email mismatch: rejected with error message
- [x] Email already registered: API returns `status=USER_EXISTS`
- [x] SMTP failure: verified by disabling Dumbster on dev and inducing an SMTP error — transaction rolled back and TempUser row was not inserted
- [x] Tested as unauthenticated guest

## Key file references

- `signup/src/org/labkey/signup/SignUpController.java` — main implementation
- `signup/src/org/labkey/signup/signupPage.jsp` — JSP form
- `pwiz-ai/.tmp/wiki-signup-form-updated.html` — updated wiki form (not yet deployed)
- `labkey/release-branch/server/modules/platform/core/src/org/labkey/core/login/LoginController.java` — `RegisterUserAction` (captcha pattern reference)

## Notes

- `LabKey's RegisterUserAction` does not clear the session captcha attribute after use. We do clear it in our implementation (after a successful match) so the same captcha cannot be replayed.
- IP-based rate limiting would further reduce abuse risk but is out of scope for this change.

## Progress Log

### 2026-05-27 - Merged

PR #638 merged as commit `ce9055a5`. Verified on the test server. Wiki HTML moved into the module at `signup/wiki/signup-form.html` with LabKey UI cleanup; paste into the skyline.ms wiki is still pending as a deploy step.

### 2026-06-07 - Closed out

All code and the wiki form were deployed and tested successfully on the test server, including the signup form rendered from `signup/wiki/signup-form.html`. The only remaining work is pasting that HTML into the production skyline.ms wiki, which is tracked separately as a deploy step. Moving this TODO to completed.
