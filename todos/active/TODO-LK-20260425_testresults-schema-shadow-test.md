# TODO-20260425_testresults-schema-shadow-test.md

## Branch Information
- **Branch**: TBD (test plan, not a code branch)
- **Created**: 2026-04-25
- **Status**: Not started
- **Related PRs**:
  - Refactor (UserSchema registration): [#622](https://github.com/LabKey/MacCossLabModules/pull/622)
  - Container filtering: separate PR (out of scope here)

## Objective

Verify that registering `testresults` as a UserSchema correctly shadows the
existing External Schema of the same name and that custom queries authored
against the External Schema continue to resolve under the User Schema. The
MCP nightly tools must keep working through the transition.

Phases 0–3 test shadowing on a dev machine with synthetic data (the binary
correctness question). Phase 4 validates MCP behavior against real
prod-synced data on the test server.

## Out of Scope

- Container filter overrides on `testresults` child tables — branch
  `26.3_fb_testresults-container-filter`, separate PR
- Issues / wiki / support / announcement schemas — only `testresults` is
  affected by the UserSchema registration

## Reference

- `todos/active/TODO-LK-20260326_testresults-migrate-actions.md` — refactor
  TODO, Phase 7
- `mcp/LabKeyMcp/queries/nightly/*.sql` — saved-query source of truth
- `mcp/LabKeyMcp/queries/README.md` — table mapping queries to MCP tools

## Phase 0: Dev Machine Setup

- [ ] Provision a local LabKey instance with the same module set as prod
      (deploying the testresults module creates its DB schema)
- [ ] Redirect `skyline.ms` to the dev machine via hosts file
- [ ] Create LabKey account `<claude-user>@uw.edu` and add to `Site:Agents`
      so the MCP's existing netrc credentials authenticate
- [ ] Create container `/home/development/Nightly x64` (and sibling test
      folders the MCP queries: `Release Branch`, `Performance Tests`,
      `Release Branch Performance Tests`, `Integration`,
      `Integration with Perf Tests`)

## Phase 1: Baseline — External Schema Only (pre-refactor)

- [ ] Check out a commit prior to the testresults UserSchema registration;
      deploy the module
- [ ] Create an External Schema named `testresults`
      (Admin → Schema Administration → New)
- [ ] Seed runs via the Selenium harness's `@BeforeClass` flow (`PostAction`
      with `testresults/test/sampledata/testresults/*.xml`) — at least 3
      runs across 2 computers in `Nightly x64`
- [ ] Author saved queries via Schema Browser, pasting from the `.sql`
      mirrors:
  - [ ] `testruns_detail`
  - [ ] `expected_computers`
  - [ ] `failures_by_date`
  - [ ] `leaks_by_date`
- [ ] Smoke-test the MCP nightly tools (`query_test_runs`,
      `get_run_failures`, `get_run_leaks`, `get_run_toolsets`,
      `get_daily_test_summary`, `analyze_daily_patterns`,
      `list_computer_status`, `check_computer_alarms`) and save the output
      to `ai/.tmp/shadow-test-baseline.md`

## Phase 2: Shadow — External + User Coexist (the actual test)

- [ ] Check out the refactor branch's schema-registration commit; deploy
- [ ] **Do NOT delete the External Schema yet** — both must coexist
- [ ] Re-run the Phase 1 MCP smoke tests; results must match the baseline
      (same row counts, no `ERROR` cells)
- [ ] In Schema Browser, confirm the four saved queries still appear under
      `testresults`. **If they don't, that is the shadowing bug.**
- [ ] Control: create a new saved query
      `mcp_shadow_smoke: SELECT id FROM testruns LIMIT 1` via Schema
      Browser and issue it. Confirms saved-query authoring works under the
      User Schema regardless of whether pre-existing ones port over

## Phase 3: User Schema Only (Phase 7 end state)

- [ ] Delete the External Schema via Admin → Schema Administration →
      testresults → DELETE
- [ ] Re-run the MCP smoke tests; results must match Phase 1
- [ ] Delete the `mcp_shadow_smoke` test query

## Phase 4: Real-Data Verification on Test Server

Run only after Phases 0–3 pass. The test server has the User Schema
deployed and a ~2025-12-01 prod-data sync, but lacks the saved queries
(created on prod 2025-12-13+).

- [ ] Confirm `<claude-user>@uw.edu` still authenticates against the test
      server
- [ ] Recreate the four saved queries on the test server using the `.sql`
      mirrors
- [ ] Run the MCP smoke tests targeting dates with data (try `2025-12-01`
      and earlier)
- [ ] Diff against the dev-machine baseline — same shape, different row
      counts and computer names

## Phase 5: Cleanup and Findings

- [ ] File any regressions under `TODO-LK-20260403_testresults-bugs.md` or
      a new bug TODO
- [ ] Note MCP-side issues (e.g., `get_daily_test_summary` masking 401/404
      as "0 runs") for an MCP follow-up TODO
- [ ] Update Phase 7 of `TODO-LK-20260326_testresults-migrate-actions.md`
      with the outcome
- [ ] Tear down the dev instance / revert hosts redirect; leave the test
      server queries in place for further MCP iteration

## Notes

- Saved queries live in `query.QueryDef` keyed by
  `(container, schema_name, query_name)`. The shadow question is whether
  LabKey resolves them by schema *name* (port for free) or by schema
  *identity* (lost on registration). Phase 2 is the empirical answer.
- The MCP authenticates via `~/.netrc` / `~/_netrc` — no MCP-side
  configuration changes needed as long as `skyline.ms` resolves to the
  target machine and the account exists.
