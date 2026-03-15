# Skyline ChatGPT HTTP MCP Feasibility and Implementation TODO

## Purpose

Define a phased plan to evaluate and, if feasible, implement ChatGPT-compatible MCP connectivity for Skyline by extending the existing `SkylineMcpServer.exe` / `SkylineAiConnector.exe` architecture with an HTTP-based MCP transport while preserving the current named-pipe integration with running Skyline instances.

## Background

Current architecture:

```text
LLM client
  ↔ stdio MCP
SkylineMcpServer.exe
  ↔ named pipe JSON
running Skyline instance(s)
```

Target experimental architecture for ChatGPT:

```text
ChatGPT Desktop / ChatGPT
  ↔ MCP over HTTP
SkylineMcpServer.exe  (HTTP mode)
  ↔ named pipe JSON
running Skyline instance(s)
```

Design principles:

- Preserve Skyline's current named-pipe contract and `connection*.json` discovery model.
- Keep `SkylineMcpServer.exe` as the transport adapter and broker.
- Add HTTP mode as a second front end rather than redesigning the Skyline-facing implementation.
- Use phased validation to minimize sunk effort if ChatGPT proves not to support the required localhost configuration.
- Likely keep first public release focused on stdio-based MCP clients, while pursuing ChatGPT compatibility as a separate experimental track.

---

# Sprint 0 — Feasibility Confirmation

## Goals

- Confirm whether ChatGPT Desktop can be configured to connect to a custom MCP server by URL.
- Confirm whether `localhost` / `127.0.0.1` endpoints are accepted.
- Confirm any authentication, TLS, CORS, or connector-registration requirements relevant to a local HTTP MCP bridge.
- Determine whether the product limitation is architectural, policy-based, UI-based, or merely undocumented.

## Tasks

- Review current official OpenAI documentation for custom MCP / connector support.
- Test manual entry of a local MCP endpoint such as:
  - `http://127.0.0.1:<port>/`
  - `http://localhost:<port>/`
- Determine whether ChatGPT Desktop and web product behavior differ.
- Capture exact UI flow and error behavior for:
  - valid reachable endpoint
  - invalid endpoint
  - unreachable endpoint
  - non-MCP endpoint
- Determine whether HTTPS is required or whether plain HTTP loopback is acceptable.
- Determine whether OAuth can be bypassed or stubbed for loopback endpoints.
- Test whether ngrok or similar tunneling can bridge localhost to an HTTPS URL that ChatGPT accepts (common workaround in the MCP community).
- Check whether OpenAI has announced or is tracking stdio transport support.

## Deliverables

- Short feasibility note with screenshots and observed behavior.
- Decision: one of
  - `Feasible now`
  - `Feasible with caveats`
  - `Not currently feasible`
  - `Insufficient evidence; revisit later`

## Validation tests

### Test 0.1 — Manual connector registration
- Attempt to register a trivial local endpoint.
- Expected result: clear acceptance or rejection by ChatGPT UI.

### Test 0.2 — Localhost acceptance
- Register both `localhost` and `127.0.0.1`.
- Expected result: determine whether either form is blocked.

### Test 0.3 — MCP protocol recognition
- Point ChatGPT to a minimal MCP-compatible test server.
- Expected result: ChatGPT either recognizes tools/resources or returns a protocol-level error rather than a generic connection failure.

## Exit criteria

- Do not begin meaningful implementation work until there is enough evidence that ChatGPT can, in principle, consume a localhost MCP-over-HTTP endpoint.

---

# Sprint 1 — HTTP Transport Prototype in SkylineMcpServer.exe

## Goals

- Add an experimental HTTP server mode to `SkylineMcpServer.exe`.
- Reuse existing Skyline discovery and named-pipe broker logic.
- Avoid changes to Skyline's pipe protocol and current stdio mode.

## Tasks

- Investigate the `ModelContextProtocol` NuGet package's built-in streamable HTTP transport
  support. The library likely already handles this — the change may be primarily a transport
  configuration switch rather than a full architectural refactor.
- Preserve existing stdio MCP mode.
- Add experimental HTTP mode, for example:
  - `SkylineMcpServer.exe --mode=stdio`
  - `SkylineMcpServer.exe --mode=http --port=<port>`
- Ensure both transports call the same tool implementations (already the case if the
  `ModelContextProtocol` library handles transport switching).
- Continue discovering Skyline instances from `~\.skyline-mcp\connection*.json`.
- Continue routing requests to currently available named-pipe-backed Skyline instances.

## Design notes

- The HTTP server should be stable even when Skyline instances come and go.
- The HTTP mode should not assume a single Skyline instance.
- The broker should return useful messages when no Skyline instances are currently available.

