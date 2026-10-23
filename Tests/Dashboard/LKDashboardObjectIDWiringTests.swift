import Foundation

@main
enum LKDashboardObjectIDWiringTests {
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

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            require(false, "repository root argument is required")
            return
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let dashboard = try String(
            contentsOf: root.appendingPathComponent("LookInside/Dashboard/DashboardViewController.swift"),
            encoding: .utf8
        )
        let lookup = try String(
            contentsOf: root.appendingPathComponent("LookInside/MCPBridge/MCPBridgeLiveDocumentLookup.swift"),
            encoding: .utf8
        )
        let header = try String(
            contentsOf: root.appendingPathComponent("LookInside/Dashboard/Search/DashboardHeaderView.swift"),
            encoding: .utf8
        )

        let layout = section(dashboard, from: "override func viewDidLayout()", to: "// MARK: - Rendering")
        guard let objectRow = layout.range(of: "objectIDView.dashboardLayout"),
              let cardLoop = layout.range(of: "for group in groupList") else {
            require(false, "layout must contain Object ID row and card loop")
            return
        }
        require(objectRow.lowerBound < cardLoop.lowerBound, "Object ID row must be laid out before Class and all cards")
        require(dashboard.contains("cardContainerView.addSubview(objectIDView)"), "Object ID row must live inside the card container")

        let reload = section(dashboard, from: "private func reload(groupList list:", to: "func reloadCurrentDisplayItem")
        require(reload.contains("currentDataSource()?.selectedItem"), "hierarchy selection must drive Object ID")
        require(reload.contains("LKMCPObjectIdentifierFormatter.objectIdentifier(for:"), "Dashboard must call shared formatter")
        require(reload.contains("objectIDView.render(objectIdentifier:"), "selection reload must refresh the row")
        require(dashboard.contains("observeSelectedItem(of:"), "selection changes must drive Dashboard reload")

        require(dashboard.contains("if !cardContainerView.isHidden"), "Object ID row must follow the same search visibility as cards")

        require(lookup.contains("LKMCPObjectIdentifierFormatter.objectIdentifier(for: item)"), "MCP must call shared formatter")
        require(!lookup.contains("String(format: \"0x%lx\""), "MCP lookup must not duplicate hex formatting")
        require(header.contains("dashboardHeaderViewDidRequestCustomPropertiesGuide"), "header must forward the guide request")
        require(!header.contains("Legacy custom property guides are disabled"), "disabled legacy alert must stay removed")
        print("LKDashboardObjectIDWiringTests passed")
    }
}
