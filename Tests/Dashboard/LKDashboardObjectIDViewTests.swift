import AppKit

@main
enum LKDashboardObjectIDViewTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() {
        _ = NSApplication.shared
        let view = LKDashboardObjectIDView(frame: NSRect(x: 0, y: 0, width: 280, height: 34))
        view.render(objectIdentifier: nil)
        require(view.isHidden, "nil Object ID must hide the row")
        require(!view.copy(using: { _ in true }), "hidden row must not copy")

        view.render(objectIdentifier: "0x1234")
        require(!view.isHidden, "valid Object ID must show the row")
        require(view.objectIdentifier == "0x1234", "rendered value must stay canonical")

        var copiedIdentifier: String?
        require(view.copy(using: {
            copiedIdentifier = $0
            return true
        }), "valid Object ID must copy")
        require(copiedIdentifier == "0x1234", "writer must receive the exact MCP value")
        require(view.isShowingCopyFeedback, "successful copy must show feedback")
        require(!view.copy(using: { _ in false }), "failed writer must report failure")
        require(!view.isShowingCopyFeedback, "failed copy must clear stale success feedback")
        print("LKDashboardObjectIDViewTests passed")
    }
}
