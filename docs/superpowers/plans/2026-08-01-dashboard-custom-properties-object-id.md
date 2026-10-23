# Dashboard Custom Properties and Object ID Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Dashboard custom-property menu into an offline guide with copyable integration code, and show the selected live object's canonical MCP Object ID above the Class card with one-click copy.

**Architecture:** A small Swift formatter owns the sole `displayingObject().oid` to lowercase-hex conversion and is called by both MCP and Dashboard. Two AppKit components remain independent of Dashboard internals: a compact Object ID view and a reusable guide window; the existing Objective-C Dashboard controller only supplies selection/layout events and the header delegate action.

**Tech Stack:** Objective-C/AppKit Dashboard, Swift/AppKit components exposed through `LookInside-Swift.h`, filesystem-synchronized Xcode project, standalone `xcrun swiftc` behavior tests, existing `Scripts/test.sh` build gate.

---

## File map

- Create `LookInside/MCPBridge/LKMCPObjectIdentifierFormatter.swift`: canonical Object ID selection and formatting shared by MCP and UI.
- Modify `LookInside/MCPBridge/LKMCPBridgeLiveDocumentLookup.swift`: delegate wire formatting to the shared formatter.
- Create `LookInside/Dashboard/LKDashboardObjectIDView.swift`: compact value/copy UI and pasteboard behavior.
- Create `LookInside/Dashboard/LKCustomPropertyGuideWindowController.swift`: singleton guide window, code template, copy feedback.
- Modify `LookInside/Dashboard/Search/LKDashboardHeaderView.h/.m`: forward the custom-property guide action to Dashboard.
- Modify `LookInside/Dashboard/LKDashboardViewController.m`: lay out/update Object ID and present the guide.
- Modify `LookInside/Localizable.xcstrings`: English and Simplified Chinese strings for the new UI.
- Modify `LookInside.xcodeproj/project.pbxproj`: add the three Swift files to the synchronized target membership exception list only.
- Create `Tests/Dashboard/*.swift`: executable behavior checks for formatter, view visibility/copy, and guide template.
- Create `Scripts/test-dashboard-features.sh`: compile and run those tests without introducing an XCTest target.
- Modify `Scripts/test.sh`: make the behavior tests part of the standard verification gate.

### Task 1: Canonical MCP Object ID formatter

**Files:**
- Create: `Tests/Dashboard/LKMCPObjectIdentifierFormatterStubs.swift`
- Create: `Tests/Dashboard/LKMCPObjectIdentifierFormatterTests.swift`
- Create: `Scripts/test-dashboard-features.sh`
- Create: `LookInside/MCPBridge/LKMCPObjectIdentifierFormatter.swift`
- Modify: `LookInside/MCPBridge/LKMCPBridgeLiveDocumentLookup.swift:76-83`
- Modify: `LookInside.xcodeproj/project.pbxproj:53-369`
- Modify: `Scripts/test.sh:45-52`

- [ ] **Step 1: Write the formatter stubs and failing behavior test**

```swift
// Tests/Dashboard/LKMCPObjectIdentifierFormatterStubs.swift
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
```

```swift
// Tests/Dashboard/LKMCPObjectIdentifierFormatterTests.swift
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
```

```bash
#!/bin/bash
# Scripts/test-dashboard-features.sh (initial version)
set -euo pipefail

script_root="$(cd "$(dirname "$0")/.." && pwd)"
dashboard_test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/lookinside-dashboard-tests.XXXXXX")"
trap 'rm -rf "$dashboard_test_tmp"' EXIT

xcrun swiftc -parse-as-library \
    "$script_root/Tests/Dashboard/LKMCPObjectIdentifierFormatterStubs.swift" \
    "$script_root/LookInside/MCPBridge/LKMCPObjectIdentifierFormatter.swift" \
    "$script_root/Tests/Dashboard/LKMCPObjectIdentifierFormatterTests.swift" \
    -o "$dashboard_test_tmp/object-id-formatter-tests"
"$dashboard_test_tmp/object-id-formatter-tests"
```

- [ ] **Step 2: Run the test and verify RED**

Run: `rtk bash Scripts/test-dashboard-features.sh`

Expected: FAIL because `LookInside/MCPBridge/LKMCPObjectIdentifierFormatter.swift` does not exist.

- [ ] **Step 3: Implement the shared formatter**

