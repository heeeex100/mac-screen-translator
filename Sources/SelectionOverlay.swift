import AppKit

/// 覆盖目标屏幕的透明框选面板。
/// 显式获取键盘焦点以接收框选操作和 Escape。
final class SelectionOverlay: NSPanel {
    private var completion: ((NSRect) -> Void)?
    private var onDismiss: (() -> Void)?

    @discardableResult
    static func present(
        on screen: NSScreen,
        completion: @escaping (NSRect) -> Void,
        onDismiss: @escaping () -> Void
    ) -> SelectionOverlay {
        let window = SelectionOverlay(screen: screen, completion: completion, onDismiss: onDismiss)
        // 框选面板必须成为 Key Window 才能稳定接收鼠标拖拽和 Escape。
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        if let contentView = window.contentView {
            window.makeFirstResponder(contentView)
        }
        return window
    }

    init(screen: NSScreen, completion: @escaping (NSRect) -> Void, onDismiss: @escaping () -> Void) {
        self.completion = completion
        self.onDismiss = onDismiss
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        contentView = SelectionView { [weak self] rect in
            guard let self else { return }
            // 隐藏遮罩后给 WindowServer 留一个合成周期；立即截图会把半透明遮罩也截进去，
            // 从而降低 OCR 的识别率。
            let completion = self.completion
            self.completion = nil
            self.orderOut(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                // 先让调用方同步完成 CGDisplay 截图，再通知外层恢复主窗口；否则主窗口
                // 会在截图前重新出现，导致 OCR 截到翻译器自己的界面。
                completion?(rect)
                self?.onDismiss?()
                self?.onDismiss = nil
            }
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
        completion = nil
        onDismiss?()
        onDismiss = nil
    }
}

private final class SelectionView: NSView {
    private var start: NSPoint?
    private var current: NSPoint?
    private let selected: (NSRect) -> Void

    init(selected: @escaping (NSRect) -> Void) { self.selected = selected; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil); current = start; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let start, let current else { return }
        let rect = NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                          width: abs(current.x - start.x), height: abs(current.y - start.y))
        if rect.width > 8, rect.height > 8 { selected(rect) }
    }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { window?.cancelOperation(self) } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill(); bounds.fill()
        guard let start, let current else { return }
        let rect = NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                          width: abs(current.x - start.x), height: abs(current.y - start.y))
        NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
        NSBezierPath(rect: rect).fill()
        NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
        NSColor.systemCyan.setStroke(); let path = NSBezierPath(rect: rect); path.lineWidth = 2; path.stroke()
    }
}
