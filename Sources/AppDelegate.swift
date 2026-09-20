import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// 管理应用生命周期，以及 SwiftUI Scene 之外的 AppKit 能力：菜单栏、全局快捷键和系统权限。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = TranslationStore()
    let visibilityController = AppVisibilityController()
    private var hotKey: EventHotKeyRef?
    private var clipboardHotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var selectionOverlay: SelectionOverlay?
    private var hotkeyEnabled = true
    private var hotkeyObserver: NSObjectProtocol?
    private var clipboardHotkeyObserver: NSObjectProtocol?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var previousExternalApplication: NSRunningApplication?
    private var statusItem: NSStatusItem?
    private var captureMenuItem: NSMenuItem?
    private var clipboardMenuItem: NSMenuItem?
    private var translationObserver: NSObjectProtocol?
    private var accessibilityObserver: NSObjectProtocol?
    private let translationPanelController = TranslationResultPanelController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 在应用第一次激活前记录启动它的外部应用，覆盖“先在浏览器选中文字，
        // 再打开截图翻译器”的常见使用方式。
        let application = NSWorkspace.shared.frontmostApplication
        if let application, application.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousExternalApplication = application
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run` 启动的是普通可执行文件，不一定会自动采用 GUI 应用的激活策略。
        // 显式设置后，输入框才能稳定接收键盘事件，而不是把输入继续发送给 Terminal。
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: .captureHotkeyChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.configureGlobalHotkey()
            self?.updateCaptureMenuTitle()
        }
        clipboardHotkeyObserver = NotificationCenter.default.addObserver(
            forName: .clipboardHotkeyChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.configureGlobalHotkey()
            self?.updateClipboardMenuTitle()
        }
        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self.previousExternalApplication = application
        }
        translationObserver = NotificationCenter.default.addObserver(
            forName: .translationCompleted, object: nil, queue: .main
        ) { [weak self] notification in
            guard let result = notification.object as? TranslationDisplayResult else { return }
            if let self { self.translationPanelController.show(result, store: self.store) }
        }
        accessibilityObserver = NotificationCenter.default.addObserver(
            forName: .openAccessibilitySettings, object: nil, queue: .main
        ) { [weak self] _ in self?.openAccessibilitySettings() }
        configureGlobalHotkey()
        checkRequiredPermissions()
        showMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let clipboardHotKey { UnregisterEventHotKey(clipboardHotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        if let hotkeyObserver { NotificationCenter.default.removeObserver(hotkeyObserver) }
        if let clipboardHotkeyObserver { NotificationCenter.default.removeObserver(clipboardHotkeyObserver) }
        if let workspaceActivationObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver) }
        if let translationObserver { NotificationCenter.default.removeObserver(translationObserver) }
        if let accessibilityObserver { NotificationCenter.default.removeObserver(accessibilityObserver) }
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
        menu.addItem(withTitle: "框选 OCR（自动复制）", action: #selector(startOCR), keyEquivalent: "")
        menu.addItem(withTitle: "翻译选中文字", action: #selector(translateSelection), keyEquivalent: "")
        let clipboardItem = menu.addItem(withTitle: "", action: #selector(translateClipboard), keyEquivalent: "")
        clipboardMenuItem = clipboardItem
        updateClipboardMenuTitle()
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

    private func updateClipboardMenuTitle() {
        clipboardMenuItem?.title = "翻译剪贴板  \(store.clipboardShortcutTitle)"
    }

    @objc private func showMainWindow() {
        visibilityController.showMainWindow(store: store)
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

    @objc private func translateSelection() {
        translateSelectedText()
    }

    /// 点击主窗口按钮会先让原来选中文字的应用重新获得焦点，再读取选区。
    /// 这样用户不必在“选中文字”之后重新复制，也不会因为点击本应用而丢失选区。
    func translateSelectedText() {
        guard let target = previousExternalApplication, !target.isTerminated else {
            store.translateSelectedText()
            return
        }

        let wasVisible = visibilityController.hideMainWindowForCapture()
        store.status = "正在读取外部应用中的选中文字…"
        target.activate(options: [.activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.store.translateSelectedText()
            self.visibilityController.restoreMainWindowAfterCapture(wasVisible: wasVisible)
        }
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

    @objc private func openAccessibilitySettings() {
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = "读取其他应用中选中的文字需要辅助功能权限。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后处理")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
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
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let clipboardHotKey { UnregisterEventHotKey(clipboardHotKey); self.clipboardHotKey = nil }
        guard hotkeyEnabled else { return }
        let capture = store.captureShortcut
        let clipboard = store.clipboardShortcut
        guard capture.keyCode != clipboard.keyCode || capture.modifiers != clipboard.modifiers else {
            store.status = "两个快捷键不能设置为同一组合键。"
            return
        }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        if eventHandler == nil {
            let userData = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, userData, &eventHandler)
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x5354524E), id: 1) // STRN
        let captureStatus = RegisterEventHotKey(capture.keyCode, capture.modifiers, hotKeyID,
                                                GetApplicationEventTarget(), 0, &hotKey)
        guard captureStatus == noErr else {
            hotKey = nil
            store.status = "截图快捷键注册失败，可能已被其他应用占用。"
            return
        }
        let clipboardID = EventHotKeyID(signature: OSType(0x5354524E), id: 2) // STRN
        let clipboardStatus = RegisterEventHotKey(clipboard.keyCode, clipboard.modifiers, clipboardID,
                                                  GetApplicationEventTarget(), 0, &clipboardHotKey)
        guard clipboardStatus == noErr else {
            if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
            clipboardHotKey = nil
            store.status = "剪贴板快捷键注册失败，可能已被其他应用占用。"
            return
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

    enum CaptureMode { case translation, ocr }

    func captureRequested(mode: CaptureMode = .translation) {
        // 系统可能重复投递同一次热键事件。持有唯一遮罩，直到框选完成或取消，
        // 可以防止叠出两个遮罩、要求用户框选两次。
        guard !store.isTranslating, selectionOverlay == nil else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return }
        let mainWindowWasVisible = visibilityController.hideMainWindowForCapture()
        store.status = mode == .ocr ? "请框选要识别的区域…" : "请框选要翻译的区域…"
        selectionOverlay = SelectionOverlay.present(
            on: screen,
            completion: { [weak self] rect in
                guard let self else { return }
                if mode == .ocr { self.store.recognize(selection: rect, on: screen) }
                else { self.store.translate(selection: rect, on: screen) }
                // 截图已在上面的调用中同步完成，现在可以恢复主窗口。
                self.visibilityController.restoreMainWindowAfterCapture(wasVisible: mainWindowWasVisible)
            },
            onDismiss: { [weak self] in
                guard let self else { return }
                self.selectionOverlay = nil
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
