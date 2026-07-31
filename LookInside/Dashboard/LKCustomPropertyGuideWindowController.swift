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

    static var fieldExplanation: String {
        NSLocalizedString(
            "Top-level title overrides the inspected object's display name. In each property, title names the row, section groups it, valueType selects its renderer or editor, and value is the current value. retainedSetter makes string, number, bool, color, rect, size, point, insets, and enum values editable; omit it for read-only values. shadow and json are read-only.",
            comment: ""
        )
    }

    private static let sharedController = LKCustomPropertyGuideWindowController()
    static var guideWindow: NSWindow? { sharedController.window }
    static var isShowingCopyFeedback: Bool {
        (sharedController.contentViewController as? LKCustomPropertyGuideContentViewController)?.isShowingCopyFeedback ?? false
    }

    @objc(showGuideWindow)
    static func showGuideWindow() {
        (sharedController.contentViewController as? LKCustomPropertyGuideContentViewController)?.resetCopyFeedback()
        sharedController.showWindow(nil)
        sharedController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @discardableResult
    static func copyExampleCode(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        return copyExampleCode { pasteboard.setString($0, forType: .string) }
    }

    @discardableResult
    static func copyExampleCode(using writer: (String) -> Bool) -> Bool {
        writer(exampleCode)
    }

    @discardableResult
    static func copyFromGuide(using writer: (String) -> Bool) -> Bool {
        guard let controller = sharedController.contentViewController as? LKCustomPropertyGuideContentViewController else {
            return false
        }
        return controller.performCopy(using: writer)
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
    fileprivate var isShowingCopyFeedback: Bool { !feedbackLabel.isHidden }

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
        let fieldLabel = wrappingLabel(LKCustomPropertyGuideWindowController.fieldExplanation)
        fieldLabel.identifier = NSUserInterfaceItemIdentifier("lookinside.custom-property-guide.fields")
        fieldLabel.textColor = .secondaryLabelColor

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

        let controls: [NSView] = [
            titleLabel,
            introLabel,
            supportedLabel,
            fieldLabel,
            codeScrollView,
            feedbackLabel,
            copyButton,
            doneButton,
        ]
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

            fieldLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            fieldLabel.trailingAnchor.constraint(equalTo: introLabel.trailingAnchor),
            fieldLabel.topAnchor.constraint(equalTo: supportedLabel.bottomAnchor, constant: 6),

            codeScrollView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            codeScrollView.trailingAnchor.constraint(equalTo: introLabel.trailingAnchor),
            codeScrollView.topAnchor.constraint(equalTo: fieldLabel.bottomAnchor, constant: 14),
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
        _ = performCopy { code in
            pasteboard.clearContents()
            return pasteboard.setString(code, forType: .string)
        }
    }

    @discardableResult
    fileprivate func performCopy(using writer: (String) -> Bool) -> Bool {
        resetCopyFeedback()
        guard LKCustomPropertyGuideWindowController.copyExampleCode(using: writer) else {
            return false
        }
        feedbackLabel.isHidden = false
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(hideFeedback),
            object: nil
        )
        perform(#selector(hideFeedback), with: nil, afterDelay: 1)
        return true
    }

    @objc private func hideFeedback() {
        feedbackLabel.isHidden = true
    }

    @objc private func closeGuide() {
        view.window?.close()
    }

    fileprivate func resetCopyFeedback() {
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(hideFeedback),
            object: nil
        )
        feedbackLabel.isHidden = true
    }
}
