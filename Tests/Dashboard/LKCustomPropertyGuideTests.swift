import AppKit

@main
enum LKCustomPropertyGuideTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() {
        _ = NSApplication.shared
        let code = LKCustomPropertyGuideWindowController.exampleCode
        ["lookin_customDebugInfos", "properties", "title", "section", "valueType", "value", "retainedSetter"].forEach {
            require(code.contains($0), "example must contain \($0)")
        }
        require(code.contains("weakSelf"), "editable example must avoid retaining the inspected view")

        let pasteboard = NSPasteboard.withUniqueName()
        require(LKCustomPropertyGuideWindowController.copyExampleCode(to: pasteboard), "example code must copy")
        require(pasteboard.string(forType: .string) == code, "pasteboard must receive the complete example")
        print("LKCustomPropertyGuideTests passed")
    }
}
