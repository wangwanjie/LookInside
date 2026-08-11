import Foundation

@main
enum LookinAppInfoMacScreenshotTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func sourceSection(_ source: String, from start: String, to end: String) -> String {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            return ""
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            require(false, "usage: LookinAppInfoMacScreenshotTests <repository-root>")
            return
        }

        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let sourceURL = root.appendingPathComponent("Sources/LookinCore/LookinAppInfo.m")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let windowSelection = sourceSection(
            source,
            from: "+ (LookinWindow *)_lookinScreenshotWindow",
            to: "+ (LookinImage *)screenshotImage"
        )
        let screenshot = sourceSection(
            source,
            from: "+ (LookinImage *)screenshotImage",
            to: "+ (BOOL)isSimulator"
        )

        require(!windowSelection.isEmpty, "macOS screenshot capture must select an eligible content window")
        require(windowSelection.contains("largestVisibleWindow"), "window fallback must prefer the largest visible content window")
        require(windowSelection.contains("candidate.isVisible"), "window fallback must reject hidden windows")
        require(windowSelection.contains("candidate.isMiniaturized"), "window fallback must reject miniaturized windows")
        require(!screenshot.contains("windows.firstObject"), "screenshot capture must not select NSStatusBarWindow by array order")
        require(screenshot.contains("[self _lookinScreenshotWindow]"), "screenshot capture must use the content-window selector")
        require(screenshot.contains("CGRectNull"), "CGWindowListCreateImage must use the selected window bounds")

        print("LookinAppInfo macOS screenshot tests passed")
    }
}
