import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// 管理应用生命周期，以及 SwiftUI Scene 之外的 AppKit 能力：菜单栏、全局快捷键和系统权限。
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = TranslationStore()
    let visibilityController = AppVisibilityController()
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var selectionOverlay: SelectionOverlay?
    private var hotkeyEnabled = true
    private var hotkeyObserver: NSObjectProtocol?
    private var statusItem: NSStatusItem?
    private var captureMenuItem: NSMenuItem?
    private var translationObserver: NSObjectProtocol?
    private let translationPanelController = TranslationResultPanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run` 启动的是普通可执行文件，不一定会自动采用 GUI 应用的激活策略。
        // 显式设置后，输入框才能稳定接收键盘事件，而不是把输入继续发送给 Terminal。
        NSApp.setActivationPolicy(.regular)
        setupStatusItem()
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: .captureHotkeyChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.configureGlobalHotkey()
            self?.updateCaptureMenuTitle()
        }
        translationObserver = NotificationCenter.default.addObserver(
            forName: .translationCompleted, object: nil, queue: .main
        ) { [weak self] notification in
            guard let result = notification.object as? TranslationDisplayResult else { return }
            self?.translationPanelController.show(result)
        }
        configureGlobalHotkey()
        checkRequiredPermissions()
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        if let hotkeyObserver { NotificationCenter.default.removeObserver(hotkeyObserver) }
        if let translationObserver { NotificationCenter.default.removeObserver(translationObserver) }
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    private func setupStatusItem() {
        // NSStatusItem 必须由 AppDelegate 强引用，否则创建后会立即从菜单栏消失。
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "截图翻译器")
            button.imagePosition = .imageOnly
            button.toolTip = "截图翻译器"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "显示主窗口", action: #selector(showMainWindow), keyEquivalent: "")
        let captureItem = menu.addItem(withTitle: "", action: #selector(startCapture), keyEquivalent: "")
        captureMenuItem = captureItem
        updateCaptureMenuTitle()
        menu.addItem(withTitle: "翻译剪贴板", action: #selector(translateClipboard), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出截图翻译器", action: #selector(terminate), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private func updateCaptureMenuTitle() {
        captureMenuItem?.title = "框选翻译  \(store.captureShortcutTitle)"
    }

    @objc private func showMainWindow() {
        visibilityController.showMainWindow()
    }

    func hideMainWindow() {
        visibilityController.hideToMenuBar()
    }

    @objc private func startCapture() {
        captureRequested()
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
        // Carbon 热键可以在应用不活跃时工作，也不需要辅助功能权限。
        // 每次设置变化时先注销旧热键，避免同一个按键触发多个框选窗口。
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        guard hotkeyEnabled else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        if eventHandler == nil {
            let userData = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, userData, &eventHandler)
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x5354524E), id: 1) // STRN
        let shortcut = store.captureShortcut
        RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKey)
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

    func captureRequested() {
        // 系统可能重复投递同一次热键事件。持有唯一遮罩，直到框选完成或取消，
        // 可以防止叠出两个遮罩、要求用户框选两次。
        guard !store.isTranslating, selectionOverlay == nil else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return }
        selectionOverlay = SelectionOverlay.present(
            on: screen,
            completion: { [weak self] rect in self?.store.translate(selection: rect, on: screen) },
            onDismiss: { [weak self] in self?.selectionOverlay = nil }
        )
    }
}

private func hotKeyHandler(_ nextHandler: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return noErr }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { delegate.captureRequested() }
    return noErr
}
