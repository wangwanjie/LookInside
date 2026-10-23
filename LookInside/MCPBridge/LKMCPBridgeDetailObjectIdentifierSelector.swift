import Foundation

/// Chooses the runtime object identifier accepted by RPC 203.
///
/// Hierarchy identifiers intentionally use the display object (usually a
/// view), while the iOS server's hierarchy-details handler accepts CALayer
/// identifiers. AppKit targets can handle NSView identifiers directly.
enum LKMCPBridgeDetailObjectIdentifierSelector {
    static func select(
        targetIsMac: Bool,
        layerObjectIdentifier: UInt,
        viewObjectIdentifier: UInt,
        windowObjectIdentifier: UInt
    ) -> UInt? {
        let candidates = targetIsMac
            ? [viewObjectIdentifier, layerObjectIdentifier, windowObjectIdentifier]
            : [layerObjectIdentifier, viewObjectIdentifier, windowObjectIdentifier]
        return candidates.first(where: { $0 != 0 })
    }
}
