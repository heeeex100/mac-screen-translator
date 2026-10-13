import AppKit

/// 松开鼠标后保留选区，确认后才隐藏遮罩并截图。
final class SelectionOverlay: NSPanel {
    private var completion: ((NSRect) -> Void)?
    private var onDismiss: (() -> Void)?
    private var pendingCapture: DispatchWorkItem?
    private let selectionView = SelectionView(frame: .zero)
    private let confirmButton = NSButton(title: "确认（Enter）", target: nil, action: nil)

    @discardableResult
    static func present(on screen: NSScreen, completion: @escaping (NSRect) -> Void,
                        onDismiss: @escaping () -> Void) -> SelectionOverlay {
        let window = SelectionOverlay(screen: screen, completion: completion, onDismiss: onDismiss)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.makeFirstResponder(window.selectionView)
        return window
    }

    init(screen: NSScreen, completion: @escaping (NSRect) -> Void, onDismiss: @escaping () -> Void) {
        self.completion = completion
        self.onDismiss = onDismiss
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        contentView = selectionView
        selectionView.changed = { [weak self] in self?.confirmButton.isEnabled = self?.selectionView.selection != nil }
        let reset = NSButton(title: "重新框选", target: self, action: #selector(resetSelection))
        let cancel = NSButton(title: "取消（Esc）", target: self, action: #selector(cancelSelection))
        confirmButton.target = self
        confirmButton.action = #selector(confirmSelection)
        confirmButton.isEnabled = false
        let hint = NSTextField(labelWithString: "拖动框选，松开后可重选；Enter 确认，Esc 取消")
        hint.textColor = .white
        let toolbar = NSStackView(views: [hint, reset, cancel, confirmButton])
        toolbar.spacing = 12
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        selectionView.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.centerXAnchor.constraint(equalTo: selectionView.centerXAnchor),
            toolbar.topAnchor.constraint(equalTo: selectionView.topAnchor, constant: 36)
        ])
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    @objc private func resetSelection() {
        selectionView.reset()
        makeFirstResponder(selectionView)
    }

    @objc private func cancelSelection() { cancelOperation(nil) }

    @objc private func confirmSelection() {
        guard pendingCapture == nil, let rect = selectionView.selection, completion != nil else { return }
        orderOut(nil)
        // 等遮罩消失后截图；取消窗口时也取消待执行回调。
        let work = DispatchWorkItem { [weak self] in
            guard let self, let completion = self.completion else { return }
            self.completion = nil
            self.pendingCapture = nil
            completion(rect)
            self.dismiss()
        }
        pendingCapture = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { confirmSelection() }
        else if event.keyCode == 53 { cancelOperation(nil) }
        else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) {
        pendingCapture?.cancel()
        pendingCapture = nil
        completion = nil
        orderOut(nil)
        dismiss()
    }

    private func dismiss() {
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }
}

private final class SelectionView: NSView {
    private var start: NSPoint?
    private var current: NSPoint?
    private var dragging = false
    var changed: (() -> Void)?

    var selection: NSRect? {
        guard !dragging, let start, let current else { return nil }
        let rect = NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                          width: abs(current.x - start.x), height: abs(current.y - start.y))
        return rect.width > 8 && rect.height > 8 ? rect : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func reset() {
        start = nil; current = nil; dragging = false
        needsDisplay = true
        changed?()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        start = convert(event.locationInWindow, from: nil)
        current = start
        dragging = true
        changed?()
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        dragging = false
        changed?()
        needsDisplay = true
    }
    override func rightMouseDown(with event: NSEvent) { reset() }
    override func keyDown(with event: NSEvent) { window?.keyDown(with: event) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill(); bounds.fill()
        guard let start, let current else { return }
        let rect = NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                          width: abs(current.x - start.x), height: abs(current.y - start.y))
        NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
        NSBezierPath(rect: rect).fill()
        NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
        NSColor.systemCyan.setStroke()
        let path = NSBezierPath(rect: rect); path.lineWidth = 2; path.stroke()
    }
}
