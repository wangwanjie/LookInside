# MCP Hierarchy Reload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a waiting `hierarchy_reload` MCP tool that responds only after the phone hierarchy has updated LookInside's desktop cache.

**Architecture:** A completion-capable `LKStaticWindowController` entry is shared by the toolbar and MCP and coalesces concurrent reload callers. The Swift Bridge awaits that completion, while the Node shim translates between MCP stdio JSON-RPC and the existing Unix-socket protocol.

**Tech Stack:** Objective-C/AppKit, Swift concurrency, Node.js, Unix domain sockets, Swift/Node focused tests, Xcode.

---

### Task 1: Make the shared desktop reload awaitable

**Files:**
- Modify: `Tests/MCP/LKMCPHierarchyReloadWiringTests.swift`
- Modify: `LookInside/Static/LKStaticWindowController.h`
- Modify: `LookInside/Static/LKStaticWindowController.m`

- [ ] Extend the controller test first to require `LKHierarchyReloadCompletion`, `triggerHierarchyReloadWithCompletion:`, an active completion collection, joining `isFetchingHierarchy`, and completion after `reloadWithHierarchyInfo`.
- [ ] Run `rtk bash Scripts/test-mcp-hierarchy-reload.sh controller`; expect failure because the current trigger is fire-and-forget.
- [ ] Add `LKHierarchyReloadTriggerResultJoinedExistingReload` and the nullable completion-block API. Keep `triggerHierarchyReload` as the toolbar wrapper.
- [ ] Store completions for the active request. If `isFetchingHierarchy`, append the new completion and return `JoinedExistingReload`. On a new request, append before subscribing.
- [ ] On success, update the hierarchy data source and existing UI state before completing all waiters with `nil`. On failure, preserve the existing reset/error sheet and complete all waiters with the `NSError`.
- [ ] Run the focused controller test; expect PASS.
- [ ] Commit only the controller/test changes with `git commit -m "refactor: make hierarchy reload awaitable"`.

The public API is:

```objc
typedef void (^LKHierarchyReloadCompletion)(NSError *_Nullable error);

- (LKHierarchyReloadTriggerResult)triggerHierarchyReload;
- (LKHierarchyReloadTriggerResult)triggerHierarchyReloadWithCompletion:(nullable LKHierarchyReloadCompletion)completion;
```

### Task 2: Await reload completion in the Bridge

**Files:**
- Modify: `Tests/MCP/LKMCPHierarchyReloadWiringTests.swift`
- Modify: `LookInside/MCPBridge/LKMCPBridgeInvocationService.swift`

- [ ] Change the bridge test first to require `triggerHierarchyReloadWithCompletion`, `withCheckedContinuation`, `"reloaded"`, and `"hierarchy.reloadFailed"`; remove the old immediate-ack assertions.
- [ ] Run `rtk bash Scripts/test-mcp-hierarchy-reload.sh bridge`; expect failure because the Bridge still returns immediately.
- [ ] Add a private Swift outcome enum for success, phone failure, detail cancellation, and not-ready states.
- [ ] Convert the controller callback to `await withCheckedContinuation`. For `.started` and `.joinedExistingReload`, resume only from the completion callback. Resume cancellation/not-ready states immediately.
- [ ] Return `{ "reloaded": true }` after successful completion, `{ "reloaded": false, "reason": "cancelledDetailsFetch" }` for cancellation, and `hierarchy.reloadFailed` for phone errors.
- [ ] Run controller and bridge focused tests; expect both PASS.
- [ ] Commit the Bridge/test changes with `git commit -m "feat: await hierarchy reload completion"`.

### Task 3: Expose the MCP shim tool

**Files:**
- Create: `Tests/MCP/lookinside-mcp-shim-reload-tests.mjs`
- Modify: `Scripts/test-mcp-hierarchy-reload.sh`
- Modify: `Scripts/lookinside-mcp-shim.mjs`

- [ ] Run the real-shim test against a temporary Unix socket and confirm RED because `hierarchy_reload` is not advertised. If sandbox socket creation is denied, rerun the same focused test with approval.
- [ ] Add `hierarchy_reload: "hierarchy.reload"` to `bridgeMethods` and advertise a tool requiring `targetIdentifier`.
- [ ] Make the fake Bridge delay its response briefly and return `{ "reloaded": true }`; assert the shim forwards the request and does not resolve the MCP call before the delayed response.
- [ ] Run `rtk bash Scripts/test-mcp-hierarchy-reload.sh shim`; expect PASS.
- [ ] Commit the shim and tests with `git commit -m "feat: expose hierarchy reload MCP tool"`.

The tool schema is:

```javascript
{
  name: "hierarchy_reload",
  description: "Reload the target hierarchy and wait until LookInside updates its desktop cache.",
  inputSchema: {
    type: "object",
    additionalProperties: false,
    required: ["targetIdentifier"],
    properties: { targetIdentifier: { type: "string" } },
  },
}
```

### Task 4: Verify the complete feature

**Files:** Verify only; fix only failures caused by this feature.

- [ ] Run all focused modes: `controller`, `bridge`, and `shim`.
- [ ] Run `rtk bash Scripts/test-dashboard-features.sh`.
- [ ] Run `rtk xcodebuild -project LookInside.xcodeproj -scheme LookInside -configuration Debug -derivedDataPath /tmp/LookInside-MCPReload-DerivedData CODE_SIGNING_ALLOWED=NO build`.
- [ ] Run `rtk git diff --check` and inspect `rtk git status --short` to ensure pre-existing user changes were not included in feature commits.
