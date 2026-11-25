# 21 CFR Part 11 support for the Skyline audit log (LabKey-anchored)

## Branch Information
- **Branch**: Skyline `Skyline/work/20261124_cfr21_part11_audit_log` (local); targetedms
  `fb_skyline-audit-anchoring` (local, from `develop`)
- **Module**: `skyline`
- **Base**: `master` (pwiz), `develop` (targetedms)
- **Created**: 2026-11-24
- **Status**: In Progress (both branches local only, by Nick's choice)
- **Related**: [TODO-20261116_language_independent_audit_logs.md](TODO-20261116_language_independent_audit_logs.md)
  changes audit log entry text (not hashing); both edit `AuditLogEntry.cs`, so merge with care
- **GitHub Issue**: (pending)
- **Checkout**: `I:\git_i\sky_cfr21part11`

## Goal

Make the Skyline audit log hold up to a Part 11 review: audit-trail records
that cannot be silently changed or removed, attributed to authenticated users
with trusted timestamps, plus electronic signatures. Software cannot itself be
"Part 11 compliant" - the claim is that Skyline + Panorama/LabKey *support*
compliance inside a customer's validated system.

Decisions made (2026-11-24):
- **Offline**: queue anchors locally and flush when the server is reachable;
  the document shows as "not yet anchored" until then. Saving is not blocked.
- **Servers**: panoramaweb.org *and* on-prem LabKey (everything lives in the
  targetedms module, which on-prem installs already run).
- **Scope v1**: anchoring + verification + electronic signatures.

## What exists today

Skyline (`pwiz_tools/Skyline/Model/AuditLog/AuditLogEntry.cs`):
- Per-entry SHA-1 over entry content + parent hash (`GetAuditLogHash`, :1530),
  root hash over all entries, and a hash of the `.sky` stream in the `.skyl`
  (`AuditLogList.WriteToXmlWriter`).
- `VerifyHashValues` throws on an edited entry.
- `SrmDocument.ReadAuditLog` (`SrmDocument.cs:2227`): `.sky` hash mismatch
  -> prompt for a reason (`SkylineFiles.AskForLogEntry`) or append an
  "undocumented change" entry, then continue.
- User = `WindowsIdentity.GetCurrent().Name`; timestamps from the local clock.
- Audit logging can be turned off (`DataSettings.AuditLogging`).
- Panorama access: `Shared/PanoramaClient/PanoramaClient.cs`
  (`WebPanoramaClient`), servers in `Util/PanoramaPublishUtil.cs` (`Server`).

targetedms (`labkeyEnlistment/server/modules/targetedms/.../parser/skyaudit`):
- On full document upload, `SkylineAuditLogParser` stores entries by
  document GUID with entry hash + parent hash as a tree (`AuditLogTree`), so
  versions of one document share history.
- `SkylineAuditLogSecurityManager.INTEGRITY_LEVEL { ANY, HASH, RSA }` is a
  per-folder setting; `RSA` is declared but nothing implements it.

## Gaps against Part 11

| Gap | Part 11 | Fix |
|-----|---------|-----|
| Anyone can recompute the hash chain (open algorithm, no secret) | 11.10(a),(e) | Server witness holds the chain head |
| `.skyl` can be deleted / `.sky` edited and accepted as "undocumented" | 11.10(e) | Regulated docs: hard failure, no prompt |
| Logging can be switched off | 11.10(e) | Locked on for regulated docs |
| User is an unauthenticated Windows name | 11.10(d),(g), 11.100 | LabKey-authenticated user on every anchor |
| Local clock | 11.10(e) | Server timestamp on every anchor |
| Only `.sky` hashed; `.skyd`, libraries not covered | 11.10(a),(c) | Hash `.skyd` (+ libraries) in the anchor |
| SHA-1 | (validation) | SHA-256 in a new `DocumentFormat` |
| No e-signatures | 11.50, 11.70, 11.200 | Server-side signing, recorded in the log |

## Design

### Regulated document
A document becomes regulated when it is bound to a LabKey folder that has
the new "Part 11" integrity level (replaces the unused `RSA` level).
The binding (server URL, container path, document GUID) is stored in the
`.skyl`. Once bound:
- audit logging cannot be turned off;
- the "undocumented change" path is a verification failure, not a prompt;
- `DocumentGuid` changes are not allowed except by an explicit, signed
  "branch/copy" action that the server records as a child of the original.

### Anchoring (server is the witness)
On every save of a regulated document Skyline sends one anchor:
`{documentGuid, newEntryHashes[] (ordered), parentHash, rootHash, skyHash,
skydHash, clientUser, clientTime, skylineVersion}`.

The server:
- authenticates the LabKey user (session or API key) and refuses a user
  without permission in the bound folder;
- rejects an anchor whose `parentHash` is not a known node for that GUID
  (any branch is allowed - undo/redo creates branches - but it must attach);
- stores it add-only (no update/delete permission for anyone, including site
  admins via the UI; DB-level grants documented for on-prem validation);
- returns a **receipt** `{anchorId, entryHashes, serverUser, serverTime}`.

The add-only table is the record. Receipts are not signed: Skyline stores
them in the `.skyl` only to show which entries are anchored and who/when the
server recorded; trust comes from checking against the server on open.

**Why no server signing key (decided 2026-11-24):** Part 11 does not require
cryptographic signatures - its e-signatures are ID + password linked to the
record by the system (11.70, 11.200), and a server table with no update or
delete path satisfies the audit-trail requirement. A key would only add
offline verification (reviewers inspect with server access anyway) and weak
protection against a DB admin (the private key would be decrypted with a
master key on the same server). Dropping it removes key storage, rotation,
compromise handling and an `encryptionKey` requirement for on-prem sites.
Leave an optional `signature` field in the receipt format so a server key or
RFC 3161 timestamping can be added later if a validation team asks.

### Offline queue
- When the server cannot be reached, the anchor goes to a pending queue in
  the `.skyl` (and is retried on the next save, open, or a background timer).
- The status bar / audit log grid shows unanchored entries.
- The server records both `clientTime` and its own receipt time, so a late
  flush is visible in the record.
- Known limit, to document for validation: entries changed *before* their
  first flush cannot be detected. Open question: folder policy for maximum
  unanchored age/count before saving is blocked.
- E-signatures need the server and cannot be queued.

### Verification on open
For a regulated document:
1. Verify the local chain (existing `VerifyHashValues`, now SHA-256).
2. If online, ask the server for the anchored heads for this GUID; the local
   chain must contain the latest anchored head and every anchored entry must
   match the server's hashes. A missing head means rollback or a rebuilt
   chain -> hard failure.
3. `.sky` / `.skyd` hashes must match the last entry's anchor (or a pending
   one) - otherwise hard failure.
