# TODO-LK-20260723_signup-security.md

## Branch Information

| Repo | Branch | PR | Base |
|---|---|---|---|
| `MacCossLabModules` | `26.7_fb_signup-security` | [#667](https://github.com/LabKey/MacCossLabModules/pull/667) | `release26.7-SNAPSHOT` |

- **Created**: 2026-07-23
- **Last updated**: 2026-07-28
- **Status**: PR #667 merged into `release26.7-SNAPSHOT` on 2026-07-28 (merge commit
  `0a21a77`). All four in-scope findings are fixed and `SignUpGroupChangeSecurityTest`
  (SIGNUP-1) passes on 26.7. Four review rounds addressed (`/pw-self-review`, LabKey's
  own `review-pr.md`, Copilot, and Josh's review). Awaiting the 26.7 installer build and
  deployment to skyline.ms, then the one deploy-time wiki edit (see Client contract).

### Notes
- **Working tree**: clean except untracked scratch under `signup/wiki/` (never commit).
- **Build**: verified on 26.7 - cleanBuild + deployApp succeed and the test passes.

## Objective
Remediate the confirmed `signup`-module findings from the MacCoss Lab security audit.
All production changes live in `signup/src/org/labkey/signup/SignUpController.java`.

## Findings status
| Finding | Status |
|---|---|
| SIGNUP-1 self-service group change could be steered into a privileged/site/other-project group | Fixed. `validateGroupChangeTarget` requires both to be project groups in the same project and rejects a target that grants more than read access (write or admin permission) anywhere in the project tree. A rejection returns the generic `NO_PERMISSIONS` (the same status as the not-eligible cases, so the response does not reveal which rules are misconfigured) and logs the specific reason server-side. Each successful move is audited. |
| SIGNUP-2 response distinguished an existing account (user enumeration) | Fixed. Both signup paths funnel the existing/new branches through one try/catch: mail OK returns `SUCCESS` for both, a send failure returns the same generic `ERROR` for both. The existing-account path emails the real owner and never touches the account. No automated test (not feasible - see Test coverage); manual Dumbster check + code review. |
| SIGNUP-3 admin config changes not audited | Fixed. The four admin actions emit a `ClientApiAuditEvent` on success. |
| SIGNUP-4 raw mail-send exception returned to caller | Fixed. Both catch blocks log server-side and return only the generic message. |
| SIGNUP-5 / SIGNUP-6 email bombing / no rate limiting | Already fixed - the CAPTCHA in PR #638 (merged to base) blocks automated submissions. No work here. |

Implementation notes worth keeping in mind:
- `sendExistingAccountEmail(ValidEmail)` sends an informational email pointing the owner
  to "Forgot your password?" and never modifies the account. It now propagates a send
  failure (`throws MessagingException`; `MailHelper.send` surfaces failures as an unchecked
  `ConfigurationException`) so a failed send yields the same generic `ERROR` as new signup.
- The unified catch is narrowed to `MessagingException | ConfigurationException |
  SQLException` (not a broad `catch (Exception)`).
- `SignUpApiAction` returns `SUCCESS` (renamed from the misleading `USER_ADDED`).
- `RemoveGroupChangeProperty` keeps its pre-existing `false` return; the
  `m.remove(String.valueOf(oldgroup))` line is a genuine but benign key-type fix.

## Deferred (out of scope for this PR)
- Double-click race on signup: two concurrent submits of the same new email both pass
  the temp-user lookup, then one insert loses the `uq_temporaryuser_email` constraint.
  The constraint prevents any duplicate row or double email, so the only effect is a
  mothership log entry / generic error on the losing click. Not an enumeration vector
  (requires two concurrent requests for the same address, so reveals nothing about a
  pre-existing account). Left as-is - the DB layer throws an unchecked
  `RuntimeSQLException`, which the signup catch clauses do not include.

## Client contract - action needed at deploy
One live skyline.ms wiki page needs an edit at/after deploy. Do NOT touch the live wikis
without the user. Dev copies are under `signup/wiki/`.
1. `signup-form` (`/home/support`) still keys success off `USER_ADDED`. It must check
   `json.status == 'SUCCESS'` and drop the `USER_EXISTS` branch, or the confirmation
   message won't show.

The `register-form` page (`/home/software/Skyline/daily/register-form/`) needs no change.
It already handles `NO_PERMISSIONS`, which is now the status a refused group change
returns, so a misconfigured rule shows the existing "contact the administrator" message
instead of failing silently.

## Test coverage
- **SIGNUP-1**: `SignUpGroupChangeSecurityTest` (`signup/test/src/org/labkey/test/tests/signup/`,
  `@Category({External.class, MacCossLabModules.class})`) is the module's first test.
  One `@Test` drives the actions directly: an admin form POST plants each dangerous
  transition rule, then a non-admin user calls `ChangeGroupsApi` over a remote-API
  `Connection`. It asserts every rejection branch (admin-in-project, admin-in-subfolder,
  nested-group, cross-project, write-enabled Editor, site-group) returns `NO_PERMISSIONS`
  with membership unchanged, a no-rule target also returns `NO_PERMISSIONS`, and the happy
  path returns `USER_MOVED_SUCCESS`. Audit assertions use before/after deltas (root-container events
  survive project cleanup, so absolute counts are unreliable). The site-global
  `SIGNUP_GROUP_TO_GROUP` property is restored in `@After` (survives `clean=false`).
- **SIGNUP-2**: no automated test. The useful end-to-end flow is not testable under our
  constraints - CAPTCHA has no bypass, `signup.temporaryuser` has no `QueryUpdateService`
  to seed a temp-user row, and `ConfirmAction` needs a real HTTP request. Rather than
  reshape a security-sensitive controller for a narrow proxy test, the fix was made
  robust (both->ERROR) so the uniform response no longer depends on the two send paths
  failing in lockstep. Confirmed by the manual enumeration-parity check (Dumbster, 2026-07-26) and code review.

## Manual verification (dev)
Dev server at ROOT context; mail capture toggled via **Go To Module > More Modules >
Dumbster** -> "Record email messages sent". Group-move path confirmed working
(Signup -> DailyRequests). Enumeration parity confirmed 2026-07-26 - passed:
- **Mail working (Part A)**: existing-account and brand-new emails both returned the
  same `SUCCESS` message. Indistinguishable responses.
- **Mail failing (Part B)**: with delivery broken, existing-account and brand-new emails
  both returned the same generic `ERROR` ("Could not send email..."). Indistinguishable
  responses; only the generic message is shown to the caller (SIGNUP-4).

## Tasks
- [x] SIGNUP-1: `validateGroupChangeTarget` read-only enforcement (rejects write or admin targets); refused move returns `NO_PERMISSIONS`.
- [x] SIGNUP-2: uniform response (both->ERROR), existing-account owner email.
- [x] SIGNUP-3: audit the four admin actions.
- [x] SIGNUP-4: generic mail-error message, log server-side only.
- [x] `SignUpGroupChangeSecurityTest` written and passing on 26.7.
- [x] Four review rounds addressed (`/pw-self-review`, LabKey `review-pr.md`, Copilot, Josh's review).
- [x] Mark PR #667 ready for review.
- [x] LabKey reviewer (Josh) approved PR #667.
- [x] Merge PR #667 (merged 2026-07-28, merge commit `0a21a77`).
- [x] Manual verification: enumeration parity passed in both mail modes (2026-07-26).
- [ ] Await the 26.7 installer build and deployment to skyline.ms.
- [ ] At/after deploy: update the remaining live skyline.ms wiki page (`signup-form`; see Client contract).
