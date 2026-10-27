# TODO-20261025_signup_hash_expire_key.md

## Branch Information
- **Repository**: `LabKey/MacCossLabModules` (maccossmodules enlistment, `server/modules/MacCossLabModules`)
- **Branch**: `fb_signup-hash-expire-key`
- **Base**: `develop`
- **Created**: 2026-10-25
- **Status**: Completed
- **PR**: [#682](https://github.com/LabKey/MacCossLabModules/pull/682) (merged 2026-10-27)
- **Platform PR**: [LabKey/platform#8241](https://github.com/LabKey/platform/pull/8241), branch
  `fb_remove-unused-sendemail` in the vagisha/platform fork
- **Objective**: Store SignUp confirmation keys as hashes, expire them after seven days, and make each
  link work once, the same way LabKey/platform#8211 changed core verification tokens.

## Background

Adam (LabKey) pointed out that the SignUp module had the same problems platform#8211 fixed in core.
`signup.temporaryuser` held the emailed key in plain text, the key never expired, and it was never
cleared after use, so database contents alone could be used to create an account for a pending
signup. Module docs are in `ai/docs/labkey/signup/signup-module.md`.

## Decisions

- Hash with `Crypt.SHA256.digestWithPrefix`, the same as platform. Keys are long and random, so an
  unsalted fast hash is enough.
- Links expire after `LoginManager.SETUP_LINK_TIMEOUT` (seven days). Expired rows are kept.
- A repeat signup for the same email replaces only the key, and the link sent earlier stops working.
  The name, organization and folder from the first signup are kept, so someone else submitting the same
  email cannot change them. Users can edit their name and organization after the account exists.
- The key is cleared when the account is created, by a conditional update in the same transaction, so a
  key replaced or used after the check cannot create the account.
- Used, expired and wrong keys all get the same "could not be verified" message.
- The admin `ConfirmationURL` column masks the key and is empty for used and expired keys, in the grid,
  exports and the JSON API.
- `clearKeyIfValid` is a hand-written conditional UPDATE that checks the row count, the same pattern as
  platform's `LoginManager.updateVerification`. The plain updates by primary key in `saveWithNewKey`
  and `setLabkeyUserId` use `Table.update` with a map.
- The tests are registered with `getIntegrationTests()`, since they need the database.
- The upgrade script is `signup-26.000-26.001.sql` (module version 13.24 -> 26.001), following the
  sibling modules' year-based numbering.
- Integration tests only (`SignUpManager.TestCase`). Kaptcha blocks a Selenium test of the signup form.

## Tasks

- [x] Hash, expire and clear the key (`SignUpManager.saveWithNewKey`, `verifyUser`, `clearKeyIfValid`, `setLabkeyUserId`)
- [x] Send the link expiration in the email (`SecurityManager.sendEmail` with a `Duration`)
- [x] Mask the admin column, empty for used and expired keys
- [x] Upgrade script, tested on the dev server (a plain-text key converted by the script was accepted
      by `ConfirmAction`)
- [x] Integration tests, 6 passing
- [x] LabKey 5-phase review and `/code-review high`, findings triaged and fixed
- [x] Manual end-to-end check on the dev server (hashed storage, expiry text in the email, repeat
      signup, single use, expiry, masked column)
- [x] Committed (049958d3) and pushed
- [x] Push and open the PR against `develop`
- [x] Copilot review. Its one finding (checking the key and clearing it were separate steps) is
      fixed with a conditional clear (`SignUpManager.clearKeyIfValid`) at the start of the account
      transaction. A second `/code-review high` led to keeping the first signup's details, the
      column fix, `Table.update` for updates by primary key and the integration-test registration.
      Committed as c0f06c79 and pushed. Reply posted and thread resolved.
- [x] Human review. Approved by Adam (LabKey). His `@Nullable` suggestion for `verifyUser` is in 958be17f.
- [x] Merged to `develop` on 2026-10-27
- [x] Opened LabKey/platform#8241 to remove the 5-argument `SecurityManager.sendEmail`, which has no
      callers left. Adam (LabKey) merges it.

## Follow-ups

- At deploy on skyline.ms, check whether the registration email template is customized. A customized
  template does not have the `^linkExpiration^` line, so the email would not mention the expiry.
- At deploy, check the `signup-form` wiki page in `/home/support` for text that tells users to use the
  link from their first email. A repeat signup now sends a new link and the first one stops working.

## Progress Log

### 2026-10-27 - Merged

PR #682 merged to `develop` as f9a0a629, after Adam (LabKey) approved it. The final commit, 958be17f,
added his `@Nullable` suggestion for `SignUpManager.verifyUser`. LabKey/platform#8241, opened from the
vagisha/platform fork, removes the `SecurityManager.sendEmail` overload that SignUp no longer calls.
