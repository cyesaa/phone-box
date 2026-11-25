import AppKit
import CoreImage

/// The pairing window: the personal link as a QR code and as text (design §5 "Eşleştirme").
@MainActor
final class QRWindowController: NSObject {
    private var panel: NSPanel?
    private let imageView = NSImageView()
    private let linkField = NSTextField(labelWithString: "")
    private let copyButton = NSButton()
    private var link = ""

    func show(link: String) {
        self.link = link
        let panel = self.panel ?? makePanel()
        self.panel = panel
        imageView.image = Self.qrImage(for: link, size: 260)
        linkField.stringValue = link
        copyButton.title = L10n.qrCopy
        panel.center()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 430),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = L10n.qrTitle
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let instructions = NSTextField(wrappingLabelWithString: L10n.qrInstructions)
        instructions.alignment = .center
        linkField.isSelectable = true
        linkField.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        linkField.textColor = .secondaryLabelColor
        linkField.lineBreakMode = .byCharWrapping
        linkField.maximumNumberOfLines = 3
        linkField.alignment = .center
        imageView.imageScaling = .scaleNone
        copyButton.bezelStyle = .rounded
        copyButton.target = self
        copyButton.action = #selector(copyLink)

        let stack = NSStackView(views: [imageView, instructions, linkField, copyButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = NSView()
        panel.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            instructions.widthAnchor.constraint(equalToConstant: 290),
            linkField.widthAnchor.constraint(equalToConstant: 290),
        ])
        return panel
    }

    @objc private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        copyButton.title = L10n.qrCopied
    }

    /// Black modules on white with a quiet zone, scaled by whole pixels so it stays sharp.
    static func qrImage(for text: String, size: CGFloat) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = max(1, (size / output.extent.width).rounded(.down))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let representation = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}
