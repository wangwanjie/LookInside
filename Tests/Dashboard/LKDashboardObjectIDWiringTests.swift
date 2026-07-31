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
            contentsOf: root.appendingPathComponent("LookInside/Dashboard/LKDashboardViewController.m"),
            encoding: .utf8
        )
        let lookup = try String(
            contentsOf: root.appendingPathComponent("LookInside/MCPBridge/LKMCPBridgeLiveDocumentLookup.swift"),
            encoding: .utf8
        )
        let header = try String(
            contentsOf: root.appendingPathComponent("LookInside/Dashboard/Search/LKDashboardHeaderView.m"),
            encoding: .utf8
        )

        let layout = section(dashboard, from: "- (void)viewDidLayout", to: "- (NSArray<LookinAttributesGroup *> *)_groupListForDisplayItem:")
        guard let objectRow = layout.range(of: "$(self.objectIDView)"),
              let cardLoop = layout.range(of: "[self.groupList enumerateObjectsUsingBlock:") else {
            require(false, "layout must contain Object ID row and card loop")
            return
        }
        require(objectRow.lowerBound < cardLoop.lowerBound, "Object ID row must be laid out before Class and all cards")
        require(dashboard.contains("[self.cardContainerView addSubview:self.objectIDView]"), "Object ID row must live inside the card container")

        let reload = section(dashboard, from: "- (void)reloadWithGroupList:", to: "- (void)reloadCurrentDisplayItem")
        require(reload.contains("self.staticDataSource.selectedItem"), "live/static selection must drive Object ID")
        require(!reload.contains("self.readDataSource.selectedItem"), "archive/read selection must not expose MCP Object ID")
        require(reload.contains("objectIdentifierForDisplayItem:selectedItem"), "Dashboard must call shared formatter")
        require(reload.contains("renderWithObjectIdentifier:objectIdentifier"), "selection reload must refresh the row")
        require(dashboard.contains("RACObserve(self.staticDataSource, selectedItem)"), "selection changes must drive Dashboard reload")

        let searchToggle = section(dashboard, from: "- (void)dashboardHeaderView:(LKDashboardHeaderView *)view didToggleActive:", to: "#pragma mark - <LKDashboardSearchMethodsViewDelegate>")
        require(searchToggle.contains("self.cardContainerView.animator.hidden = YES"), "search activation must hide the Object ID container")
        require(searchToggle.contains("self.cardContainerView.animator.hidden = NO"), "search dismissal must restore the Object ID container")

        require(lookup.contains("LKMCPObjectIdentifierFormatter.objectIdentifier(for: item)"), "MCP must call shared formatter")
        require(!lookup.contains("String(format: \"0x%lx\""), "MCP lookup must not duplicate hex formatting")
        require(header.contains("dashboardHeaderViewDidRequestCustomPropertiesGuide"), "header must forward the guide request")
        require(!header.contains("Legacy custom property guides are disabled"), "disabled legacy alert must stay removed")
        print("LKDashboardObjectIDWiringTests passed")
    }
}
