import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: TranslationStore
    @EnvironmentObject var visibilityController: AppVisibilityController
    @State private var settingsShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("截图翻译器").font(.title2.bold())
                Spacer()
                Button("隐藏到菜单栏") {
                    visibilityController.hideToMenuBar()
                }
                Button("设置") { settingsShown = true }
            }
            // 快捷键只在 AppDelegate 中注册；如果 SwiftUI 再注册一次，会叠出两个框选遮罩。
            HStack {
                Button("框选翻译  \(store.captureShortcutTitle)") {
                    NSApp.delegate.flatMap { ($0 as? AppDelegate)?.captureRequested() }
                }
                Button("翻译剪贴板") {
                    store.translateClipboard()
                }
            }
            .disabled(store.isTranslating)
            Text(store.status).foregroundStyle(store.status == "翻译完成" ? .green : .secondary)
            Text("识别原文").font(.headline)
            TextEditor(text: .constant(store.source)).frame(height: 150).disabled(true)
            Text("译文").font(.headline)
            TextEditor(text: .constant(store.translation)).frame(height: 180).disabled(true)
        }
        .padding(20).frame(width: 720, height: 560)
        .sheet(isPresented: $settingsShown) { SettingsView().environmentObject(store) }
        .onReceive(NotificationCenter.default.publisher(for: .openTranslationSettings)) { _ in
            settingsShown = true
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject var store: TranslationStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: SettingsField?

    private enum SettingsField {
        case apiKey
        case model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DeepSeek 设置").font(.title2.bold())
            SecureField("DeepSeek API Key", text: $store.apiKey)
                .focused($focusedField, equals: .apiKey)
            if let error = store.apiKeyStorageError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            TextField("模型", text: $store.model)
                .focused($focusedField, equals: .model)
            HStack {
                Text("截图快捷键")
                Spacer()
                ShortcutRecorder(title: store.captureShortcutTitle) { keyCode, modifiers in
                    store.setCaptureShortcut(keyCode: keyCode, modifiers: modifiers)
                }
                .frame(width: 180, height: 28)
            }
            Picker("目标语言", selection: $store.targetLanguage) {
                Text("中文（简体）").tag("中文（简体）"); Text("English").tag("English")
                Text("日本語").tag("日本語"); Text("한국어").tag("한국어")
            }
            Text("接口：https://api.deepseek.com/chat/completions\n模型默认：deepseek-flash")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(24).frame(width: 460)
        .onAppear {
            (NSApp.delegate as? AppDelegate)?.setHotkeyEnabled(false)
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                focusedField = .apiKey
            }
        }
        .onDisappear { (NSApp.delegate as? AppDelegate)?.setHotkeyEnabled(true) }
    }
}
