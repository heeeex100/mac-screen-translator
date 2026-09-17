import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 把 AppKit 按键录制按钮包装成 SwiftUI 控件。
struct ShortcutRecorder: NSViewRepresentable {
    let title: String
    let onRecord: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.onRecord = onRecord
        button.title = title
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.onRecord = onRecord
        if !button.isRecording { button.title = title }
    }
}

final class ShortcutRecorderButton: NSButton {
    var onRecord: ((UInt32, UInt32) -> Void)?
    var isRecording = false
    private var previousTitle = ""
    private var keyMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() {
        // 录制期间临时接管应用内的 keyDown，防止组合键被设置页中的输入框消费。
        stopMonitoring()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        isRecording = true
        previousTitle = title
        title = "请按新的组合键…"
        window?.makeFirstResponder(self)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }
            self.record(event)
            return nil
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        record(event)
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            title = previousTitle
            window?.makeFirstResponder(nil)
            stopMonitoring()
            return
        }
        // 只保留与设备无关的修饰键，忽略 Caps Lock、数字键盘等附加标志。
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        guard modifiers != 0 else {
            title = "请同时按 ⌘、⌃、⌥ 或 ⇧"
            return
        }
        isRecording = false
        onRecord?(UInt32(event.keyCode), modifiers)
        window?.makeFirstResponder(nil)
        stopMonitoring()
    }

    private func stopMonitoring() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    deinit {
        stopMonitoring()
    }
}
