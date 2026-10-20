import AppFinderCore
import AppFinderSystem
import AppKit
import Carbon
import os
import QuartzCore

/// The search panel and everything it does: the query, the results, opening an item, and the
/// ABC lock (see `docs/design.md`, "ABC lock and restore").
@MainActor final class SearchController: NSObject {
    enum CloseReason: String {
        case escape, hotkey, focusLost, opened, revealed, command
    }

    /// How the input source is handed back on close; the defaults are what measurement settled on.
    struct Tuning {
        /// How long the panel keeps the key focus after the system reports the restored source.
        var settle: Duration = .milliseconds(30)
        /// The longest wait for the system to report the restored source.
        var reportTimeout: Duration = .milliseconds(300)
        /// How long the panel takes the focus back after a click elsewhere, when the system does
        /// not switch per document (macism measured 100 ms and up as stable on macOS 26).
        var refocusSettle: Duration = .milliseconds(150)
    }

    let panel = SearchPanel()
    let lock: InputSourceLock
    var tuning = Tuning()

    private let field = SearchField()
    private let searchIcon = NSImageView()
    private let separator = NSBox()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let content = FlippedView()
    private let catalog: AppCatalog
    private let usage: UsageStore
    private let fileSearch = FileSearch()
    private let icons = IconCache()
    private let inputSources: TISInputSources

    private(set) var rows: [ResultRow] = []
    private var appResults: [RankedItem] = []
    private var fileResults: [RankedItem] = []
    private var fileTask: Task<Void, Never>?
    private(set) var isOpen = false
    private(set) var isClosing = false
    private var sourceObserver: NSObjectProtocol?
    private let log = Logger(subsystem: "io.damao.appfinder", category: "panel")

    /// Measurements of the last open and close, for the Debug control channel.
    private(set) var lastOpen: [String: Any] = [:]
    private(set) var lastClose: [String: Any] = [:]
    private(set) var lockCorrections = 0
    private(set) var lastFileSearch: [String: Any] = [:]
    private let undoManager = UndoManager()

    static let fieldHeight: CGFloat = 56
    static let rowHeight: CGFloat = 44
    static let headerHeight: CGFloat = 26
    static let visibleItemRows: CGFloat = 8
    static let appLimit = 6
    static let fileLimit = 20
    static let recentLimit = 8

