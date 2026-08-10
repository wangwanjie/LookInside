import AppKit

/// Resolves the icon shown for the device an inspected app runs on.
///
/// This compatibility branch keeps the Swift bridge in place, but always falls back to
/// the legacy per-family asset artwork instead of depending on newer UIFoundation
/// device-icon APIs.
@objc(LKDeviceIconProvider)
final class LKDeviceIconProvider: NSObject {

    @objc static let toolbarPointSize: CGFloat = 16
    @objc static let tipsPointSize: CGFloat = 18
    @objc static let launchPointSize: CGFloat = 36

    @objc(deviceIconForAppInfo:pointSize:)
    static func deviceIcon(forAppInfo appInfo: LookinAppInfo?, pointSize: CGFloat) -> NSImage? {
        return nil
    }
}
