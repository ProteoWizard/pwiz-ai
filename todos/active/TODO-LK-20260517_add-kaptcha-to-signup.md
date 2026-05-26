# Add Kaptcha verification to signup module's SignUpApiAction

## Branch Information
- **Branch**: (to be created)
- **Base**: `release-branch` (labkey)
- **Repo**: `labkey/release-branch/server/modules/MacCossLabModules/signup`
- **Created**: 2026-05-17
- **Status**: Not Started
- **PR**: (pending)

## Objective

Add server-side captcha verification to the `SignUpApiAction` in the `signup` LabKey module so that the skyline.ms self-sign-up form is no longer vulnerable to the same kind of automated abuse that hit PanoramaWeb's `hosted-project-signup` form on 2026-05-14.

The skyline.ms signup form posts to a custom action that creates user accounts directly (not a message board), so an attack would silently create thousands of bogus accounts with no admin notification to act as a canary. This makes the fix more urgent than PanoramaWeb's was — without email alerts, an attack could go undetected for weeks.

## Background

- PanoramaWeb's `hosted-project-signup` was patched 2026-05-14/15 via wiki-page + folder-permission changes (login required to post).
- skyline.ms uses a custom signup module — the form posts to `SignUpApiAction` which calls `SecurityManager.sendEmail()` + creates a `TempUser` record. There's no captcha on that action today.
- LabKey already has a built-in image captcha (`LabKeyKaptchaServlet`) used by self-registration. The fix reuses that existing infrastructure rather than introducing a new dependency.

## Tasks

### 1. Add `kaptchaText` field to `SignupForm`
- [ ] Add `_kaptchaText` field with getter/setter, mirroring `LoginController.RegisterForm.getKaptchaText()`

### 2. Add captcha verification in `SignUpApiAction.execute()`
- [ ] Check `LabKeyKaptchaServlet.SESSION_KEY_VALUE` is set on the session
- [ ] Compare with `signupForm.getKaptchaText()` (case-insensitive)
- [ ] Reject with appropriate error if missing or mismatched
- [ ] Clear the session attribute on success so the same captcha can't be replayed

Reference implementation: `LoginController.java:465-478` (in `RegisterUserAction.validateForm()`).

### 3. Update skyline.ms signup wiki form
- [ ] Add `<img>` tag for the Kaptcha image at `/kaptcha.jpg` (servlet is registered globally in `ApiModule.java:339-341` — verified accessible at `https://panoramaweb-dr.gs.washington.edu/kaptcha.jpg`)
- [ ] Add input field for the user's captcha answer (`name="kaptchaText"`)
- [ ] Include the field in `form.serialize()` so it's posted along with other fields
- [ ] Add client-side `hasValue` check for the new field

### 4. Testing
- [ ] On a local dev instance: form renders, image loads, valid captcha succeeds, invalid captcha rejected
- [ ] Verify session attribute is cleared after a successful submission (so the same captcha can't be reused)
- [ ] Verify the form correctly re-renders / fetches a new image after a failed attempt
- [ ] CSP doesn't block the Kaptcha image
- [ ] Test as an unauthenticated guest (the real attack surface)

## Implementation sketch

### `SignupForm.java`

```java
public class SignupForm extends ... {
    private String _kaptchaText;
    public String getKaptchaText() { return _kaptchaText; }
    public void setKaptchaText(String kaptchaText) { _kaptchaText = kaptchaText; }
    // ... existing fields
}
```

### `SignUpController.SignUpApiAction.execute()` — at the top, before any side effects

```java
String expectedKaptcha = (String) getViewContext().getRequest().getSession(true)
    .getAttribute(LabKeyKaptchaServlet.SESSION_KEY_VALUE);
if (expectedKaptcha == null) {
    errors.reject(ERROR_MSG, "Captcha not initialized, please retry.");
    return response;
}
if (!expectedKaptcha.equalsIgnoreCase(StringUtils.trimToNull(signupForm.getKaptchaText()))) {
    errors.reject(ERROR_MSG, "Verification text does not match, please retry.");
    return response;
}
// Clear so the same captcha can't be replayed
getViewContext().getRequest().getSession(true).removeAttribute(LabKeyKaptchaServlet.SESSION_KEY_VALUE);
```

### Wiki form (skyline.ms `signup-form` or equivalent)

```html
<tr>
  <td class="labkey-form-label">Verification<font color="red">*</font></td>
  <td colspan="2">
    <img src="/login/kaptchaImage.view" alt="Captcha"><br>
    <input name="kaptchaText" id="kaptchaText" size="20" type="text" value="">
  </td>
</tr>
```

Update `renderBody()` to validate that the captcha field is non-empty before submission.

## Key file references

- `labkey/release-branch/server/modules/MacCossLabModules/signup/src/org/labkey/signup/SignUpController.java:773` — `SignUpApiAction`
- `labkey/release-branch/server/modules/platform/core/src/org/labkey/core/login/LoginController.java:438` — `RegisterUserAction` (pattern to copy)
- `labkey/release-branch/server/modules/platform/core/src/org/labkey/core/login/LoginController.java:465-478` — the captcha check itself

## Estimated effort

| Step | Time |
|---|---|
| `SignupForm` change | 5 min |
| `SignUpApiAction` change | 10 min |
| Wiki form update | 30 min |
| Testing | 1-2 hours |
| **Total** | **2-3 hours** |

## Notes / open questions

- Verify the Kaptcha image URL works from outside the login container (the existing `LabKeyKaptchaServlet` is registered globally, but worth confirming for the signup container path).
- Consider whether to also add IP-based rate limiting on the action — captcha alone slows attackers but doesn't stop a determined adversary with captcha-solving services (~$1-2/1000). Probably out of scope for this TODO; would be a separate effort.
- LabKey's existing `RegisterUserAction` does **not** clear the session captcha attribute after use. Worth checking whether that's intentional (maybe the session ends quickly anyway) or an oversight. For this signup flow I'm clearing it — discuss with the team whether to also clear on the LoginController side.
- The lead dev raised a broader concern that LabKey itself should be more robust to insert bursts (rate limiting, anomaly detection, throttled notifications). That's tracked separately as a platform-level discussion, not blocking this TODO.

## Context

Companion to the PanoramaWeb fix being rolled out via wiki pages on PWeb-DR:
- `hosted-project-signup-form` — combined gateway + form requiring login
- `hosted-project-signup-form-submitted` — confirmation page
- Folder permission change: `/home/support/hosted-project-signup` Submitter role for All Site Users

skyline.ms's `signup` module is the architectural equivalent of the PanoramaWeb form, but creates user accounts directly rather than message-board posts. The wiki/permission fix used for PanoramaWeb doesn't apply here — the in-module action is the natural place to enforce captcha.