4. Offline, only step 1 is possible (same as today); show the document as
   "not verified with server" until the next online open.
Failures open the document read-only with the reason, rather than refusing,
so the user can still inspect it (open question - confirm with users).

### Electronic signatures
- New audit log action "Sign" with a meaning (Reviewed / Approved / Authored,
  folder-configurable list).
- Skyline shows a signing dialog: user name + password re-entry (11.200(a):
  both components on the first signing of a session; password on later ones).
  The credentials go to the server, never stored. API keys alone are not
  accepted for signing.
- Server checks credentials, records `{entryHash being signed, user full
  name, meaning, serverTime}` in an add-only table, returns a receipt.
- Skyline adds a signature entry (11.50: printed name, time, meaning) linked
  to the signed entry hash (11.70: signature bound to the record). The audit
  log grid and reports show signatures.
- Any later change to the document is visibly after the signature; the grid
  shows "changed since signed".
- Open question: SSO/LDAP-only on-prem servers have no password LabKey can
  check - may need the LabKey re-authentication flow in an embedded browser.

### Identity
Record both the Windows user (existing) and the LabKey user (new, from the
server receipt). The LabKey user is the authoritative one for regulated docs.

## Work phases

1. **Skyline format**: SHA-256 entry/root/document hashes behind a new
   `DocumentFormat`; `.skyd` hash; binding + receipts + pending queue in the
   `.skyl`; read old formats unchanged. Unit tests in `AuditLogListTest`.
2. **targetedms** (branch `fb_skyline-audit-anchoring`): add-only anchor and
   signature tables + API (`anchorAuditLog`, `getAuditLogHeads`,
   `signAuditLogEntry`); folder integrity level "Part 11" (replaces the
   unused `RSA` level); make full-upload verification check uploaded history
   against anchors. Server tests.
3. **Skyline anchoring**: client calls via `WebPanoramaClient`; bind dialog;
   save hook (shared by GUI, CLI and MCP save paths - see `DocumentWriter`
   convergence note in the skill); offline queue + retry; verification on
   open; locked logging; read-only open on failure.
4. **E-signatures**: signing dialog (native-dialog testable), signature
   entries, grid/report columns, "changed since signed".
5. **CLI**: `--audit-log-bind`, `--audit-log-sign` (needs a non-interactive
   credential story - open question), verification report command.
6. **Validation package**: requirements traceability to Part 11 sections,
   IQ/OQ scripts, documented limits (offline window, DB admin access on-prem).

## Progress

- 2026-11-24 targetedms (`fb_skyline-audit-anchoring`, uncommitted): upgrade script
  `targetedms-26.009-26.010.sql` adds `AuditLogAnchor` + `AuditLogAnchorEntry`, add-only via
  `targetedms.prevent_anchor_change()` triggers (UPDATE/DELETE/TRUNCATE refused unless the transaction
  ran `SET LOCAL targetedms.allow_anchor_purge = 'true'`). Schema XML, `TargetedMSSchema` constants,
  `TargetedMSManager` getters. `AuditLogAnchorTest` (integration) passes 3/3 on the dev server.
- Side effect to settle: a folder holding anchors cannot be deleted (FK to core.Containers); today
  that surfaces as a raw DB error. Add a clear refusal in `TargetedMSListener` / delete UI.
- Tables committed locally as `7eebea29`; do not push the targetedms branch until the API is in
  (pushing starts LabKey TeamCity on the `fb_` branch).
