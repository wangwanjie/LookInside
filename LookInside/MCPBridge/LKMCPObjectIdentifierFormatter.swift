import Foundation

@objc(LKMCPObjectIdentifierFormatter)
final class LKMCPObjectIdentifierFormatter: NSObject {
    @objc(stringForOID:)
    static func string(forOID oid: UInt) -> String? {
        guard oid != 0 else { return nil }
        return String(format: "0x%lx", oid)
    }

    @objc(objectIdentifierForDisplayItem:)
    static func objectIdentifier(for item: LookinDisplayItem) -> String? {
        string(forOID: item.displayingObject()?.oid ?? 0)
    }
}
