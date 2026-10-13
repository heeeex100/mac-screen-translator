import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// 管理应用生命周期，以及 SwiftUI Scene 之外的 AppKit 能力：菜单栏、全局快捷键和系统权限。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = TranslationStore()
    let visibilityController = AppVisibilityController()
    private var hotKeyRegistry: HotKeyRegistry<EventHotKeyRef>?
    private var eventHandler: EventHandlerRef?
    private var selectionOverlay: SelectionOverlay?
    private var hotkeyEnabled = true
    private var statusItem: NSStatusItem?
    private var captureMenuItem: NSMenuItem?
    private var clipboardMenuItem: NSMenuItem?
    private var translationObserver: NSObjectProtocol?
    private let translationPanelController = TranslationResultPanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run` 启动的是普通可执行文件，不一定会自动采用 GUI 应用的激活策略。
        // 显式设置后，输入框才能稳定接收键盘事件，而不是把输入继续发送给 Terminal。
        // 保留 Dock 图标，关闭或隐藏窗口后仍可从 Dock 重新打开。
        NSApp.setActivationPolicy(.regular)
        setupStatusItem()
        translationObserver = NotificationCenter.default.addObserver(
            forName: .translationCompleted, object: nil, queue: .main
        ) { [weak self] notification in
            guard let result = notification.object as? TranslationDisplayResult else { return }
            MainActor.assumeIsolated {
                if let self { self.translationPanelController.show(result, store: self.store) }
            }
        }
        configureGlobalHotkey()
        checkRequiredPermissions()
        showMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 无论其他面板是否可见，都恢复应用自己持有的主窗口。
        showMainWindow()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = hotKeyRegistry?.setEnabled(false)
        if let eventHandler { RemoveEventHandler(eventHandler) }
        if let translationObserver { NotificationCenter.default.removeObserver(translationObserver) }
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    private func setupStatusItem() {
        // NSStatusItem 必须由 AppDelegate 强引用，否则创建后会立即从菜单栏消失。
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = Self.makeStatusIcon()
            button.imagePosition = .imageOnly
            button.toolTip = "多多翻译"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "显示主窗口", action: #selector(showMainWindow), keyEquivalent: "")
        let captureItem = menu.addItem(withTitle: "", action: #selector(startCapture), keyEquivalent: "")
        captureMenuItem = captureItem
        updateCaptureMenuTitle()
        menu.addItem(withTitle: "框选 OCR（自动复制）", action: #selector(startOCR), keyEquivalent: "")
        let clipboardItem = menu.addItem(withTitle: "", action: #selector(translateClipboard), keyEquivalent: "")
        clipboardMenuItem = clipboardItem
        updateClipboardMenuTitle()
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出多多翻译", action: #selector(terminate), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private static func makeStatusIcon() -> NSImage? {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        for name in ["StatusIcon", "StatusIcon@2x"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
                  let data = try? Data(contentsOf: url),
                  let representation = NSBitmapImageRep(data: data) else { continue }
            representation.size = size
            image.addRepresentation(representation)
        }
        guard !image.representations.isEmpty else {
            return NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "多多翻译")
        }
        // 使用 alpha 轮廓，由 macOS 按明暗主题和菜单选中状态着色。
        image.isTemplate = true
        return image
    }

    private func updateCaptureMenuTitle() {
        captureMenuItem?.title = "框选翻译  \(store.captureShortcutTitle)"
    }

    private func updateClipboardMenuTitle() {
        clipboardMenuItem?.title = "翻译剪贴板  \(store.clipboardShortcutTitle)"
    }

    @objc private func showMainWindow() {
        visibilityController.showMainWindow(
            store: store,
            capture: { [weak self] in self?.captureRequested() },
            recognize: { [weak self] in self?.captureRequested(mode: .ocr) },
            setHotkeyEnabled: { [weak self] enabled in self?.setHotkeyEnabled(enabled) }
        )
    }

    func hideMainWindow() {
        visibilityController.hideToMenuBar()
    }

    @objc private func startCapture() {
        captureRequested()
    }

    @objc private func startOCR() {
        captureRequested(mode: .ocr)
    }

    @objc private func translateClipboard() {
        store.translateClipboard()
    }

    @objc private func openSettings() {
        showMainWindow()
        // Let the status-item menu finish dismissing before presenting the sheet.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .openTranslationSettings, object: nil)
        }
    }

    @objc private func terminate() {
        NSApp.terminate(nil)
    }

    func setHotkeyEnabled(_ enabled: Bool) {
        guard hotkeyEnabled != enabled else { return }
        hotkeyEnabled = enabled
        configureGlobalHotkey()
    }

    private func configureGlobalHotkey() {
        if hotKeyRegistry == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let userData = Unmanaged.passUnretained(self).toOpaque()
            let status = InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, userData, &eventHandler)
            guard status == noErr else {
                store.shortcutError = "快捷键事件处理器安装失败，请重启应用。"
                return
            }
            let capture = store.captureShortcut
            let clipboard = store.clipboardShortcut
            hotKeyRegistry = HotKeyRegistry(shortcuts: [
                .capture: HotKeyShortcut(keyCode: capture.keyCode, modifiers: capture.modifiers),
                .clipboard: HotKeyShortcut(keyCode: clipboard.keyCode, modifiers: clipboard.modifiers)
            ], register: { action, shortcut in
                var handle: EventHotKeyRef?
                let id = EventHotKeyID(signature: OSType(0x5354524E), id: action.id)
                let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                                                GetApplicationEventTarget(), 0, &handle)
                return status == noErr ? handle : nil
            }, unregister: { UnregisterEventHotKey($0) })
            store.registerShortcut = { [weak self] action, shortcut in
                guard let self, let registry = self.hotKeyRegistry else { return "快捷键服务尚未就绪。" }
                let error = registry.update(action, to: shortcut)
                if error == nil {
                    // setter 在回调返回后保存配置，下一轮刷新菜单。
                    DispatchQueue.main.async { [weak self] in
                        self?.updateCaptureMenuTitle()
                        self?.updateClipboardMenuTitle()
                    }
                }
                return error
            }
        }
        let errors = hotKeyRegistry?.setEnabled(hotkeyEnabled) ?? []
        if !errors.isEmpty {
            store.shortcutError = errors.joined(separator: "\n")
            store.status = errors.joined(separator: " ")
        }
    }

    private func checkRequiredPermissions() {
        // CGDisplayCreateImage 受“屏幕录制”权限保护；OCR 本身不需要额外权限。
        let screenRecordingGranted = CGPreflightScreenCaptureAccess()

        guard !screenRecordingGranted else { return }

        let alert = NSAlert()
        alert.messageText = "需要系统权限"
        alert.informativeText = "要进行截图和文字识别，请在“系统设置 → 隐私与安全性 → 屏幕录制”中允许此应用。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后处理")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    typealias CaptureMode = CaptureOperation

    func captureRequested(mode: CaptureMode = .translation) {
        // 系统可能重复投递同一次热键事件。持有唯一遮罩，直到框选完成或取消，
        // 可以防止叠出两个遮罩、要求用户框选两次。
        guard selectionOverlay == nil else {
            AppLogger.shared.info("忽略框选请求：框选面板已经存在")
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else {
            AppLogger.shared.error("框选失败：找不到当前屏幕")
            return
        }
        store.prepareForCapture()
        translationPanelController.hide()
        let mainWindowWasVisible = visibilityController.hideMainWindowForCapture()
        store.status = mode == .ocr ? "请框选要识别的区域…" : "请框选要翻译的区域…"
        AppLogger.shared.info("开始框选：模式=\(mode == .ocr ? "OCR" : "翻译")，屏幕=\(screen.frame)")
        var submitted = false
        selectionOverlay = SelectionOverlay.present(
            on: screen,
            completion: { [weak self] rect in
                guard let self else { return }
                submitted = true
                if mode == .ocr { self.store.recognize(selection: rect, on: screen) }
                else { self.store.translate(selection: rect, on: screen) }
            },
            onDismiss: { [weak self] in
                guard let self else { return }
                self.selectionOverlay = nil
                if !submitted { self.store.status = "框选已取消。" }
                AppLogger.shared.info("框选结束或取消")
                self.visibilityController.restoreMainWindowAfterCapture(wasVisible: mainWindowWasVisible)
            }
        )
    }
}

private func hotKeyHandler(_ nextHandler: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return noErr }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
    var hotKeyID = EventHotKeyID()
    guard let event,
          GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                            nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID) == noErr else { return noErr }
    DispatchQueue.main.async {
        if hotKeyID.id == 2 { delegate.store.translateClipboard() }
        else { delegate.captureRequested() }
    }
    return noErr
}
