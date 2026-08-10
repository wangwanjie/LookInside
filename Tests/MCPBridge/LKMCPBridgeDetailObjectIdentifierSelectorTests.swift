import Foundation

@main
enum LKMCPBridgeDetailObjectIdentifierSelectorTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func testIOSTargetPrefersLayer() {
        let identifier = LKMCPBridgeDetailObjectIdentifierSelector.select(
            targetIsMac: false,
            layerObjectIdentifier: 0x2b01,
            viewObjectIdentifier: 0x2afe,
            windowObjectIdentifier: 0x100
        )
        require(identifier == 0x2b01, "iOS RPC 203 must use the layer OID before the view OID")
    }

    static func testMacTargetPrefersView() {
        let identifier = LKMCPBridgeDetailObjectIdentifierSelector.select(
            targetIsMac: true,
            layerObjectIdentifier: 0x2b01,
            viewObjectIdentifier: 0x2afe,
            windowObjectIdentifier: 0x100
        )
        require(identifier == 0x2afe, "AppKit RPC 203 must use the view OID before the layer OID")
    }

    static func testFallsBackAcrossObjectKinds() {
        require(
            LKMCPBridgeDetailObjectIdentifierSelector.select(
                targetIsMac: false,
                layerObjectIdentifier: 0,
                viewObjectIdentifier: 0x2afe,
                windowObjectIdentifier: 0x100
            ) == 0x2afe,
            "iOS must fall back to a view when a display item has no layer"
        )
        require(
            LKMCPBridgeDetailObjectIdentifierSelector.select(
                targetIsMac: true,
                layerObjectIdentifier: 0,
                viewObjectIdentifier: 0,
                windowObjectIdentifier: 0x100
            ) == 0x100,
            "window OID must be the final fallback"
        )
        require(
            LKMCPBridgeDetailObjectIdentifierSelector.select(
                targetIsMac: false,
                layerObjectIdentifier: 0,
                viewObjectIdentifier: 0,
                windowObjectIdentifier: 0
            ) == nil,
            "an item without a runtime object must remain unresolved"
        )
    }

    static func main() {
        testIOSTargetPrefersLayer()
        testMacTargetPrefersView()
        testFallsBackAcrossObjectKinds()
        print("LKMCPBridgeDetailObjectIdentifierSelectorTests passed")
    }
}
