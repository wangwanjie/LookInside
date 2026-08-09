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
        let models = try source(at: "LookInside/MCPBridge/LKMCPBridgeInspectionModels.swift", root: root)
        require(models.contains("public let parentObjectIdentifier: String?"), "view node model must expose parentObjectIdentifier")
        require(models.contains("public struct LKMCPBridgeViewDetail: Sendable, Codable"), "details model must exist")
    }

    static func testService(root: URL) throws {
        let service = try source(at: "LookInside/MCPBridge/LKMCPBridgeInspectionService.swift", root: root)
        require(service.contains("let parentIdentity = item.superItem.map"), "service must derive parent identity from superItem")
        require(service.contains("parentObjectIdentifier: parentIdentity"), "service must encode the parent object identifier")
        require(service.contains("makeViewNode(from: $0, remainingDepth: nextDepth)"), "service must recurse through children")
    }

    static func testDetailsService(root: URL) throws {
        let models = try source(at: "LookInside/MCPBridge/LKMCPBridgeInspectionModels.swift", root: root)
        let details = try source(at: "LookInside/MCPBridge/LKMCPBridgeDetailsService.swift", root: root)
        require(models.contains("public let parentObjectIdentifier: String?\n    public let groups: [LKMCPBridgeAttributeGroup]"), "view detail model must expose parentObjectIdentifier")
        require(details.contains("parentObjectIdentifier: resolved.displayItem.superItem.map("), "details.read must encode parent object identifier from superItem")
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
