import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: TranslationStore
    @State private var settingsShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("截图翻译器").font(.title2.bold())
                Spacer()
                Button("设置") { settingsShown = true }
            }
            Button("框选翻译  Ctrl+Shift+T") { NSApp.delegate.flatMap { ($0 as? AppDelegate)?.captureRequested() } }
                .keyboardShortcut("t", modifiers: [.control, .shift])
                .disabled(store.isTranslating)
            Text(store.status).foregroundStyle(store.status == "翻译完成" ? .green : .secondary)
            Text("识别原文").font(.headline)
            TextEditor(text: .constant(store.source)).frame(height: 150).disabled(true)
            Text("译文").font(.headline)
            TextEditor(text: .constant(store.translation)).frame(height: 180).disabled(true)
        }
        .padding(20).frame(width: 720, height: 560)
        .sheet(isPresented: $settingsShown) { SettingsView().environmentObject(store) }
    }
}

private struct SettingsView: View {
    @EnvironmentObject var store: TranslationStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DeepSeek 设置").font(.title2.bold())
            SecureField("DeepSeek API Key", text: $store.apiKey)
            TextField("模型", text: $store.model)
            Picker("目标语言", selection: $store.targetLanguage) {
                Text("中文（简体）").tag("中文（简体）"); Text("English").tag("English")
                Text("日本語").tag("日本語"); Text("한국어").tag("한국어")
            }
            Text("接口：https://api.deepseek.com/chat/completions\n模型默认：deepseek-flash")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(24).frame(width: 460)
    }
}
