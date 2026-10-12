import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: TranslationStore
    @EnvironmentObject var visibilityController: AppVisibilityController
    let capture: () -> Void
    let recognize: () -> Void
    let setHotkeyEnabled: (Bool) -> Void
    @State private var settingsShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            actionPanel
            statusRow
            HStack(spacing: 14) {
                sourceTextCard
                textCard(title: "译文", subtitle: store.translation.isEmpty ? "TRANSLATION" : store.targetLanguage.uppercased(), text: store.translation, color: AppTheme.accent)
            }
            .frame(height: 240)
            learningCard
        }
        .padding(24)
        .frame(width: 860, height: 790)
        .foregroundStyle(AppTheme.cocoa)
        .tint(AppTheme.accent)
        .background(AppTheme.background)
        .sheet(isPresented: $settingsShown) { SettingsView(setHotkeyEnabled: setHotkeyEnabled).environmentObject(store) }
        .onReceive(NotificationCenter.default.publisher(for: .openTranslationSettings)) { _ in
            settingsShown = true
        }
    }

    private var learningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.peach, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("学习笔记").font(.headline)
                    Text("多懂一点，下次就更熟悉一点")
                        .font(.caption).foregroundStyle(AppTheme.secondary)
                }
                Spacer()
                if store.isLoadingLearningNote {
                    ProgressView().controlSize(.small)
                } else if store.learningNote == nil && store.canLearnCurrentText && !store.translation.isEmpty {
                    Button("理解这句话") { store.loadLearningNote() }
                        .buttonStyle(WarmButtonStyle()).tint(AppTheme.accent)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let note = store.learningNote {
                        Text(note.summary).font(.callout)
                        if !note.keyPoints.isEmpty { learningSection("表达要点", note.keyPoints, icon: "text.book.closed") }
                        if !note.words.isEmpty { learningSection("重点词汇", note.words, icon: "character.book.closed") }
                    } else {
                        Text(store.isLoadingLearningNote ? "正在整理这句话…" : "翻译完成后，可以按需理解句意、表达和重点词汇。")
                            .font(.callout).foregroundStyle(AppTheme.secondary)
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(17)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .warmCard(fill: AppTheme.peach.opacity(0.45))
    }

    private func learningSection(_ title: String, _ text: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.secondary)
            Text(text).font(.callout)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            BrandIcon(size: 58)
            VStack(alignment: .leading, spacing: 3) {
                Text("多多翻译").font(.system(size: 25, weight: .bold, design: .rounded))
                Text("把看不懂的，变成熟悉的")
                    .font(.subheadline).foregroundStyle(AppTheme.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(store.isTranslating ? AppTheme.accent : AppTheme.success).frame(width: 7, height: 7)
                Text(store.isTranslating ? "处理中" : "已就绪")
                    .font(.caption.weight(.medium)).foregroundStyle(AppTheme.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Capsule().fill(AppTheme.surface))
            Button { settingsShown = true } label: {
                Label("设置", systemImage: "gearshape")
            }
            .buttonStyle(WarmButtonStyle())
            Button { visibilityController.hideToMenuBar() } label: {
                Image(systemName: "menubar.arrow.up.rectangle")
            }
            .buttonStyle(.borderless)
            .help("隐藏到菜单栏")
        }
    }

    private var actionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("开始翻译").font(.headline)
                    Text("选择一种方式把文字带进工作区").font(.caption).foregroundStyle(AppTheme.secondary)
                }
                Spacer()
                Text("⌘↩︎ 翻译输入内容").font(.caption).foregroundStyle(AppTheme.secondary)
            }
            HStack(spacing: 12) {
                actionButton("框选翻译", detail: store.captureShortcutTitle, icon: "viewfinder", tint: AppTheme.accent) {
                    capture()
                }
                actionButton("翻译剪贴板", detail: store.clipboardShortcutTitle, icon: "doc.on.clipboard", tint: AppTheme.caramel) { store.translateClipboard() }
                actionButton("仅 OCR", detail: "自动复制", icon: "text.viewfinder", tint: AppTheme.cocoa) {
                    recognize()
                }
            }
        }
        .padding(17)
        .warmCard()
        .disabled(store.isTranslating)
    }

    private func actionButton(_ title: String, detail: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.cocoa)
                    Text(detail).font(.caption2).foregroundStyle(AppTheme.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
        }
        .buttonStyle(WarmActionStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusRow: some View {
        HStack(spacing: 9) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
            Text(store.status).font(.callout).foregroundStyle(AppTheme.secondary).lineLimit(2)
            Spacer()
            if store.isTranslating {
                ProgressView().controlSize(.small)
                Button("取消") { store.cancelTranslation() }.buttonStyle(WarmButtonStyle())
            } else if !store.source.isEmpty && store.state == .failed {
                Button("重试") { store.retryLastTranslation() }.buttonStyle(WarmButtonStyle())
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
    }

    private var statusIcon: String {
        if store.isTranslating { return "arrow.triangle.2.circlepath" }
        if store.state == .succeeded { return "checkmark.circle.fill" }
        if store.state == .failed { return "exclamationmark.triangle.fill" }
        return "info.circle.fill"
    }

    private var statusColor: Color {
        if store.isTranslating { return AppTheme.accent }
        if store.state == .succeeded { return AppTheme.success }
        if store.state == .failed { return AppTheme.accent }
        return .secondary
    }

    private func textCard(title: String, subtitle: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.headline)
                Spacer()
                Text(subtitle).font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.secondary)
            }
            ZStack(alignment: .topLeading) {
                ScrollView {
                    Text(text.isEmpty ? "" : text)
                        .font(.system(size: 16))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                }
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.input))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.border.opacity(0.7), lineWidth: 1))
                if text.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Image(systemName: title == "识别原文" ? "text.viewfinder" : "character.bubble")
                            .foregroundStyle(color.opacity(0.65))
                        Text(title == "识别原文" ? "框选区域或输入文字后，原文会显示在这里" : "翻译结果会显示在这里")
                            .font(.callout).foregroundStyle(AppTheme.secondary)
                    }
                    .padding(18)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .warmCard()
    }

    private var sourceTextCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(AppTheme.caramel).frame(width: 8, height: 8)
                Text("识别原文").font(.headline)
                Spacer()
                Text("SOURCE").font(.caption2.weight(.semibold)).foregroundStyle(AppTheme.secondary)
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $store.source)
                    .font(.system(size: 16))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.input))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.border.opacity(0.7), lineWidth: 1))
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        store.translateInput(store.source)
                        return .handled
                    }
                if store.source.isEmpty {
                    Text("框选区域后，或直接在这里输入原文")
                        .font(.callout).foregroundStyle(AppTheme.secondary).padding(18)
                        .allowsHitTesting(false)
                }
            }
            Text("可直接修改识别结果；按 ⌘↩︎ 翻译")
                .font(.caption).foregroundStyle(AppTheme.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .warmCard()
    }
}