```swift
// LookInside/MCPBridge/LKMCPObjectIdentifierFormatter.swift
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
```

- [ ] **Step 4: Make MCP consume the canonical formatter**

Replace `objectIdentifierString(for:)` with:

```swift
static func objectIdentifierString(for item: LookinDisplayItem) -> String {
    LKMCPObjectIdentifierFormatter.objectIdentifier(for: item) ?? "0x0"
}
```

This preserves the existing `0x0` wire fallback while making every valid ID use one implementation.

- [ ] **Step 5: Add the formatter to target membership and the test gate**

In the first `PBXFileSystemSynchronizedBuildFileExceptionSet.membershipExceptions`, insert alphabetically:

```text
MCPBridge/LKMCPObjectIdentifierFormatter.swift,
```

In `Scripts/test.sh`, before `sync derived source`, add:

```bash
run_command "dashboard feature tests" bash Scripts/test-dashboard-features.sh
```

- [ ] **Step 6: Verify GREEN and compile the mixed-language target**

Run: `rtk bash Scripts/test-dashboard-features.sh`

Expected: `LKMCPObjectIdentifierFormatterTests passed`.

Run: `rtk xcodebuild -skipMacroValidation -project LookInside.xcodeproj -scheme LookInside -configuration Debug -derivedDataPath /tmp/LookInsideDerivedData CODE_SIGNING_ALLOWED=NO build`

Expected: `** BUILD SUCCEEDED **`; generated `LookInside-Swift.h` exposes `stringForOID:` and `objectIdentifierForDisplayItem:` to Objective-C.

- [ ] **Step 7: Commit the formatter slice**

```bash
git add Scripts/test-dashboard-features.sh Scripts/test.sh Tests/Dashboard/LKMCPObjectIdentifierFormatterStubs.swift Tests/Dashboard/LKMCPObjectIdentifierFormatterTests.swift LookInside/MCPBridge/LKMCPObjectIdentifierFormatter.swift LookInside/MCPBridge/LKMCPBridgeLiveDocumentLookup.swift LookInside.xcodeproj/project.pbxproj
git commit -m "feat: share MCP object identifier formatting"
```

### Task 2: Object ID row above Class

**Files:**
- Create: `Tests/Dashboard/LKDashboardObjectIDViewTests.swift`
- Modify: `Scripts/test-dashboard-features.sh`
- Create: `LookInside/Dashboard/LKDashboardObjectIDView.swift`
- Modify: `LookInside/Dashboard/LKDashboardViewController.m:26-170,197-231`
- Modify: `LookInside.xcodeproj/project.pbxproj:53-369`
- Modify: `LookInside/Localizable.xcstrings`

- [ ] **Step 1: Add the failing Object ID view test**

```swift
// Tests/Dashboard/LKDashboardObjectIDViewTests.swift
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
        let view = LKDashboardObjectIDView(frame: NSRect(x: 0, y: 0, width: 280, height: 34))
        view.render(objectIdentifier: nil)
        require(view.isHidden, "nil Object ID must hide the row")
        require(!view.copy(to: NSPasteboard(name: NSPasteboard.Name("lookinside.empty"))), "hidden row must not copy")

        view.render(objectIdentifier: "0x1234")
        require(!view.isHidden, "valid Object ID must show the row")
        require(view.objectIdentifier == "0x1234", "rendered value must stay canonical")

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("lookinside.object-id.\(UUID().uuidString)"))
        require(view.copy(to: pasteboard), "valid Object ID must copy")
        require(pasteboard.string(forType: .string) == "0x1234", "pasteboard must receive the exact MCP value")
        print("LKDashboardObjectIDViewTests passed")
    }
}
```

Extend `Scripts/test-dashboard-features.sh` after the formatter executable:

```bash
xcrun swiftc -parse-as-library -framework AppKit \
    "$script_root/LookInside/Dashboard/LKDashboardObjectIDView.swift" \
    "$script_root/Tests/Dashboard/LKDashboardObjectIDViewTests.swift" \
    -o "$dashboard_test_tmp/object-id-view-tests"
"$dashboard_test_tmp/object-id-view-tests"
```

- [ ] **Step 2: Run the test and verify RED**

Run: `rtk bash Scripts/test-dashboard-features.sh`

Expected: formatter test passes, then compilation fails because `LKDashboardObjectIDView.swift` does not exist.

