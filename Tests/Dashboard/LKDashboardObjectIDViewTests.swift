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
        require(!view.copy(to: NSPasteboard.withUniqueName()), "hidden row must not copy")

        view.render(objectIdentifier: "0x1234")
        require(!view.isHidden, "valid Object ID must show the row")
        require(view.objectIdentifier == "0x1234", "rendered value must stay canonical")

        let pasteboard = NSPasteboard.withUniqueName()
        require(view.copy(to: pasteboard), "valid Object ID must copy")
        require(pasteboard.string(forType: .string) == "0x1234", "pasteboard must receive the exact MCP value")
        require(view.isShowingCopyFeedback, "successful copy must show feedback")
        require(!view.copy(using: { _ in false }), "failed writer must report failure")
        require(!view.isShowingCopyFeedback, "failed copy must clear stale success feedback")
        print("LKDashboardObjectIDViewTests passed")
    }
}
