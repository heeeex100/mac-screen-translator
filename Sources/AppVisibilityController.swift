import AppKit
import Combine

/// 统一控制主界面的显示状态，供 SwiftUI 按钮和菜单栏菜单共同使用。
final class AppVisibilityController: ObservableObject {
    func hideToMenuBar() {
        // 隐藏应用不会终止进程，因此全局热键和菜单栏图标仍然有效。
        NSApp.hide(nil)
    }

    func showMainWindow() {
        // 先解除应用隐藏状态，再把现有 SwiftUI 窗口带到前台。
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)

        let window = NSApp.windows.first(where: { $0.canBecomeMain })
        window?.makeKeyAndOrderFront(nil)
    }
}