- [ ] **Step 3: Implement the compact AppKit row**

Create `LKDashboardObjectIDView.swift` with:

```swift
import AppKit

@objc(LKDashboardObjectIDView)
final class LKDashboardObjectIDView: NSView {
    @objc(preferredHeight) class var preferredHeight: CGFloat { 34 }

    @objc private(set) var objectIdentifier: String?
    private let backgroundView = NSVisualEffectView()
    private let titleLabel = NSTextField(labelWithString: NSLocalizedString("Object ID", comment: ""))
    private let valueLabel = NSTextField(labelWithString: "")
    private let copyButton: NSButton
    private let feedbackLabel = NSTextField(labelWithString: NSLocalizedString("Copied", comment: ""))
    private var hideFeedbackWorkItem: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        let image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: NSLocalizedString("Copy Object ID", comment: "")) ?? NSImage()
        copyButton = NSButton(image: image, target: nil, action: nil)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        setupViews()
        render(objectIdentifier: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { hideFeedbackWorkItem?.cancel() }

    private func setupViews() {
        backgroundView.blendingMode = .withinWindow
        backgroundView.state = .active
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        valueLabel.lineBreakMode = .byTruncatingMiddle
        valueLabel.isSelectable = true
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(copyFromControl)))
        copyButton.isBordered = false
        copyButton.imagePosition = .imageOnly
        copyButton.toolTip = NSLocalizedString("Copy Object ID", comment: "")
        copyButton.target = self
        copyButton.action = #selector(copyFromControl)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        feedbackLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        feedbackLabel.textColor = .secondaryLabelColor
        feedbackLabel.isHidden = true
        feedbackLabel.translatesAutoresizingMaskIntoConstraints = false
        [backgroundView, titleLabel, valueLabel, feedbackLabel, copyButton].forEach(addSubview)
        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 58),
            copyButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            copyButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            copyButton.widthAnchor.constraint(equalToConstant: 20),
            copyButton.heightAnchor.constraint(equalToConstant: 20),
            feedbackLabel.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -6),
            feedbackLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            valueLabel.trailingAnchor.constraint(lessThanOrEqualTo: feedbackLabel.leadingAnchor, constant: -6),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @objc(renderWithObjectIdentifier:)
    func render(objectIdentifier: String?) {
        let validIdentifier = objectIdentifier.flatMap { $0.isEmpty ? nil : $0 }
        self.objectIdentifier = validIdentifier
        valueLabel.stringValue = validIdentifier ?? ""
        valueLabel.toolTip = validIdentifier
        copyButton.isEnabled = validIdentifier != nil
        isHidden = validIdentifier == nil
        feedbackLabel.isHidden = true
    }

    @discardableResult
    func copy(to pasteboard: NSPasteboard) -> Bool {
        guard let objectIdentifier, !objectIdentifier.isEmpty else { return false }
        pasteboard.clearContents()
        guard pasteboard.setString(objectIdentifier, forType: .string) else { return false }
        showCopiedFeedback()
        return true
    }

    @objc private func copyFromControl() {
        _ = copy(to: .general)
    }

    private func showCopiedFeedback() {
        hideFeedbackWorkItem?.cancel()
        feedbackLabel.isHidden = false
        let workItem = DispatchWorkItem { [weak self] in self?.feedbackLabel.isHidden = true }
        hideFeedbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: workItem)
    }
}
```

- [ ] **Step 4: Integrate selection and layout in Dashboard**

Add a strong `LKDashboardObjectIDView *objectIDView` property, instantiate it inside `cardContainerView`, and update the beginning of the card layout to:

```objc
__block CGFloat y = 0;
if (!self.objectIDView.hidden) {
    $(self.objectIDView).width(contentWidth).y(y).height([LKDashboardObjectIDView preferredHeight]);
    y = self.objectIDView.$maxY + verMargin;
}
```

Before rendering card groups in `reloadWithGroupList:`, update it from the selected live/static item:

```objc
LookinDisplayItem *selectedItem = self.staticDataSource.selectedItem;
NSString *objectIdentifier = selectedItem
    ? [LKMCPObjectIdentifierFormatter objectIdentifierForDisplayItem:selectedItem]
    : nil;
[self.objectIDView renderWithObjectIdentifier:objectIdentifier];
```

