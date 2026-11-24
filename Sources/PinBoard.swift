import AppKit

/// 贴图板只保存每张贴图自己的像素或文字，以及那张贴图的任务。
/// 不调用 `TranslationStore`，也不注册全局热键。窗口保持隐藏，直到以后的交互 PR 再显示。
@MainActor
final class PinBoard {
    private(set) var pins: [ScreenPin] = []

    @discardableResult
    func pinImage(_ image: CGImage) throws -> ScreenPin {
        try add(.fromImage(image))
    }

    @discardableResult
    func pinText(_ text: String) throws -> ScreenPin {
        try add(.fromText(text))
    }

    /// 只取消这一张的生存期。其他贴图的任务继续。
    func close(_ pin: ScreenPin) {
        guard let index = pins.firstIndex(where: { $0 === pin }) else { return }
        pins.remove(at: index)
        pin.lifetime.cancel()
        pin.panel.orderOut(nil)
        pin.panel.close()
    }

    private func add(_ content: PinContent) -> ScreenPin {
        let pin = ScreenPin(content: content, panel: Self.makeHiddenPanel(for: content))
        pins.append(pin)
        return pin
    }

    private static func makeHiddenPanel(for content: PinContent) -> NSPanel {
        let size = panelSize(for: content)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "贴图"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = contentView(for: content, size: size)
        panel.orderOut(nil)
        return panel
    }

    private static func panelSize(for content: PinContent) -> NSSize {
        if let image = content.image {
            return NSSize(width: max(image.width, 1), height: max(image.height, 1))
        }
        return NSSize(width: 240, height: 80)
    }

    private static func contentView(for content: PinContent, size: NSSize) -> NSView {
        if let image = content.image {
            let view = NSImageView(frame: NSRect(origin: .zero, size: size))
            view.image = NSImage(cgImage: image, size: size)
            view.imageScaling = .scaleProportionallyUpOrDown
            return view
        }
        let field = NSTextField(labelWithString: content.text ?? "")
        field.frame = NSRect(origin: .zero, size: size)
        field.maximumNumberOfLines = 0
        return field
    }
}

@MainActor
final class ScreenPin {
    let content: PinContent
    let lifetime: PinLifetime
    private(set) var job: TranslationJob
    let panel: NSPanel

    fileprivate init(content: PinContent, panel: NSPanel) {
        self.content = content
        let lifetime = PinLifetime()
        self.lifetime = lifetime
        self.job = TranslationJob.start(lifetime: lifetime)
        self.panel = panel
    }

    /// 换一次新尝试，不取消换下去的那一次。调用方要丢掉旧结果时先 `cancel()`。
    @discardableResult
    func nextAttempt() -> TranslationJob {
        let next = job.nextAttempt()
        job = next
        return next
    }
}
