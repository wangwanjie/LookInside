import AppKit

@main
enum LKCustomPropertyGuideTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    static func main() {
        _ = NSApplication.shared
        let code = LKCustomPropertyGuideWindowController.exampleCode
        ["lookin_customDebugInfos", "properties", "title", "section", "valueType", "value", "retainedSetter"].forEach {
            require(code.contains($0), "example must contain \($0)")
        }
        require(code.contains("weakSelf"), "editable example must avoid retaining the inspected view")

        let fieldExplanation = LKCustomPropertyGuideWindowController.fieldExplanation
        ["title", "section", "valueType", "value", "retainedSetter", "read-only", "editable"].forEach {
            require(fieldExplanation.contains($0), "field explanation must contain \($0)")
        }

        let pasteboard = NSPasteboard.withUniqueName()
        require(LKCustomPropertyGuideWindowController.copyExampleCode(to: pasteboard), "example code must copy")
        require(pasteboard.string(forType: .string) == code, "pasteboard must receive the complete example")

        LKCustomPropertyGuideWindowController.showGuideWindow()
        guard let firstWindow = LKCustomPropertyGuideWindowController.guideWindow,
              let contentView = firstWindow.contentView else {
            require(false, "guide window must be created")
            return
        }
        contentView.layoutSubtreeIfNeeded()
        let allViews = descendants(of: contentView)
        let fieldLabel = allViews
            .compactMap { $0 as? NSTextField }
            .first { $0.identifier?.rawValue == "lookinside.custom-property-guide.fields" }
        require(fieldLabel?.stringValue == fieldExplanation, "field explanation must be rendered in the window")
        require(allViews.contains { ($0 as? NSTextView)?.string == code }, "complete example must be rendered")
        require(allViews.contains { ($0 as? NSButton)?.identifier?.rawValue == "lookinside.custom-property-guide.copy" }, "copy button must be rendered")

        LKCustomPropertyGuideWindowController.showGuideWindow()
        require(LKCustomPropertyGuideWindowController.guideWindow === firstWindow, "repeated opens must reuse one window")
        firstWindow.close()
        LKCustomPropertyGuideWindowController.showGuideWindow()
        require(LKCustomPropertyGuideWindowController.guideWindow === firstWindow, "closed guide must reopen the same window")
        require(firstWindow.isVisible, "closed guide must become visible when reopened")
        firstWindow.orderOut(nil)
        print("LKCustomPropertyGuideTests passed")
    }
}