This deliberately uses `staticDataSource` only; archive/read dashboards remain hidden.

- [ ] **Step 5: Add target membership and localization**

Insert in the first synchronized membership list:

```text
Dashboard/LKDashboardObjectIDView.swift,
```

Add English/`zh-Hans` entries:

```text
Object ID / 对象 ID
Copy Object ID / 复制对象 ID
```

- [ ] **Step 6: Verify GREEN and build**

Run: `rtk bash Scripts/test-dashboard-features.sh`

Expected: formatter and Object ID view tests pass.

Run: `rtk xcodebuild -skipMacroValidation -project LookInside.xcodeproj -scheme LookInside -configuration Debug -derivedDataPath /tmp/LookInsideDerivedData CODE_SIGNING_ALLOWED=NO build`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit the Object ID UI slice**

```bash
git add Scripts/test-dashboard-features.sh Tests/Dashboard/LKDashboardObjectIDViewTests.swift LookInside/Dashboard/LKDashboardObjectIDView.swift LookInside/Dashboard/LKDashboardViewController.m LookInside/Localizable.xcstrings LookInside.xcodeproj/project.pbxproj
git commit -m "feat: show MCP object id in dashboard"
```

### Task 3: Offline custom-property guide

**Files:**
- Create: `Tests/Dashboard/LKCustomPropertyGuideTests.swift`
- Modify: `Scripts/test-dashboard-features.sh`
- Create: `LookInside/Dashboard/LKCustomPropertyGuideWindowController.swift`
- Modify: `LookInside/Dashboard/Search/LKDashboardHeaderView.h/.m:12-17,136-153`
- Modify: `LookInside/Dashboard/LKDashboardViewController.m:24-25,395-465`
- Modify: `LookInside.xcodeproj/project.pbxproj:53-369`
- Modify: `LookInside/Localizable.xcstrings`

- [ ] **Step 1: Add the failing guide-content test**

```swift
// Tests/Dashboard/LKCustomPropertyGuideTests.swift
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
        let code = LKCustomPropertyGuideWindowController.exampleCode
        ["lookin_customDebugInfos", "properties", "title", "section", "valueType", "value", "retainedSetter"].forEach {
            require(code.contains($0), "example must contain \($0)")
        }
        require(code.contains("weakSelf"), "editable example must avoid retaining the inspected view")
        print("LKCustomPropertyGuideTests passed")
    }
}
```

Extend `Scripts/test-dashboard-features.sh`:

```bash
xcrun swiftc -parse-as-library -framework AppKit \
    "$script_root/LookInside/Dashboard/LKCustomPropertyGuideWindowController.swift" \
    "$script_root/Tests/Dashboard/LKCustomPropertyGuideTests.swift" \
    -o "$dashboard_test_tmp/custom-property-guide-tests"
"$dashboard_test_tmp/custom-property-guide-tests"
```

- [ ] **Step 2: Run the test and verify RED**

Run: `rtk bash Scripts/test-dashboard-features.sh`

Expected: the first two executables pass, then compilation fails because `LKCustomPropertyGuideWindowController.swift` does not exist.

- [ ] **Step 3: Implement the reusable guide window**