private struct SettingsView: View {
    let setHotkeyEnabled: (Bool) -> Void
    @EnvironmentObject var store: TranslationStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: SettingsField?

    private enum SettingsField { case apiKey, model }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BrandIcon(size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("让多多更懂你").font(.title2.bold())
                    Text("服务、语言与快捷键").font(.caption).foregroundStyle(AppTheme.secondary)
                }
                Spacer()
            }
            .padding(24)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    settingsSection("翻译服务", icon: "bubble.left.and.bubble.right") {
                        Picker("服务商", selection: $store.providerRaw) {
                            ForEach(APIProvider.allCases) { provider in
                                Text(provider.title).tag(provider.rawValue)
                            }
                        }
                        .onChange(of: store.providerRaw) { _, rawValue in
                            store.provider = APIProvider(rawValue: rawValue) ?? .deepSeek
                        }
                        SecureField("\(store.provider.title) API Key", text: $store.apiKey)
                            .focused($focusedField, equals: .apiKey)
                        if let error = store.apiKeyStorageError {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                        TextField("模型", text: $store.model)
                            .focused($focusedField, equals: .model)
                        HStack {
                            Text("密钥保存在 macOS 钥匙串中")
                                .font(.caption).foregroundStyle(AppTheme.secondary)
                            Spacer()
                            Button("保存密钥") { store.saveAPIKey() }.buttonStyle(WarmButtonStyle())
                        }
                    }
                    settingsSection("语言偏好", icon: "character.bubble") {
                        Picker("识别语言", selection: $store.recognitionLanguage) {
                            Text("自动识别（中英日韩）").tag("自动识别")
                            Text("中文").tag("中文")
                            Text("English").tag("English")
                            Text("日本語").tag("日本語")
                            Text("한국어").tag("한국어")
                        }
                        Picker("目标语言", selection: $store.targetLanguage) {
                            Text("中文（简体）").tag("中文（简体）")
                            Text("English").tag("English")
                            Text("日本語").tag("日本語")
                            Text("한국어").tag("한국어")
                        }
                    }
                    settingsSection("快捷操作", icon: "keyboard") {
                        shortcutRow("框选翻译", title: store.captureShortcutTitle) { keyCode, modifiers in
                            store.setCaptureShortcut(keyCode: keyCode, modifiers: modifiers)
                        }
                        shortcutRow("翻译剪贴板", title: store.clipboardShortcutTitle) { keyCode, modifiers in
                            store.setClipboardShortcut(keyCode: keyCode, modifiers: modifiers)
                        }
                    }
                    DisclosureGroup("连接信息与日志") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("接口：\(store.provider.baseURL.absoluteString)/chat/completions\n默认模型：\(store.provider.defaultModel)")
                                .font(.caption).foregroundStyle(AppTheme.secondary)
                            HStack {
                                Text(store.logFileURL.path)
                                    .font(.caption2).foregroundStyle(AppTheme.secondary)
                                    .textSelection(.enabled)
                                Spacer()
                                Button("打开日志") { store.openLogFile() }
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(16)
                    .warmCard()
                }
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
            }
            HStack {
                Text("按你的习惯，轻松翻译")
                    .font(.caption).foregroundStyle(AppTheme.secondary)
                Spacer()
                Button("完成") { store.saveAPIKey(); dismiss() }
                    .buttonStyle(WarmButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .background(AppTheme.surface)
        }
        .frame(width: 540, height: 630)
        .foregroundStyle(AppTheme.cocoa)
        .tint(AppTheme.accent)
        .background(AppTheme.background)
        .onAppear {
            setHotkeyEnabled(false)
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async { focusedField = .apiKey }
        }
        .onDisappear { setHotkeyEnabled(true) }
    }

    private func settingsSection<Content: View>(_ title: String, icon: String,
                                                @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(AppTheme.accent)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard()
    }

    private func shortcutRow(_ label: String, title: String,
                             onChange: @escaping (UInt32, UInt32) -> Void) -> some View {
        HStack {
            Text(label).font(.callout)
            Spacer()
            ShortcutRecorder(title: title, onRecord: onChange)
                .frame(width: 180, height: 28)
        }
    }
}
