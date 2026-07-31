import Foundation

@objc final class LookinObject: NSObject {
    @objc var oid: UInt = 0
}

@objc final class LookinDisplayItem: NSObject {
    var mockedDisplayingObject: LookinObject?

    @objc func displayingObject() -> LookinObject? {
        mockedDisplayingObject
    }
}
