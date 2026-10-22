import AppKit
import SwiftUI

/// 持有唯一主窗口，关闭后仍可通过菜单栏恢复。
@MainActor
final class AppVisibilityController: ObservableObject {
    private var mainWindow: NSWindow?

    func hideToMenuBar() {
        NSApp.hide(nil)
    }

    /// 隐藏主窗口但保留应用本身，供截图面板覆盖真实桌面内容。
    /// 返回值用于在截图结束或取消时恢复原来的窗口状态。
    @discardableResult
    func hideMainWindowForCapture() -> Bool {
        guard let mainWindow, mainWindow.isVisible else { return false }
        mainWindow.orderOut(nil)
        return true
    }

    func restoreMainWindowAfterCapture(wasVisible: Bool) {
        guard wasVisible, let mainWindow else { return }
        mainWindow.orderFrontRegardless()
        mainWindow.makeKey()
    }

    func showMainWindow(store: TranslationStore, capture: @escaping () -> Void,
                        recognize: @escaping () -> Void,
                        setHotkeyEnabled: @escaping (Bool) -> Void) {
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 790),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.minSize = NSSize(width: 560, height: 620)
            window.setFrameAutosaveName("translatorMainWindow")
            window.title = "多多翻译"
            window.identifier = NSUserInterfaceItemIdentifier("translatorMainWindow")
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: ContentView(capture: capture,
                                                recognize: recognize, setHotkeyEnabled: setHotkeyEnabled)
                .environmentObject(store)
                .environmentObject(self))
            window.center()
            mainWindow = window
        }

        // 等菜单收起，再激活并恢复明确持有的主窗口。
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.mainWindow else { return }
            NSApp.unhide(nil)
            if window.isMiniaturized { window.deminiaturize(nil) }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }
}
