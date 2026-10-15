import Foundation

@main
enum LKMCPHierarchyParentWiringTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func source(at relativePath: String, root: URL) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    static func testModel(root: URL) throws {
        let models = try source(at: "LookInside/MCPBridge/MCPBridgeInspectionModels.swift", root: root)
        require(models.contains("let parentObjectIdentifier: String?"), "view node model must expose parentObjectIdentifier")
        require(models.contains("struct MCPBridgeViewDetail: Sendable, Codable"), "details model must exist")
    }

    static func testService(root: URL) throws {
        let service = try source(at: "LookInside/MCPBridge/MCPBridgeInspectionService.swift", root: root)
        let lookup = try source(at: "LookInside/MCPBridge/MCPBridgeLiveDocumentLookup.swift", root: root)
        require(lookup.contains("static func parent(of item: DisplayItem) -> DisplayItem?"), "lookup must expose a parent accessor")
        require(lookup.contains("item.value(forKey: \"superItem\")"), "lookup parent accessor must read superItem")
        require(service.contains("let parentIdentity = MCPBridgeLiveDocumentLookup.parent(of: item).map("), "service must derive parent identity through the shared parent accessor")
        require(service.contains("parentObjectIdentifier: parentIdentity"), "service must encode the parent object identifier")
        require(service.contains("makeViewNode(from: $0, remainingDepth: nextDepth, includeLayoutGuides: includeLayoutGuides, includeCells: includeCells)"), "service must recurse through children while preserving node filters")
    }

    static func testDetailsService(root: URL) throws {
        let models = try source(at: "LookInside/MCPBridge/MCPBridgeInspectionModels.swift", root: root)
        let details = try source(at: "LookInside/MCPBridge/MCPBridgeDetailsService.swift", root: root)
        require(models.contains("let parentObjectIdentifier: String?\n    let groups: [MCPBridgeAttributeGroup]"), "view detail model must expose parentObjectIdentifier")
        require(details.contains("parentObjectIdentifier: MCPBridgeLiveDocumentLookup.parent(of: resolved.displayItem).map("), "details.read must encode parent object identifier through the shared parent accessor")
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            require(false, "usage: LKMCPHierarchyParentWiringTests <repository-root>")
            return
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        try testModel(root: root)
        try testService(root: root)
        try testDetailsService(root: root)
        print("LKMCPHierarchyParentWiringTests passed")
    }
}