- 2026-11-24 `anchorAuditLog` API (`dc8b65d7`, local): `AuditLogAnchorManager` enforces the chain
  rules (unbroken entries; first anchor starts the log; later anchors attach to a recorded entry;
  branching from an earlier entry allowed; full repeat = retry returning the original receipt;
  partial overlap refused; one folder per document GUID; per-document advisory lock).
  `clientTime` is a UTC instant; `serverTime` returned as UTC. 13/13 tests pass. JSON binding in
  the action is not covered by a test yet.
- 2026-11-24 (`859b9598`, local): audit integrity level 2 is now "21 CFR Part 11" (the old
  `RSA` level was never implemented and behaved like level 1); only Part 11 folders accept
  anchors. `getAuditLogAnchor.api?documentGUID=` returns the latest anchor (replaces the planned
  `getAuditLogHeads`: since entry hashes chain, the open-time check only needs the latest head and
  file hashes). Saves that add no entries (undo, undo+redo) record an anchor at a recorded entry
  so the next open does not look like a rollback; a retry is a repeat of the latest save (same
  head + file hashes). 20/20 tests pass.
- Known limit: a stale retry arriving after a newer save looks like an undo-save (new anchor at
  the older head). Skyline's queue must send anchors in order and drop confirmed ones.
- 2026-11-24 e-signatures (`8ce39450`, local). Decided: signing happens on Panorama, not in
  Skyline, using LabKey's platform re-authentication (`AuthenticationManager.getAndClearReauthUser`;
  password, SSO or second factor, whichever the user signed in with), so Skyline never handles
  credentials; fixed meanings Authored/Reviewed/Approved. Add-only `AuditLogAnchorSignature`
  (meaning, printed name snapshot, server time, signer; one per signer+meaning+state). Pages:
  `auditLogAnchors.view?documentGUID=` (history + Sign links) -> `signAuditLogAnchor.view`
  (confirm, choose meaning) -> re-auth -> `completeAuditLogSignature.view` (GET shows confirm,
  POST consumes the single-use token and signs; LabKey forbids DB writes on GET).
  `getAuditLogAnchor` also returns signatures. Signing requires InsertPermission. 24/24 tests;
  end-to-end flow (anchor, sign, re-auth, token replay 403, no-token 403) verified on the dev
  server with `ai/.tmp/sessions/20261124-cfr21/sign-e2e.sh`.
- Next: link the history page from the document's page; clear folder-delete refusal; Skyline
  client. The targetedms push was held until signing was done (Nick, 2026-11-24).

## Skyline-side design (decided 2026-11-24, replaces the queue/receipts plan above)

- **Stateless client.** Skyline keeps no anchor queue or receipts. After each successful save of
  a bound document, a background task sends the local chain to `anchorAuditLog`; the server
  records only the suffix it does not have. Offline saves lose nothing: the next save or open
  sends whatever the server is missing. No `.skyl` format change for anchoring (older Skyline
  rejects any unknown `.skyl` element, `AuditLogEntry.cs` ReadFromXmlTextReader).
- **Open check** against `getAuditLogAnchor`: server head == local head and document hash
  matches -> verified; server head earlier in the local chain -> verified to there, rest pending;
  server head not in the local chain -> "older than the state recorded on <date> by <user>"
  (restored copy, rebuilt log, or an undo saved offline - shown, not hidden); offline -> "not
  verified with the server".
- **Binding** is a new `[Track]` attribute on `DataSettings` in the `.sky` (server + folder), so
  binding/unbinding is itself an audit log entry; older Skyline ignores the attribute.
- **Hooks**: all saves converge on `SrmDocument.SerializeToFile` (`SrmDocument.cs`), which
  returns the `.sky` SHA-1 hash; GUI `SkylineFiles.SaveDocument`, CLI `CommandLine.SaveDocument`,
  MCP via the GUI path. Opens: `SkylineFiles.OpenFile` and `CommandLine.OpenSkyFile`, both into
  `SrmDocument.ReadAuditLog`.
- **HTTP**: saved `Server` list (Basic auth) and `IRequestHelper.Post(uri, json, msg)` in
  `Shared/PanoramaClient`.
- Server change needed: `anchorAuditLog` accepts the chain from its start.
- Order: server full-chain change; DataSettings binding; anchor/read client; anchor after save
  (GUI + CLI); check on open; "Record on Panorama..." in the Audit Log window. SHA-256 and
  `.skyd` hashing after.

## Open questions
- Folder policy for the offline window (unlimited / max age / max entries).
- Read-only open vs refuse on verification failure.
- SSO-only servers and signing.
- CLI signing credentials.
- Do raw data files need hashes too, or is `.skyd` enough for the record?
- DB-admin threat: on-prem DBAs can edit the anchor table. v1 answer is
  documented DB permission restrictions in the validation package; stronger
  answer, if asked for, is periodically publishing the table's chain head to
  an RFC 3161 timestamp authority (outside witness).
- Documents that outlive their server (decommissioned, or sent to another
  organization): export the anchor records with the document?
