import SwiftUI

@main
struct MacScreenTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 主窗口由 AppVisibilityController 管理，避免关闭后失去窗口引用。
        Settings { EmptyView() }
    }
}
