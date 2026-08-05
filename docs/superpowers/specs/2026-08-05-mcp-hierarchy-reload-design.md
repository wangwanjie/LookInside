# MCP Hierarchy Reload Design

## Goal

Add an MCP tool that performs the same hierarchy reload as LookInside's “重新加载” button and does not return until the phone hierarchy has been fetched and the desktop hierarchy data source has been updated.

## Public interface

The stdio MCP shim exposes `hierarchy_reload` with one required string argument, `targetIdentifier`, and maps it to the internal bridge method `hierarchy.reload`.

After `reloadWithHierarchyInfo` has updated the desktop cache, the tool returns:

```json
{
  "reloaded": true
}
```

Therefore, a subsequent `hierarchy_read` observes the refreshed desktop hierarchy.

The toolbar button is also the stop control while hierarchy details are being fetched. To remain equivalent to clicking it, an MCP call in that state stops the detail fetch and returns:

```json
{
  "reloaded": false,
  "reason": "cancelledDetailsFetch"
}
```

## Architecture

`LKStaticWindowController` exposes one shared reload entry used by both the toolbar action and MCP. The entry accepts an optional completion block and owns the existing guards, progress UI, phone request, cache replacement, performance reporting, and error sheet.

The controller keeps completion blocks for the active hierarchy reload. The first caller starts the phone request. A caller arriving while that request is active joins it without starting another request. After success, the controller first calls `reloadWithHierarchyInfo`, clears the fetching state, and then completes every waiter. After failure, it resets the existing UI state, shows the existing error sheet, and completes every waiter with the error.

`LKMCPBridgeServer` routes `hierarchy.reload` through `LKMCPBridgeInvocationService`. The service resolves `targetIdentifier` to the matching live document and `LKStaticWindowController`, converts the completion callback to Swift async continuation, and replies only after completion.

The Node shim remains the MCP protocol boundary. It advertises `hierarchy_reload`, validates the argument schema, maps the method, and naturally keeps the MCP call open while the Unix-socket bridge request is pending.

## Data flow

1. The MCP client sends `tools/call` for `hierarchy_reload` over stdio.
2. The shim sends a `hierarchy.reload` request through the local Unix socket.
3. LookInside resolves the requested live inspection document and window controller.
4. The shared reload entry starts a phone hierarchy request, or joins the request already in progress.
5. On success, LookInside updates `hierarchyDataSource` with the new `LookinHierarchyInfo`.
6. The controller resolves its queued completions.
7. The Bridge returns `{ "reloaded": true }`, and the shim returns the MCP tool result.

## Error handling

- Missing or malformed `targetIdentifier`: `dispatch.invalidParameters`.
- No matching live document: `hierarchy.targetNotFound`.
- No compatible live window controller or inspectable app: `hierarchy.notReady`.
- Phone hierarchy request failure: preserve the desktop error sheet and return `hierarchy.reloadFailed` with the underlying localized message.
- Detail fetch in progress: stop it and return `{ "reloaded": false, "reason": "cancelledDetailsFetch" }` without starting a hierarchy reload.

An already-running hierarchy reload is not an error. MCP joins it and receives the same final success or failure.

## Testing

Tests cover:

- The shared controller API accepts completion callbacks.
- The toolbar delegates to the shared entry without waiting.
- Concurrent callers join the active reload rather than starting another request.
- Success callbacks run after `reloadWithHierarchyInfo`; failure callbacks receive the phone error.
- The Bridge awaits completion and maps success, cancellation, and failure to the documented payloads.
- The real Node shim advertises `hierarchy_reload`, forwards it as `hierarchy.reload`, and carries the delayed bridge response back to MCP.

Verification runs focused MCP reload tests, existing MCP-adjacent dashboard tests, and an unsigned Debug build.

## Out of scope

- Returning the hierarchy tree inside the reload response.
- Progress notifications or hierarchy version tokens.
- Automatically starting a full reload after cancelling an in-progress detail fetch.
- Changing the Peertalk/USB communication between LookInside and the inspected app.