    init(catalog: AppCatalog, usage: UsageStore, inputSources: TISInputSources) {
        self.catalog = catalog
        self.usage = usage
        self.inputSources = inputSources
        let target = inputSources.isEnabled(InputSourceLock.abc)
            ? InputSourceLock.abc
            : (inputSources.asciiCapableLayoutID() ?? InputSourceLock.abc)
        lock = InputSourceLock(backend: inputSources, target: target)
        super.init()
        buildViews()
        prewarm()
        catalog.onChange = { [weak self] in self?.catalogChanged() }
        sourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.inputSourceChanged() }
        }
    }

    // MARK: Views

    private func buildViews() {
        let glass = NSGlassEffectView()
        glass.cornerRadius = 18
        glass.contentView = content
        // Clipped to its rounded shape, so that the window's shadow follows the corners; without
        // the clip the window server draws the shadow, and a hard rim, around the whole rectangle.
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 18
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        panel.contentView = glass
        panel.delegate = self
        panel.keyHandler = { [weak self] event in
            MainActor.assumeIsolated { self?.handleKey(event) ?? false }
        }

        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        searchIcon.symbolConfiguration = .init(pointSize: 20, weight: .regular)
        searchIcon.contentTintColor = .secondaryLabelColor
        field.delegate = self
        separator.boxType = .separator

        let column = NSTableColumn(identifier: .init("main"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.headerView = nil
        // Plain, so that the rows are exactly as tall as they say and the list height can be
        // computed; ResultRowView draws the rounded selection that the inset style would.
        table.style = .plain
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.refusesFirstResponder = true
        table.floatsGroupRows = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(doubleClicked)
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false

        for view in [searchIcon, field, separator, scroll] as [NSView] {
            content.addSubview(view)
        }
        layoutContent()
    }

    /// Orders the panel in and out once, invisibly, so that the first real open does not pay for
    /// the window's backing store and first render (about 50 ms after launch).
    private func prewarm() {
        panel.alphaValue = 0
        panel.place(height: panelHeight, on: NSScreen.main)
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        CATransaction.flush()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    /// The height of all rows; the list grows with it up to `maxListHeight`, and only scrolls beyond.
    private var contentHeight: CGFloat {
        rows.reduce(0) { $0 + ($1.item == nil ? Self.headerHeight : Self.rowHeight) }
    }

    private static let maxListHeight = rowHeight * visibleItemRows + headerHeight

    private var listHeight: CGFloat {
        min(contentHeight, Self.maxListHeight)
    }

    private var panelHeight: CGFloat {
        rows.isEmpty ? Self.fieldHeight : Self.fieldHeight + 1 + listHeight + 12
    }

    private func layoutContent() {
        let width = SearchPanel.width
        content.frame = NSRect(x: 0, y: 0, width: width, height: panelHeight)
        searchIcon.frame = NSRect(x: 18, y: 16, width: 24, height: 24)
        field.frame = NSRect(x: 52, y: 13, width: width - 52 - 18, height: 30)
        separator.isHidden = rows.isEmpty
        scroll.isHidden = rows.isEmpty
        separator.frame = NSRect(x: 0, y: Self.fieldHeight, width: width, height: 1)
        scroll.frame = NSRect(x: 0, y: Self.fieldHeight + 1 + 6, width: width, height: listHeight)
        scroll.hasVerticalScroller = contentHeight > Self.maxListHeight
        table.sizeLastColumnToFit()
    }

    private func resizeToRows() {
        layoutContent()
        panel.resize(height: panelHeight)
    }

    // MARK: Open and close

    func toggle() {
        if isOpen {
            close(.hotkey)
        } else {
            show()
        }
    }

    func show() {
        guard !isOpen else { return }
        let started = CACurrentMediaTime()
        isOpen = true
        undoManager.removeAllActions()
        var marks: [String: Double] = [:]
        func mark(_ name: String) { marks[name] = (CACurrentMediaTime() - started) * 1000 }
        field.stringValue = ""
        showRecent()
        layoutContent()
        mark("rows")
        panel.place(height: panelHeight, on: SearchPanel.screenWithMouse())
        mark("place")
        // On screen first: taking the key focus costs a round trip to the window server (5 to
        // 60 ms), and the input source switch another 15 to 45 ms. The next key press comes well
        // after that (the hotkey is still held), and waits in the queue until the field has
        // the focus and ABC is selected.
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        CATransaction.flush()
        let visible = (CACurrentMediaTime() - started) * 1000
        panel.makeKey()
        mark("key")
        panel.makeFirstResponder(field)
        mark("responder")
        let before = inputSources.currentID()
        fieldInputContext?.allowedInputSourceLocales = [NSAllRomanInputSourcesLocaleIdentifier]
        let locked = lock.engage()
        let elapsed = (CACurrentMediaTime() - started) * 1000
        lastOpen = [
            "visibleMs": visible,
            "marks": marks,
            "ms": elapsed,
            "before": before ?? NSNull(),
            "saved": lock.saved ?? NSNull(),
            "locked": locked,
            "after": inputSources.currentID() ?? NSNull(),
        ]
        log.debug("open in \(elapsed, format: .fixed(precision: 2)) ms, source \(before ?? "-", privacy: .public) → \(self.inputSources.currentID() ?? "-", privacy: .public)")
        // The field's input context comes up on the next pass of the run loop; hold ABC there too.
        DispatchQueue.main.async { [weak self] in
            self?.holdABC()
        }
    }

    /// Closes the panel and hands the input source back; `action` runs once the panel is gone.
    func close(_ reason: CloseReason, then action: (@MainActor () -> Void)? = nil) {
        guard isOpen, !isClosing else { return }
        isClosing = true
        fileTask?.cancel()
        let started = CACurrentMediaTime()
        // Looks closed at once; the panel keeps the key focus until the source is restored.
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        let hadFocus = panel.isKeyWindow
        fieldInputContext?.allowedInputSourceLocales = nil
        panel.makeFirstResponder(nil)
        let perDocument = InputSourcePreferences.perDocumentSources
        Task { @MainActor in
            var info: [String: Any] = ["reason": reason.rawValue, "hadFocus": hadFocus, "perDocument": perDocument]
            if let restored = lock.restore() {
                info["restored"] = restored
                if !hadFocus {
                    // A click elsewhere moved the focus before the source was restored, and a
                    // source selected while another app's text has the focus may show in the menu
                    // bar without reaching that text. Take the focus back for a moment, invisibly,
                    // so that the text is activated again with the restored source when the panel
                    // lets go. (The system's per-document switching does not help: the panel
                    // never makes AppFinder the active app, so ABC was recorded for the document
                    // behind it.)
                    panel.makeKey()
                }
                let reported = await waitUntilCurrent(restored, timeout: tuning.reportTimeout)
                info["reportedMs"] = (CACurrentMediaTime() - started) * 1000
                info["reported"] = reported
                try? await Task.sleep(for: hadFocus ? tuning.settle : tuning.refocusSettle)
            }
            panel.orderOut(nil)
            panel.alphaValue = 1
            panel.ignoresMouseEvents = false
            isOpen = false
            isClosing = false
            info["ms"] = (CACurrentMediaTime() - started) * 1000
            info["after"] = inputSources.currentID() ?? NSNull()
            lastClose = info
            log.debug("closed (\(reason.rawValue, privacy: .public)), source \(self.inputSources.currentID() ?? "-", privacy: .public)")
            action?()
        }
    }

    private func waitUntilCurrent(_ id: String, timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while inputSources.currentID() != id {
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    private var fieldInputContext: NSTextInputContext? {
        (field.currentEditor() as? NSTextView)?.inputContext
    }

    /// Selects ABC again when something else got selected while the panel is open (the lock
    /// itself keeps Ctrl+Space from picking a non-Roman source in the field).
    private func holdABC() {
        guard isOpen, !isClosing, lock.isEngaged else { return }
        if inputSources.currentID() != lock.target {
            lockCorrections += 1
            let held = lock.holdTarget()
            log.notice("input source left ABC while open, selected it again: \(held)")
        }
    }

    private func inputSourceChanged() {
        holdABC()
    }

    // MARK: Keys

    private func handleKey(_ event: NSEvent) -> Bool {
        if isClosing {
            return true
        }
        if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() {
            return false
        }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags.contains(.command), editKeyEquivalent(event, flags: flags) {
            return true
        }
        switch Int(event.keyCode) {
        case kVK_Escape:
            close(.escape)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            activateSelection(reveal: flags == .command)
        case kVK_DownArrow:
            moveSelection(by: 1)
        case kVK_UpArrow:
            moveSelection(by: -1)
        case kVK_ANSI_N where flags == .control:
            moveSelection(by: 1)
        case kVK_ANSI_P where flags == .control:
            moveSelection(by: -1)
        case kVK_Tab:
            break
        default:
            return false
        }
        return true
    }

    /// The Edit menu's shortcuts for the search field. AppFinder is never the active app while the
    /// panel is up, so there is no menu bar to carry them.
    private func editKeyEquivalent(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        guard let editor = field.currentEditor() as? NSTextView else { return false }
        switch (event.charactersIgnoringModifiers?.lowercased(), flags) {
        case ("a", .command): editor.selectAll(nil)
        case ("c", .command): editor.copy(nil)
        case ("x", .command): editor.cut(nil)
        case ("v", .command): editor.paste(nil)
        case ("z", .command): editor.undoManager?.undo()
        case ("z", [.command, .shift]): editor.undoManager?.redo()
        default: return false
        }
        return true
    }

    private func moveSelection(by step: Int) {
        let itemRows = rows.indices.filter { rows[$0].item != nil }
        guard !itemRows.isEmpty else { return }
        let current = itemRows.firstIndex(of: table.selectedRow) ?? 0
        let next = itemRows[max(0, min(itemRows.count - 1, current + step))]
        select(row: next)
    }

    private func select(row: Int) {
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    @objc private func doubleClicked() {
        guard table.clickedRow >= 0, rows.indices.contains(table.clickedRow), rows[table.clickedRow].item != nil else { return }
        select(row: table.clickedRow)
        activateSelection(reveal: false)
    }

    var selectedItem: RankedItem? {
        rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].item : nil
    }

    /// Opens the selected item (Enter) or shows it in Finder (Cmd+Enter), after the panel closed
    /// and the input source is back.
    func activateSelection(reveal: Bool) {
        guard let ranked = selectedItem else {
            NSSound.beep()
            return
        }
        let item = ranked.item
        guard FileManager.default.fileExists(atPath: item.path) else {
            NSSound.beep()
            usage.remove(path: item.path)
            queryChanged()
            return
        }
        usage.record(path: item.path, query: field.stringValue)
        let url = URL(fileURLWithPath: item.path)
        let log = log
        close(reveal ? .revealed : .opened) {
            if reveal {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else if item.kind == .app {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                    if let error {
                        log.error("cannot open \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    }
                }
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: Results

    /// Sets the query as if it had been typed (Debug control channel).
    func setQuery(_ text: String) {
        field.stringValue = text
        queryChanged()
    }

    var query: String { field.stringValue }

    private func catalogChanged() {
        guard isOpen, !isClosing else { return }
        queryChanged()
    }

    func queryChanged() {
        let query = field.stringValue
        fileTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            showRecent()
            return
        }
        let now = Date()
        appResults = Ranker.rank(catalog.items, query: query, usage: usage.book, now: now, limit: Self.appLimit)
        // Keep the files found so far while they still match, so that the list does not flicker.
        fileResults = Ranker.rank(fileResults.map(\.item), query: query, usage: usage.book, now: now, limit: Self.fileLimit)
        rebuildRows(keepSelection: false)
        scheduleFileSearch(query)
    }

    private func scheduleFileSearch(_ query: String) {
        let appPaths = Set(catalog.items.map(\.path))
        fileTask = Task { @MainActor [weak self, fileSearch] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            let started = CACurrentMediaTime()
            guard let found = await fileSearch.search(query), !Task.isCancelled else { return }
            self?.lastFileSearch = ["query": query, "found": found.count, "ms": (CACurrentMediaTime() - started) * 1000]
            guard let self, self.isOpen, self.field.stringValue == query else { return }
            let files = found.filter { !appPaths.contains($0.path) }
            self.fileResults = Ranker.rank(files, query: query, usage: self.usage.book, now: Date(), limit: Self.fileLimit)
            self.rebuildRows(keepSelection: true)
        }
    }

    private func showRecent() {
        appResults = []
        fileResults = []
        let apps = Dictionary(catalog.items.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var recent: [RankedItem] = []
        for path in usage.book.mostUsed(limit: Self.recentLimit * 3, now: Date()) where recent.count < Self.recentLimit {
            if let app = apps[path] {
                recent.append(RankedItem(item: app))
            } else if FileManager.default.fileExists(atPath: path) {
                let name = (path as NSString).lastPathComponent
                recent.append(RankedItem(item: SearchItem(kind: .file, path: path, displayName: name)))
            }
        }
        rows = recent.isEmpty ? [] : [.header(String(localized: "Recent"))] + recent.map(ResultRow.item)
        reloadTable(selecting: nil)
    }

    private func rebuildRows(keepSelection: Bool) {
        let selected = keepSelection ? selectedItem?.id : nil
        var rows: [ResultRow] = []
        if !appResults.isEmpty {
            rows.append(.header(String(localized: "Applications")))
            rows += appResults.map(ResultRow.item)
        }
        if !fileResults.isEmpty {
            rows.append(.header(String(localized: "Files")))
            rows += fileResults.map(ResultRow.item)
        }
        self.rows = rows
        reloadTable(selecting: selected)
    }

    private func reloadTable(selecting id: String?) {
        table.reloadData()
        let kept = id.flatMap { id in rows.firstIndex { $0.item?.id == id } }
        let target = kept ?? rows.firstIndex { $0.item != nil }
        resizeToRows()
        if let target {
            table.selectRowIndexes(IndexSet(integer: target), byExtendingSelection: false)
            // A new list starts at the top, with its first header in view.
            table.scrollRowToVisible(kept == nil ? 0 : target)
        }
    }

    // MARK: Debug

    /// Types "ni" into the search field through its input context, as `AppFinderFixture`'s probe
    /// does: whether an input method composed it shows which one really handles the field's keys.
    func debugProbe() -> [String: Any] {
        guard let editor = field.currentEditor() as? NSTextView, let context = editor.inputContext else {
            return ["error": "the search field is not being edited"]
        }
        let before = field.stringValue
        let source = CGEventSource(stateID: .privateState)
        for code in [CGKeyCode(kVK_ANSI_N), CGKeyCode(kVK_ANSI_I)] {
            for down in [true, false] {
                guard let cgEvent = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down),
                      let event = NSEvent(cgEvent: cgEvent)
                else { continue }
                _ = context.handleEvent(event)
            }
        }
        let composed = editor.hasMarkedText()
        let typed = field.stringValue
        context.discardMarkedText()
        editor.unmarkText()
        setQuery(before)
        return ["composed": composed, "typed": typed, "inputSource": inputSources.currentID() ?? NSNull()]
    }

    func debugState() -> [String: Any] {
        [
            "open": isOpen,
            "closing": isClosing,
            "visible": panel.isVisible,
            "key": panel.isKeyWindow,
            "appActive": NSApp.isActive,
            "query": field.stringValue,
            "selectedText": (field.currentEditor()?.selectedRange).map { NSStringFromRange($0) } ?? NSNull(),
            "listScrolls": scroll.hasVerticalScroller,
            "selected": selectedItem?.item.path ?? NSNull(),
            "rows": rows.map { row -> [String: Any] in
                switch row {
                case .header(let title): ["header": title]
                case .item(let ranked): [
                    "kind": ranked.item.kind.rawValue, "name": ranked.item.displayName,
                    "path": ranked.item.path, "score": ranked.total,
                ]
                }
            },
            "inputSource": inputSources.currentID() ?? NSNull(),
            "fieldContextSource": fieldInputContext?.selectedKeyboardInputSource ?? NSNull(),
            "lockTarget": lock.target,
            "lockEngaged": lock.isEngaged,
            "saved": lock.saved ?? NSNull(),
            "lockCorrections": lockCorrections,
            "lastOpen": lastOpen,
            "lastClose": lastClose,
            "lastFileSearch": lastFileSearch,
            "catalogCount": catalog.items.count,
        ]
    }
}

// MARK: - Delegates

extension SearchController: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        queryChanged()
    }
}

extension SearchController: NSWindowDelegate {
    /// The panel has no undo manager of its own; the search field's edits need one for Cmd+Z.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        undoManager
    }

    func windowDidResignKey(_ notification: Notification) {
        // Another window took the focus (a click elsewhere, Cmd+Tab): the panel goes away.
        guard isOpen, !isClosing else { return }
        close(.focusLost)
    }
}

extension SearchController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        rows[row].item == nil ? Self.headerHeight : Self.rowHeight
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        rows[row].item != nil
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ResultRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let title):
            let view = tableView.makeView(withIdentifier: HeaderCellView.identifier, owner: nil) as? HeaderCellView
                ?? HeaderCellView(frame: .zero)
            view.show(title)
            return view
        case .item(let ranked):
            let view = tableView.makeView(withIdentifier: ResultCellView.identifier, owner: nil) as? ResultCellView
                ?? ResultCellView(frame: .zero)
            view.show(ranked, icon: icons.icon(for: ranked.item.path))
            return view
        }
    }
}

/// Draws the selection as a rounded rectangle inset from the panel's edges, in the accent colour
/// although the table never has the keyboard focus (the search field keeps it).
final class ResultRowView: NSTableRowView {
    static let inset: CGFloat = 8

    override var isEmphasized: Bool {
        get { true }
        set {}
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: Self.inset, dy: 1), xRadius: 8, yRadius: 8).fill()
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
