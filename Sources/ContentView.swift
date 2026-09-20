import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: TranslationStore
    @EnvironmentObject var visibilityController: AppVisibilityController
    @State private var settingsShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            actionPanel
            statusRow
            HStack(spacing: 14) {
                sourceTextCard
                textCard(title: "译文", subtitle: store.translation.isEmpty ? "TRANSLATION" : store.targetLanguage.uppercased(), text: store.translation, color: .purple)
            }
            .frame(height: 250)
            learningCard
        }
        .padding(24)
        .frame(width: 820, height: 760)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $settingsShown) { SettingsView().environmentObject(store) }
        .onReceive(NotificationCenter.default.publisher(for: .openTranslationSettings)) { _ in
            settingsShown = true
        }
    }

    private var learningCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                Text("学习笔记").font(.headline)
                Spacer()
                Text(store.learningNote == nil ? "翻译完成后自动生成" : "重点理解").font(.caption).foregroundStyle(.secondary)
            }
            if let note = store.learningNote {
                VStack(alignment: .leading, spacing: 8) {
                    Text(note.summary).font(.callout)
                    if !note.keyPoints.isEmpty { learningSection("表达要点", note.keyPoints, icon: "text.book.closed") }
                    if !note.words.isEmpty { learningSection("重点词汇", note.words, icon: "character.book.closed") }
                }
                .textSelection(.enabled)
            } else {
                Text("这里会用更容易记住的方式解释句意、语法和重点词汇。")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.yellow.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.yellow.opacity(0.25), lineWidth: 1))
    }

    private func learningSection(_ title: String, _ text: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(text).font(.callout)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "character.book.closed.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("截图翻译器").font(.title2.bold())
                Text("快速识别屏幕文字，翻译成你需要的语言")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button { settingsShown = true } label: {
                Label("设置", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            Button { visibilityController.hideToMenuBar() } label: {
                Image(systemName: "menubar.arrow.up.rectangle")
            }
            .buttonStyle(.borderless)
            .help("隐藏到菜单栏")
        }
    }

    private var actionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("开始翻译").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                actionButton("框选翻译", detail: store.captureShortcutTitle, icon: "viewfinder", tint: .indigo) {
                    NSApp.delegate.flatMap { ($0 as? AppDelegate)?.captureRequested() }
                }
                actionButton("翻译剪贴板", detail: store.clipboardShortcutTitle, icon: "doc.on.clipboard", tint: .teal) { store.translateClipboard() }
                actionButton("翻译选中文字", detail: "保留当前选区", icon: "text.quote", tint: .orange) {
                    NSApp.delegate.flatMap { ($0 as? AppDelegate)?.translateSelectedText() }
                }
                actionButton("仅 OCR", detail: "自动复制", icon: "text.viewfinder", tint: .blue) {
                    NSApp.delegate.flatMap { ($0 as? AppDelegate)?.captureRequested(mode: .ocr) }
                }
            }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary, lineWidth: 1))
        .disabled(store.isTranslating)
    }

    private func actionButton(_ title: String, detail: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(tint)
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .frame(width: 148, alignment: .leading)
    }

    private var statusRow: some View {
        HStack(spacing: 9) {
            Image(systemName: store.isTranslating ? "arrow.triangle.2.circlepath" : (store.state == .succeeded ? "checkmark.circle.fill" : (store.state == .failed ? "exclamationmark.triangle.fill" : "info.circle.fill")))
                .foregroundStyle(store.state == .succeeded ? .green : (store.state == .failed ? .orange : .secondary))
            Text(store.status).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            if store.isTranslating {
                ProgressView().controlSize(.small)
                Button("取消") { store.cancelTranslation() }.buttonStyle(.bordered)
            } else if !store.source.isEmpty && store.state == .failed {
                Button("重试") { store.retryLastTranslation() }.buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 4)
    }

    private func textCard(title: String, subtitle: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.headline)
                Spacer()
                Text(subtitle).font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
            ZStack(alignment: .topLeading) {
                ScrollView {
                    Text(text.isEmpty ? "" : text)
                        .font(.system(size: 16))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                }
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 1))
                if text.isEmpty {
                    Text(title == "识别原文" ? "框选区域或输入文字后，原文会显示在这里" : "翻译结果会显示在这里")
                        .font(.callout).foregroundStyle(.tertiary).padding(18)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sourceTextCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(.blue).frame(width: 8, height: 8)
                Text("识别原文").font(.headline)
                Spacer()
                Text("SOURCE").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $store.source)
                    .font(.system(size: 16))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 1))
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        store.translateInput(store.source)
                        return .handled
                    }
                if store.source.isEmpty {
                    Text("框选区域后，或直接在这里输入原文")
                        .font(.callout).foregroundStyle(.tertiary).padding(18)
                        .allowsHitTesting(false)
                }
            }
            Text("可直接修改识别结果；按 ⌘↩︎ 翻译")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                Picker("识别语言", selection: $store.recognitionLanguage) {
                    Text("自动识别（中英日韩）").tag("自动识别")
                    Text("中文").tag("中文")
                    Text("English").tag("English")
                    Text("日本語").tag("日本語")
                    Text("한국어").tag("한국어")
                }
                Button("保存 API Key") { store.saveAPIKey() }
            }
            HStack {
                Text("截图快捷键")
                Spacer()
                ShortcutRecorder(title: store.captureShortcutTitle) { keyCode, modifiers in
                    store.setCaptureShortcut(keyCode: keyCode, modifiers: modifiers)
                }
                .frame(width: 180, height: 28)
            }
            HStack {
                Text("翻译剪贴板快捷键")
                Spacer()
                ShortcutRecorder(title: store.clipboardShortcutTitle) { keyCode, modifiers in
                    store.setClipboardShortcut(keyCode: keyCode, modifiers: modifiers)
                }
                .frame(width: 180, height: 28)
            }
            Picker("目标语言", selection: $store.targetLanguage) {
                Text("中文（简体）").tag("中文（简体）"); Text("English").tag("English")
                Text("日本語").tag("日本語"); Text("한국어").tag("한국어")
            }
            Text("接口：https://api.deepseek.com/chat/completions\n模型默认：deepseek-flash")
                .font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("请求日志").font(.subheadline.weight(.medium))
                    Text(store.logFileURL.path)
                        .font(.caption2).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("打开日志") { store.openLogFile() }
            }
            HStack { Spacer(); Button("完成") { store.saveAPIKey(); dismiss() }.keyboardShortcut(.defaultAction) }
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
