import SwiftUI

@main
struct MacScreenTranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("截图翻译器") {
            ContentView()
                .environmentObject(appDelegate.store)
                .environmentObject(appDelegate.visibilityController)
        }
        .windowResizability(.contentSize)
    }
}