## Deliverables

- Refactored `SkylineMcpServer.exe` with shared broker core.
- Prototype HTTP MCP mode, suitable for local manual testing.
- Developer notes describing startup arguments and logging behavior.

## Validation tests

### Test 1.1 — Regression test for stdio mode
- Existing Claude Desktop / Cursor / VS Code / Gemini CLI integrations still function unchanged.
- Expected result: no user-visible regression.

### Test 1.2 — HTTP mode startup
- Launch HTTP mode manually.
- Expected result: server starts, binds selected port, logs readiness, and remains running without Skyline attached.

### Test 1.3 — Dynamic Skyline discovery
- Start HTTP mode with no running Skyline instance, then launch Skyline.
- Expected result: HTTP mode begins serving Skyline-backed tools once a connection file and pipe become available.

### Test 1.4 — Skyline disappearance
- With HTTP mode running and Skyline connected, close Skyline.
- Expected result: requests fail gracefully with informative status; HTTP server remains alive.

### Test 1.5 — Multiple Skyline instances
- Run multiple Skyline instances with separate `connection*.json` entries.
- Expected result: broker correctly enumerates or routes among instances without crashing or mixing contexts incorrectly.

## Exit criteria

- HTTP transport works locally against the existing broker model.
- No regressions in stdio-based clients.

---

# Sprint 2 — Minimal ChatGPT Compatibility Test

## Goals

- Connect ChatGPT manually to the prototype HTTP MCP endpoint.
- Establish whether real end-to-end interoperability is possible.

## Tasks

- Stand up prototype HTTP mode locally.
- Attempt manual registration in ChatGPT Desktop.
- Verify whether tools appear and can be invoked.
- Test with a live Skyline instance and at least one simple operation.
- Record precise behavior if ChatGPT rejects, partially accepts, or inconsistently invokes the endpoint.

## Deliverables

- Compatibility findings document.
- Updated go/no-go recommendation.

## Validation tests

### Test 2.1 — Endpoint registration in ChatGPT
- Register the local Skyline MCP HTTP endpoint.
- Expected result: ChatGPT accepts the endpoint or gives a specific, reproducible error.

### Test 2.2 — Tool enumeration
- After registration, inspect whether Skyline tools/resources are visible to ChatGPT.
- Expected result: tools are discoverable, or failure is precise enough to diagnose.

### Test 2.3 — Live tool invocation
- Ask ChatGPT to perform a minimal Skyline-backed action.
- Expected result: action succeeds end to end, or failure identifies protocol/product mismatch.

### Test 2.4 — No-running-instance handling
- Repeat with no Skyline instance active.
- Expected result: graceful user-facing error rather than connector failure or timeout.

## Exit criteria

- Proceed only if end-to-end compatibility is demonstrated or appears close enough to justify another sprint.
- If ChatGPT fundamentally rejects localhost/custom MCP usage, stop and document the limitation.

---

# Sprint 3 — SkylineAiConnector.exe Local HTTP Bridge Management

## Goals

- Introduce practical lifecycle management for the HTTP MCP bridge.
- Make the local HTTP server discoverable and controllable by end users.

## Tasks

- Extend `SkylineAiConnector.exe` UI to include a ChatGPT / HTTP connector section.
- Show bridge state:
  - stopped
  - starting
  - running
  - failed
  - port in use
- Add controls:
  - Start
  - Stop
  - Restart
  - Copy endpoint URL
  - View logs
- Add settings:
  - start bridge at Windows startup
  - start bridge when Skyline starts
  - preferred port
  - auto-select port if unavailable
- Decide whether the bridge should be:
  - per-user background process
  - tray application
  - Windows startup item
  - optional service-like helper without becoming a real Windows Service

## UI considerations

- This UI should clearly distinguish:
  - stdio registrations that are owned by the AI client process
  - HTTP bridge mode that must already be running before ChatGPT uses it
- The ChatGPT experience should feel as close to turnkey as practical, despite its different ownership model.

## Deliverables

- Updated `SkylineAiConnector.exe` with bridge management UI.
- Local configuration persistence.
- Status/logging surface sufficient for support and troubleshooting.

## Validation tests

### Test 3.1 — Manual bridge control
- Start and stop the HTTP bridge from the UI.
- Expected result: process lifecycle reflects correctly in UI.

### Test 3.2 — Startup behavior
- Enable start at Windows startup and reboot/sign in.
- Expected result: bridge starts automatically and shows running state.

### Test 3.3 — Port conflict handling
- Occupy the configured port before bridge startup.
- Expected result: clear error and recovery path, with optional alternate port selection.

