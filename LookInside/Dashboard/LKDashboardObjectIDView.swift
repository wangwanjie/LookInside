import AppKit

@objc(LKDashboardObjectIDView)
final class LKDashboardObjectIDView: NSView {
    @objc(preferredHeight) class var preferredHeight: CGFloat { 34 }

    @objc private(set) var objectIdentifier: String?
    var isShowingCopyFeedback: Bool { !feedbackLabel.isHidden }

    private let backgroundView = NSVisualEffectView()
    private let titleLabel = NSTextField(labelWithString: NSLocalizedString("Object ID", comment: ""))
    private let valueLabel = NSTextField(labelWithString: "")
    private let copyButton: NSButton
    private let feedbackLabel = NSTextField(labelWithString: NSLocalizedString("Copied", comment: ""))
    private var hideFeedbackWorkItem: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        let image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: NSLocalizedString("Copy Object ID", comment: "")
        ) ?? NSImage()
        copyButton = NSButton(image: image, target: nil, action: nil)
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        setupViews()
        render(objectIdentifier: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        hideFeedbackWorkItem?.cancel()
    }

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
        resetCopyFeedback()
    }

    @discardableResult
    func copy(to pasteboard: NSPasteboard) -> Bool {
        copy { objectIdentifier in
            pasteboard.clearContents()
            return pasteboard.setString(objectIdentifier, forType: .string)
        }
    }

    @discardableResult
    func copy(using writer: (String) -> Bool) -> Bool {
        resetCopyFeedback()
        guard let objectIdentifier, !objectIdentifier.isEmpty else {
            return false
        }
        guard writer(objectIdentifier) else {
            return false
        }
        showCopiedFeedback()
        return true
    }

    @objc private func copyFromControl() {
        _ = copy(to: .general)
    }

    private func showCopiedFeedback() {
        feedbackLabel.isHidden = false
        let workItem = DispatchWorkItem { [weak self] in
            self?.feedbackLabel.isHidden = true
        }
        hideFeedbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: workItem)
    }

    private func resetCopyFeedback() {
        hideFeedbackWorkItem?.cancel()
        hideFeedbackWorkItem = nil
        feedbackLabel.isHidden = true
    }
}
