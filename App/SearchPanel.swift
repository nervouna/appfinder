import AppKit

/// The floating search panel. It becomes the key window without making AppFinder the active
/// app (`nonactivatingPanel`), so the app in front keeps its place and gets the focus back when
/// the panel goes away. It joins every Space and floats over full-screen apps.
final class SearchPanel: NSPanel {
    /// Keys the panel handles itself before the search field sees them. Return false to pass a key on.
    var keyHandler: ((NSEvent) -> Bool)?

    static let width: CGFloat = 680

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 60),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let keyHandler, keyHandler(event) {
            return
        }
        super.sendEvent(event)
    }

    /// Places the panel on the screen with the mouse pointer: centered, its top a fifth of the
    /// way down the visible frame. A height change keeps the top where it is.
    func place(height: CGFloat, on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let top = visible.maxY - visible.height * 0.2
        let frame = NSRect(x: visible.midX - Self.width / 2, y: top - height, width: Self.width, height: height)
        setFrame(frame.integral, display: true)
    }

    func resize(height: CGFloat) {
        var frame = self.frame
        guard abs(frame.height - height) > 0.5 else { return }
        frame.origin.y += frame.height - height
        frame.size.height = height
        setFrame(frame, display: true)
    }

    static func screenWithMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }
}

/// The search field: large, borderless, on the panel's background.
final class SearchField: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        font = .systemFont(ofSize: 22, weight: .regular)
        cell?.usesSingleLineMode = true
        cell?.wraps = false
        cell?.isScrollable = true
        placeholderString = String(localized: "Search apps and files")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