### Test 3.4 — Crash recovery
- Force bridge termination while UI is open.
- Expected result: UI detects stopped state and allows restart.

### Test 3.5 — Log visibility
- Trigger both successful and failed connector activity.
- Expected result: enough information is visible to diagnose common setup issues.

## Exit criteria

- Bridge can be managed reliably by non-developer users.
- Support burden appears acceptable.

---

# Sprint 4 — Productization, Documentation, and Release Decision

## Goals

- Decide whether to ship ChatGPT support as experimental, preview, or deferred.
- Prepare user-facing documentation and support boundaries.

## Tasks

- Document installation and setup steps for ChatGPT users.
- Document limitations, including:
  - local bridge must already be running
  - ChatGPT configuration may be more manual than stdio clients
  - behavior may change with ChatGPT product updates
- Decide release label:
  - hidden experimental feature
  - advanced preview
  - supported beta
  - defer from release
- Add diagnostic export for support cases.
- Add versioned compatibility notes.

## Deliverables

- User documentation.
- Internal support guide / troubleshooting checklist.
- Release decision memo.

## Validation tests

### Test 4.1 — Clean-machine setup
- On a machine without prior development tooling, install Skyline + AI Connector and configure ChatGPT support.
- Expected result: setup is understandable and reproducible.

### Test 4.2 — Documentation walkthrough
- Follow the docs literally from a fresh user perspective.
- Expected result: no hidden assumptions.

### Test 4.3 — Upgrade compatibility
- Upgrade from a build without HTTP bridge support to one with it.
- Expected result: no regressions in existing stdio connector registrations.

## Exit criteria

- Feature is documented well enough for real users.
- Release scope is explicit and supportable.

---

# Suggested sequencing relative to first release

## Recommended plan

- First release:
  - ship stdio-based MCP client support only
  - do not block release on ChatGPT support
- In parallel or immediately after:
  - complete Sprint 0
  - complete Sprint 1 only if Sprint 0 is promising
  - complete Sprint 2 before investing heavily in polished UI
- Only proceed to Sprint 3 if Sprint 2 demonstrates practical interoperability

This sequencing reduces the risk of spending significant effort on UI and lifecycle management before confirming that ChatGPT will actually consume the local HTTP MCP server.

---

# Open technical questions

- Does ChatGPT Desktop truly allow custom MCP endpoints that point to loopback addresses?
- Is HTTP over loopback sufficient, or is HTTPS required?
- Are there authentication requirements even for localhost? Can OAuth be stubbed?
- Does ChatGPT maintain a persistent session, or does it reconnect frequently enough that startup timing matters?
- Are there constraints on long-lived connections, streaming, or request duration that differ from current stdio clients?
- How should multiple Skyline instances be represented to ChatGPT:
  - explicit tool parameters
  - instance selection tool
  - automatically chosen default instance
- Should the HTTP bridge remain running with no Skyline instances, or should it idle-exit after a timeout?
- Could the HTTP transport also serve other future HTTP-only MCP clients (not just ChatGPT),
  making the investment more broadly useful?
- As of 2026-03-15, ChatGPT MCP requires Business/Enterprise/Edu plans — is OpenAI likely
  to expand to Plus/free tiers?

---

# Strategic context (2026-03-15)

As of this date, ChatGPT MCP support is remote-only (streamable HTTP/SSE with OAuth),
beta, and restricted to Business/Enterprise/Edu plans. There is no stdio support and no
indication OpenAI plans to add it. Meanwhile, Claude Desktop, Claude Code, Gemini CLI,
VS Code Copilot, and Cursor all support stdio and are already integrated.

The competitive dynamic may resolve this naturally: if Anthropic continues to gain
productivity/cowork market share with better local MCP support, OpenAI may follow with
stdio or at least localhost HTTP. Waiting costs little since our stdio architecture
already covers the major clients. Revisit when OpenAI's position changes or when user
requests for ChatGPT support become frequent.

Original plan drafted by ChatGPT in collaboration with brendanx, reviewed and annotated
by Claude (2026-03-15).

# Recommendation

Proceed deliberately:

1. Treat ChatGPT support as a feasibility investigation, not a committed release feature.
2. Preserve the existing stdio architecture unchanged for currently supported MCP clients.
3. Add HTTP mode to `SkylineMcpServer.exe` only after confirming that ChatGPT can plausibly use a localhost MCP endpoint.
4. Defer `SkylineAiConnector.exe` UX investment until end-to-end ChatGPT interoperability is demonstrated.
5. Expect the first public release to ship without ChatGPT support unless feasibility is confirmed quickly and cleanly.

This approach keeps effort proportional to evidence while preserving a clear path toward eventual GUI-first LLM client integration.