```swift
// LookInside/Dashboard/LKCustomPropertyGuideWindowController.swift
import AppKit

@objc(LKCustomPropertyGuideWindowController)
final class LKCustomPropertyGuideWindowController: NSWindowController {
    static let exampleCode = """
    // Add this method to a UIView or CALayer subclass in the inspected app.
    - (NSDictionary *)lookin_customDebugInfos {
        __weak typeof(self) weakSelf = self;
        return @{
            @"title": NSStringFromClass(self.class),
            @"properties": @[
                @{
                    @"title": @"Description",
                    @"section": @"Custom",
                    @"valueType": @"string",
                    @"value": self.description ?: @""
                },
                @{
                    @"title": @"Hidden",
                    @"section": @"Custom",
                    @"valueType": @"bool",
                    @"value": @(self.hidden),
                    @"retainedSetter": ^(BOOL hidden) {
                        weakSelf.hidden = hidden;
                    }
                }
            ]
        };
    }
    """

    private static let sharedController = LKCustomPropertyGuideWindowController()

    @objc(showGuideWindow)
    static func showGuideWindow() {
        sharedController.showWindow(nil)
        sharedController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("Custom Properties", comment: "")
        window.identifier = NSUserInterfaceItemIdentifier("lookinside.custom-property-guide")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 620, height: 520)
        window.contentViewController = LKCustomPropertyGuideContentViewController()
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class LKCustomPropertyGuideContentViewController: NSViewController {
    private let feedbackLabel = NSTextField(labelWithString: NSLocalizedString("Copied", comment: ""))

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 620))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let titleLabel = NSTextField(labelWithString: NSLocalizedString("Custom Properties", comment: ""))
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)

        let introLabel = wrappingLabel(NSLocalizedString(
            "Implement this method in a UIView or CALayer subclass, then reload the hierarchy.",
            comment: ""
        ))
        let supportedLabel = wrappingLabel(NSLocalizedString(
            "Supported types: string, number, bool, color, rect, size, point, insets, shadow, enum, json.",
            comment: ""
        ))
        supportedLabel.textColor = .secondaryLabelColor

        let codeTextView = NSTextView(frame: .zero)
        codeTextView.string = LKCustomPropertyGuideWindowController.exampleCode
        codeTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        codeTextView.isEditable = false
        codeTextView.isSelectable = true
        codeTextView.isRichText = false
        codeTextView.textContainerInset = NSSize(width: 12, height: 12)
        codeTextView.autoresizingMask = [.width, .height]
        codeTextView.textContainer?.widthTracksTextView = true

        let codeScrollView = NSScrollView()
        codeScrollView.borderType = .bezelBorder
        codeScrollView.hasVerticalScroller = true
        codeScrollView.drawsBackground = true
        codeScrollView.documentView = codeTextView

        let copyButton = NSButton(
            title: NSLocalizedString("Copy Code", comment: ""),
            target: self,
            action: #selector(copyCode)
        )
        copyButton.identifier = NSUserInterfaceItemIdentifier("lookinside.custom-property-guide.copy")
        let doneButton = NSButton(
            title: NSLocalizedString("Done", comment: ""),
            target: self,
            action: #selector(closeGuide)
        )
        doneButton.keyEquivalent = "\r"

        feedbackLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        feedbackLabel.textColor = .secondaryLabelColor
        feedbackLabel.isHidden = true

        let controls: [NSView] = [titleLabel, introLabel, supportedLabel, codeScrollView, feedbackLabel, copyButton, doneButton]
        controls.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            introLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            introLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            introLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            supportedLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            supportedLabel.trailingAnchor.constraint(equalTo: introLabel.trailingAnchor),
            supportedLabel.topAnchor.constraint(equalTo: introLabel.bottomAnchor, constant: 6),
            codeScrollView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            codeScrollView.trailingAnchor.constraint(equalTo: introLabel.trailingAnchor),
            codeScrollView.topAnchor.constraint(equalTo: supportedLabel.bottomAnchor, constant: 14),
            codeScrollView.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -16),
            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            doneButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            doneButton.heightAnchor.constraint(equalToConstant: 30),
            copyButton.trailingAnchor.constraint(equalTo: doneButton.leadingAnchor, constant: -8),
            copyButton.centerYAnchor.constraint(equalTo: doneButton.centerYAnchor),
            copyButton.heightAnchor.constraint(equalTo: doneButton.heightAnchor),
            feedbackLabel.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -10),
            feedbackLabel.centerYAnchor.constraint(equalTo: copyButton.centerYAnchor),
        ])
    }

    private func wrappingLabel(_ string: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: string)
        label.font = .systemFont(ofSize: 12)
        label.maximumNumberOfLines = 0
        return label
    }

    @objc private func copyCode() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(LKCustomPropertyGuideWindowController.exampleCode, forType: .string) else { return }
        feedbackLabel.isHidden = false
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideFeedback), object: nil)
        perform(#selector(hideFeedback), with: nil, afterDelay: 1)
    }

    @objc private func hideFeedback() {
        feedbackLabel.isHidden = true
    }

    @objc private func closeGuide() {
        view.window?.close()
    }
}
```

- [ ] **Step 4: Replace the disabled menu action with a delegate event**

Add to `LKDashboardHeaderViewDelegate`:

```objc
- (void)dashboardHeaderViewDidRequestCustomPropertiesGuide:(LKDashboardHeaderView *)view;
```

Replace `handleAddCustomAttr` with:

```objc
- (void)handleAddCustomAttr {
    if ([self.delegate respondsToSelector:@selector(dashboardHeaderViewDidRequestCustomPropertiesGuide:)]) {
        [self.delegate dashboardHeaderViewDidRequestCustomPropertiesGuide:self];
    }
}
```

Implement in Dashboard:

```objc
- (void)dashboardHeaderViewDidRequestCustomPropertiesGuide:(LKDashboardHeaderView *)view {
    [LKCustomPropertyGuideWindowController showGuideWindow];
}
```

Remove the now-unused disabled-external-link call from this path.

- [ ] **Step 5: Add target membership and localization**

Insert in the first synchronized membership list:

```text
Dashboard/LKCustomPropertyGuideWindowController.swift,
```

Add English/`zh-Hans` translations for:

```text
Custom Properties / 自定义属性
Implement this method in a UIView or CALayer subclass, then reload the hierarchy. / 在 UIView 或 CALayer 子类中实现此方法，然后重新加载层级。
Supported types: string, number, bool, color, rect, size, point, insets, shadow, enum, json. / 支持类型：string、number、bool、color、rect、size、point、insets、shadow、enum、json。
Copy Code / 复制代码
```

Reuse existing `Done`/`完成` and `Copied`/`已复制` entries.

- [ ] **Step 6: Verify GREEN and build**

Run: `rtk bash Scripts/test-dashboard-features.sh`

Expected: all three executables print `passed`.

Run: `rtk plutil -lint LookInside/Localizable.xcstrings`

Expected: `OK`.

Run: `rtk xcodebuild -skipMacroValidation -project LookInside.xcodeproj -scheme LookInside -configuration Debug -derivedDataPath /tmp/LookInsideDerivedData CODE_SIGNING_ALLOWED=NO build`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit the guide slice**

```bash
git add Scripts/test-dashboard-features.sh Tests/Dashboard/LKCustomPropertyGuideTests.swift LookInside/Dashboard/LKCustomPropertyGuideWindowController.swift LookInside/Dashboard/Search/LKDashboardHeaderView.h LookInside/Dashboard/Search/LKDashboardHeaderView.m LookInside/Dashboard/LKDashboardViewController.m LookInside/Localizable.xcstrings LookInside.xcodeproj/project.pbxproj
git commit -m "feat: add offline custom property guide"
```

### Task 4: Completion verification

**Files:**
- Verify: all files from Tasks 1–3
- Verify: `docs/superpowers/specs/2026-08-01-dashboard-custom-properties-object-id-design.md`

- [ ] **Step 1: Run the repository gate from a clean DerivedData location**

Run: `rtk bash Scripts/test.sh`

Expected: dashboard tests pass, Swift builds pass, and LookInside Debug ends with `all tests passed`.

- [ ] **Step 2: Verify the exact wire/UI implementation contract**

Run:

```bash
rg -n "objectIdentifier\(for:|objectIdentifierForDisplayItem|renderWithObjectIdentifier|showGuideWindow|lookin_customDebugInfos" LookInside Tests/Dashboard
```

Expected: MCP and Dashboard both call `LKMCPObjectIdentifierFormatter.objectIdentifier(for:)`; no Dashboard path formats its own `%lx` string.

- [ ] **Step 3: Launch and inspect the built UI**

Run: `rtk open /tmp/LookInsideDerivedData/Build/Products/Debug/LookInside.app`

With a live document selected, verify:

1. the Object ID row is directly above Class;
2. switching selected hierarchy nodes changes the value;
3. the copy button writes the exact displayed value;
4. archive/read documents do not show the row;
5. `+` → “如何添加自定义属性…” opens one reusable local guide window;
6. the example is selectable and `Copy Code` writes the complete template.

- [ ] **Step 4: Verify MCP round-trip identity**

For the selected node, run MCP `hierarchy.read`, copy its `objectIdentifier`, and compare it byte-for-byte with the Dashboard pasteboard value. Then invoke one read-only MCP detail method with that ID to prove the copied value resolves the same node.

- [ ] **Step 5: Audit worktree scope and final diff**

Run: `rtk git status --short`

Expected: user-owned `AGENTS.md` and `.understand-anything/` remain untouched; only intended feature files are changed or committed.

Run: `rtk git diff --check HEAD~3..HEAD`

Expected: no whitespace errors.
