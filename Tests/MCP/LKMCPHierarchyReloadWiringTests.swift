import Foundation

@main
enum LKMCPHierarchyReloadWiringTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func section(_ source: String, from start: String, to end: String) -> String {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            return ""
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    static func source(at relativePath: String, root: URL) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    static func testController(root: URL) throws {
        let header = try source(at: "LookInside/Static/LKStaticWindowController.h", root: root)
        let implementation = try source(at: "LookInside/Static/LKStaticWindowController.m", root: root)

        require(header.contains("LKHierarchyReloadTriggerResultStarted"), "header must publish the started result")
        require(header.contains("LKHierarchyReloadTriggerResultJoinedExistingReload"), "header must publish the joined-reload result")
        require(header.contains("LKHierarchyReloadTriggerResultCancelledDetailsFetch"), "header must publish detail cancellation")
        require(header.contains("typedef void (^LKHierarchyReloadCompletion)"), "header must publish the completion type")
        require(header.contains("- (LKHierarchyReloadTriggerResult)triggerHierarchyReload;"), "header must publish the shared trigger")
        require(header.contains("triggerHierarchyReloadWithCompletion:(nullable LKHierarchyReloadCompletion)completion"), "header must publish the awaitable trigger")

        let toolbarAction = section(implementation, from: "- (void)_handleReload", to: "- (LKHierarchyReloadTriggerResult)triggerHierarchyReload")
        require(toolbarAction.contains("[self triggerHierarchyReload]"), "toolbar action must delegate to the shared trigger")

        let trigger = section(implementation, from: "- (LKHierarchyReloadTriggerResult)triggerHierarchyReload", to: "- (void)_handleApp")
        require(trigger.contains("triggerHierarchyReloadWithCompletion:nil"), "toolbar trigger must call the awaitable entry")
        require(trigger.contains("hierarchyReloadCompletionBlocks"), "trigger must retain active reload waiters")
        require(trigger.contains("[self.asyncUpdateManager endUpdating]"), "trigger must preserve detail cancellation")
        require(trigger.contains("if (self.isFetchingHierarchy)"), "trigger must preserve the hierarchy single-flight guard")
        require(trigger.contains("LKHierarchyReloadTriggerResultJoinedExistingReload"), "active reload callers must join the existing request")
        require(trigger.contains("[[app fetchHierarchyData] subscribeNext:"), "trigger must start the existing asynchronous hierarchy fetch")

        guard let cacheUpdate = trigger.range(of: "reloadWithHierarchyInfo:info keepState:YES"),
              let successCompletion = trigger.range(of: "_finishHierarchyReloadWithError:nil") else {
            require(false, "successful reload must update the cache and finish waiters")
            return
        }
        require(cacheUpdate.lowerBound < successCompletion.lowerBound, "success waiters must finish after the desktop cache update")
        require(trigger.contains("_finishHierarchyReloadWithError:error"), "failure waiters must receive the phone error")

        print("LKMCPHierarchyReloadWiringTests controller passed")
    }

    static func testBridge(root: URL) throws {
        let bridgingHeader = try source(at: "LookInside/Base/LookinClient-Bridging-Header.h", root: root)
        let server = try source(at: "LookInside/MCPBridge/LKMCPBridgeServer.swift", root: root)
        let invocation = try source(at: "LookInside/MCPBridge/LKMCPBridgeInvocationService.swift", root: root)

        require(bridgingHeader.contains("#import \"LKStaticWindowController.h\""), "Swift bridge must expose the shared trigger")
        require(server.contains("case \"invoke.method\", \"hierarchy.reload\":"), "server must route reload through the RPC service")
        require(invocation.contains("case \"hierarchy.reload\":"), "invocation service must dispatch reload")
        require(invocation.contains("LKMCPBridgeLiveDocumentLookup.findLiveDocument"), "reload must resolve the requested target")
        require(invocation.contains("triggerHierarchyReload { error in"), "reload must use the awaitable desktop trigger")
        require(invocation.contains("withCheckedContinuation"), "reload must await the desktop completion")
        require(invocation.contains("\"reloaded\""), "reload must encode completion success")
        require(invocation.contains("\"hierarchy.reloadFailed\""), "reload must expose phone fetch failures")
        require(invocation.contains("\"cancelledDetailsFetch\""), "reload must encode detail cancellation")

        print("LKMCPHierarchyReloadWiringTests bridge passed")
    }

    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            require(false, "usage: LKMCPHierarchyReloadWiringTests <repository-root> <mode>")
            return
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        switch CommandLine.arguments[2] {
        case "controller":
            try testController(root: root)
        case "bridge":
            try testBridge(root: root)
        default:
            require(false, "unknown mode: \(CommandLine.arguments[2])")
        }
    }
}
