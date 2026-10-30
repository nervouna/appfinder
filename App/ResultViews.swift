import AppFinderCore
import AppKit

/// A row of the result list: a section header, an item, or a calculation.
enum ResultRow: Equatable {
    case header(String)
    case item(RankedItem)
    case calculation(Calculator.Evaluation)

    var selectionID: String? {
        switch self {
        case .header: nil
        case .item(let item): item.id
        case .calculation: nil
        }
    }

    var item: RankedItem? {
        if case .item(let item) = self { return item }
        return nil
    }
}

/// Icons from the workspace, cached by path. Loaded lazily for the rows on screen.
@MainActor final class IconCache {
    private let cache = NSCache<NSString, NSImage>()

    init() {
        cache.countLimit = 500
    }

    func icon(for path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 32, height: 32)
        cache.setObject(icon, forKey: path as NSString)
        return icon
    }
}

final class ResultCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("result")
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let kind = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.font = .systemFont(ofSize: 14)
        title.lineBreakMode = .byTruncatingTail
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        kind.font = .systemFont(ofSize: 11)
        kind.textColor = .tertiaryLabelColor
        kind.alignment = .right
        kind.setContentCompressionResistancePriority(.required, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let text = NSStackView(views: [title, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        for view in [icon, text, kind] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ResultRowView.inset + 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            kind.leadingAnchor.constraint(greaterThanOrEqualTo: text.trailingAnchor, constant: 12),
            kind.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(ResultRowView.inset + 12)),
            kind.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ ranked: RankedItem, icon image: NSImage) {
        icon.image = image
        title.attributedStringValue = Self.highlighted(ranked.item.displayName, ranked.highlight)
        switch ranked.item.kind {
        case .app:
            subtitle.isHidden = true
            kind.stringValue = String(localized: "Application")
        case .file:
            subtitle.isHidden = false
            subtitle.stringValue = Self.folder(of: ranked.item.path)
            kind.stringValue = ""
        }
    }

    static func highlighted(_ text: String, _ indices: [Int]) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor,
        ])
        guard !indices.isEmpty else { return result }
        let marked = Set(indices)
        var offset = 0
        for (index, character) in text.enumerated() {
            let length = String(character).utf16.count
            if marked.contains(index) {
                result.addAttribute(.font, value: NSFont.systemFont(ofSize: 14, weight: .bold),
                                    range: NSRange(location: offset, length: length))
            }
            offset += length
        }
        return result
    }

    /// The folder an item is in, with the home folder written as `~`.
    static func folder(of path: String) -> String {
        let folder = (path as NSString).deletingLastPathComponent
        let home = NSHomeDirectory()
        if folder == home { return "~" }
        if folder.hasPrefix(home + "/") { return "~" + folder.dropFirst(home.count) }
        return folder
    }
}

final class CalculatorCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("calculation")
    private let equation = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        equation.font = .monospacedDigitSystemFont(ofSize: 22, weight: .medium)
        equation.lineBreakMode = .byTruncatingMiddle
        equation.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.stringValue = String(localized: "↩ Copy result    ⌘↩ Copy equation")

        let text = NSStackView(views: [equation, hint])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 5
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ResultRowView.inset + 10),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(ResultRowView.inset + 12)),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ calculation: Calculator.Evaluation) {
        switch calculation {
        case .result(let result):
            let title = NSMutableAttributedString(string: result.equation, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .medium),
                .foregroundColor: NSColor.labelColor,
            ])
            let valueLength = (result.value as NSString).length
            title.addAttribute(.font, value: NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold),
                               range: NSRange(location: title.length - valueLength, length: valueLength))
            equation.attributedStringValue = title
            hint.isHidden = false
            toolTip = result.equation
        case .failure(let failure):
            let message = switch failure {
            case .divisionByZero: String(localized: "Cannot divide by zero")
            case .outOfRange: String(localized: "Number is outside the supported range")
            }
            equation.attributedStringValue = NSAttributedString(string: message, attributes: [
                .font: NSFont.systemFont(ofSize: 18, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
            hint.isHidden = true
            toolTip = message
        }
    }
}

final class HeaderCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("header")
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ResultRowView.inset + 10),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ text: String) {
        label.stringValue = text
    }
}
