# TODO-20261027_panoramapublic_reviewer_password_site_rule.md

Panorama Public reviewer passwords must pass the site password rule.

## Branch Information
- **Branch**: `26.7_fb_reviewer-password-site-rule` in MacCossLabModules only (release-branch enlistment)
- **Base**: `release26.7-SNAPSHOT`
- **Created**: 2026-10-27
- **Status**: In review, [PR #683](https://github.com/LabKey/MacCossLabModules/pull/683). Test failed before the fix and passes after it.
  All 63 PanoramaPublic unit tests pass
- **GitHub Issue**: (pending)
- **Module**: `panoramapublic`

## Problem

`CopyExperimentFinalTask.createPassword()` generates reviewer passwords until one passes
`PasswordRule.Strong`. Login checks the rule the site is configured with instead, and a server set to
`PasswordRule.Good` rejects some of those passwords.

`RuleBasedPasswordValidator` (the base of the Good rule) rejects any password that contains a sequence
of three characters from the user's email address, display name, or first and last name. The check is
case-insensitive. Reviewer emails have the form `panorama+reviewerN@proteinms.net`, which yields about
30 such sequences, including `pro`, `rot`, `net`, `rev` and `ora`.

When the check fails at login, `DbLoginAuthenticationProvider` responds with a forced password change
(`FailureReason.complexity`). The reviewer receives a working password in the copy notification email
and is then made to replace it on first login.

## Reported case

A generated reviewer password contained `rot` (in uppercase), which is also in `proteinms`. The Strong rule
accepted the password and the Good rule rejected it at the reviewer's first login.

## Frequency

A simulation of `PasswordGenerator.generate()` against a reviewer email of the form above, with 200,000
samples, gave 0.44% of passwords containing a sequence from the email. That is about 1 in 230 reviewer
accounts on a server using the Good rule. Display-name sequences add to this.

## Fix

`createPassword()` keeps a generated password only if every `PasswordRule` (Good and Strong) accepts it.

- The password is valid whichever rule the site uses at login, including after an admin changes the rule
- No dependency on `DbLoginService`
- The generator is passed in as a `Supplier<String>` so the unit test can supply fixed passwords

## Tasks

- [x] Change `createPassword(User)` to reject a password unless every `PasswordRule` accepts it
- [x] Make the generator injectable (`Supplier<String>`) so a unit test can supply fixed passwords
- [x] Add `CopyExperimentFinalTask.TestCase` with a made-up user `reviewer@example.org`. It supplies a password
      that passes only Good (`Ab1!xQzk`), one that passes only Strong (`k7#Wq!EXAm2zR9vT`, "exa" is in
      "example"), then one that passes both, and asserts the third is returned
- [x] Confirm the test fails with only Strong checked and with only Good checked, and passes with both
- [x] Register the test in `PanoramaPublicModule.getUnitTests()` and run it through `junit-run.view`
- [x] Build with `gradlew :server:modules:MacCossLabModules:panoramapublic:deployModule`
- [x] `/code-review high`
- [x] Commit `8ab1e9d7` (the fix and its unit test), pushed to origin
- [x] Opened [PR #683](https://github.com/LabKey/MacCossLabModules/pull/683) against `release26.7-SNAPSHOT`

## Related, not in scope

- **Error message** - on the set-password page, `DbLoginManager.attemptSetPassword()` reports the
  specific message "Your password must not contain a sequence of three or more characters from your
  email address." It does not name the matched sequence, so a user cannot tell which characters to
  change. The summary text above the field always lists every rule. This is LabKey platform code
  (`RuleBasedPasswordValidator`) and would go to LabKey as an issue or platform PR
- **Strong is not a superset of Good** - Good rejects any three-character sequence from the email or name.
  Strong removes those sequences and scores the rest, so it accepts some passwords Good rejects. Good accepts
  short passwords such as `Ab1!xQzk` that Strong rejects. Worth raising with LabKey, since the names suggest
  Strong is the stricter rule
