# 21 CFR Part 11 support for the Skyline audit log (LabKey-anchored)

## Branch Information
- **Branch**: TBD (Skyline + targetedms, two PRs)
- **Base**: `master` (pwiz), `develop` (targetedms)
- **Status**: Backlog
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
the new "Part 11" integrity level (reuse/replace the unused `RSA` level).
The binding (server URL, container path, document GUID, server public key
fingerprint) is stored in the `.skyl`. Once bound:
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
- returns a **receipt** signed with the folder/server private key:
  `{anchorId, entryHashes, serverUser, serverTime, sig}`.

Skyline stores receipts in the `.skyl`. With the server's public key a
receipt can be checked offline, so a reviewer can verify a document without
a connection, and Skyline can tell anchored entries from unanchored ones.

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
2. Verify every stored receipt against the server public key.
3. If online, ask the server for the anchored heads for this GUID; the local
   chain must contain the head the receipts say it last reached. A missing
   head means rollback or a rebuilt chain -> hard failure.
4. `.sky` / `.skyd` hashes must match the last entry's anchor (or a pending
   one) - otherwise hard failure.
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
  name, meaning, serverTime}`, returns a signed signature receipt.
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
2. **targetedms**: anchor table + API (`anchorAuditLog`, `getAuditLogHeads`,
   `getPublicKey`, `signAuditLogEntry`); key management per server; folder
   integrity level "Part 11"; make full-upload verification check uploaded
   history against anchors. Server tests.
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

## Open questions
- Folder policy for the offline window (unlimited / max age / max entries).
- Read-only open vs refuse on verification failure.
- SSO-only servers and signing.
- CLI signing credentials.
- Do raw data files need hashes too, or is `.skyd` enough for the record?
- Key rotation for the server signing key, and which key verifies old
  receipts.
