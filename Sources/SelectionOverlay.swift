import AppKit

final class SelectionOverlay: NSWindow {
    private var completion: ((NSRect) -> Void)?

    static func present(on screen: NSScreen, completion: @escaping (NSRect) -> Void) {
        let window = SelectionOverlay(screen: screen, completion: completion)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(screen: NSScreen, completion: @escaping (NSRect) -> Void) {
        self.completion = completion
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = SelectionView { [weak self] rect in
            guard let self else { return }
            self.orderOut(nil)
            self.completion?(rect)
            self.completion = nil
        }
    }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
        completion = nil
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
