import Foundation

@main
enum LKMCPObjectIdentifierFormatterTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() {
        require(LKMCPObjectIdentifierFormatter.string(forOID: 0) == nil, "zero OID must be invalid")
        require(LKMCPObjectIdentifierFormatter.string(forOID: 0x2A) == "0x2a", "OID must be lowercase hexadecimal")
        require(LKMCPObjectIdentifierFormatter.string(forOID: UInt.max) == "0xffffffffffffffff", "full-width OID must not truncate")

        let item = LookinDisplayItem()
        require(LKMCPObjectIdentifierFormatter.objectIdentifier(for: item) == nil, "missing display object must be invalid")
        let object = LookinObject()
        object.oid = 0x1234
        item.mockedDisplayingObject = object
        require(LKMCPObjectIdentifierFormatter.objectIdentifier(for: item) == "0x1234", "displaying object OID must be used")
        print("LKMCPObjectIdentifierFormatterTests passed")
    }
}
