import AppKit
import Carbon.HIToolbox
import Vision
import SwiftUI

extension Notification.Name {
    static let captureHotkeyChanged = Notification.Name("captureHotkeyChanged")
    static let clipboardHotkeyChanged = Notification.Name("clipboardHotkeyChanged")
    static let openTranslationSettings = Notification.Name("openTranslationSettings")
    static let translationCompleted = Notification.Name("translationCompleted")
    static let ocrCompleted = Notification.Name("ocrCompleted")
}

enum TranslationState: Equatable {
    case idle
    case recognizing
    case translating
    case succeeded
    case failed
    case cancelled
}

struct OCRDisplayResult {
    let text: String
}

struct LearningNote: Equatable {
    let summary: String
    let keyPoints: String
    let words: String
}

enum APIProvider: String, CaseIterable, Identifiable {
    case deepSeek = "deepseek"
    case openAI = "openai"

    var id: String { rawValue }
    var title: String { self == .openAI ? "OpenAI" : "DeepSeek" }
    var defaultModel: String { self == .openAI ? "gpt-4o-mini" : "deepseek-flash" }
    var baseURL: URL { URL(string: self == .openAI ? "https://api.openai.com/v1" : "https://api.deepseek.com")! }
}

/// 保存界面状态，并串联截图、Vision OCR 和可切换的翻译服务。
@MainActor
final class TranslationStore: ObservableObject {
    @Published var source = ""
    @Published var translation = ""
    @Published var learningNote: LearningNote?
    @Published var isLoadingLearningNote = false
    @Published var status = "准备就绪。使用下方按钮或菜单栏快捷键框选翻译。"
    @Published var isTranslating = false
    @Published var apiKey: String
    @Published var apiKeyStorageError: String?
    @Published private(set) var state: TranslationState = .idle

    @AppStorage("apiProvider") var providerRaw = APIProvider.deepSeek.rawValue
    @AppStorage("deepseekModel") var model = "deepseek-flash"
    @AppStorage("targetLanguage") var targetLanguage = "中文（简体）"
    @AppStorage("recognitionLanguage") var recognitionLanguage = "自动识别"
    @AppStorage("captureHotKeyCode") private var captureHotKeyCode = Int(kVK_ANSI_T)
    @AppStorage("captureHotKeyModifiers") private var captureHotKeyModifiers = Int(controlKey | shiftKey)
    @AppStorage("clipboardHotKeyCode") private var clipboardHotKeyCode = Int(kVK_ANSI_V)
    @AppStorage("clipboardHotKeyModifiers") private var clipboardHotKeyModifiers = Int(controlKey | shiftKey)

    init() {
        AppLogger.shared.info("应用启动")
        let provider = APIProvider(rawValue: UserDefaults.standard.string(forKey: "apiProvider") ?? "deepseek") ?? .deepSeek
        // 首次升级时，把旧版本 UserDefaults 中的明文 Key 一次性迁移到钥匙串。
        let legacyKey = UserDefaults.standard.string(forKey: "deepseekAPIKey") ?? ""
        do {
            if let storedKey = try KeychainStore.loadAPIKey(provider: provider) {
                apiKey = storedKey
                apiKeyStorageError = nil
            } else if provider == .deepSeek && !legacyKey.isEmpty {
                try KeychainStore.saveAPIKey(legacyKey, provider: .deepSeek)
                apiKey = legacyKey
                apiKeyStorageError = nil
                UserDefaults.standard.removeObject(forKey: "deepseekAPIKey")
            } else {
                apiKey = ""
                apiKeyStorageError = nil
            }
        } catch {
            apiKey = legacyKey
            apiKeyStorageError = error.localizedDescription
        }
    }

    var provider: APIProvider {
        get { APIProvider(rawValue: providerRaw) ?? .deepSeek }
        set {
            providerRaw = newValue.rawValue
            do { apiKey = try KeychainStore.loadAPIKey(provider: newValue) ?? "" }
            catch { apiKey = ""; apiKeyStorageError = error.localizedDescription }
            if model == APIProvider.deepSeek.defaultModel || model == APIProvider.openAI.defaultModel {
                model = newValue.defaultModel
            }
        }
    }

    var captureShortcutTitle: String {
        ShortcutFormatter.title(keyCode: UInt32(captureHotKeyCode), modifiers: UInt32(captureHotKeyModifiers))
    }

    var captureShortcut: (keyCode: UInt32, modifiers: UInt32) {
        (UInt32(captureHotKeyCode), UInt32(captureHotKeyModifiers))
    }

    var clipboardShortcutTitle: String {
        ShortcutFormatter.title(keyCode: UInt32(clipboardHotKeyCode), modifiers: UInt32(clipboardHotKeyModifiers))
    }

    var clipboardShortcut: (keyCode: UInt32, modifiers: UInt32) {
        (UInt32(clipboardHotKeyCode), UInt32(clipboardHotKeyModifiers))
    }

    func saveAPIKey() {
        do {
            try KeychainStore.saveAPIKey(apiKey, provider: provider)
            apiKeyStorageError = nil
            AppLogger.shared.info("API Key 已保存（长度：\(apiKey.count)）")
        } catch {
            apiKeyStorageError = error.localizedDescription
            AppLogger.shared.error("保存 API Key 失败：\(error.localizedDescription)")
        }
    }

    var logFileURL: URL { AppLogger.shared.fileURL }

    func openLogFile() {
        AppLogger.shared.openInFinder()
    }

    func setCaptureShortcut(keyCode: UInt32, modifiers: UInt32) {
        captureHotKeyCode = Int(keyCode)
        captureHotKeyModifiers = Int(modifiers)
        objectWillChange.send()
        NotificationCenter.default.post(name: .captureHotkeyChanged, object: nil)
    }

    func setClipboardShortcut(keyCode: UInt32, modifiers: UInt32) {
        clipboardHotKeyCode = Int(keyCode)
        clipboardHotKeyModifiers = Int(modifiers)
        objectWillChange.send()
        NotificationCenter.default.post(name: .clipboardHotkeyChanged, object: nil)
    }

    func translate(selection: NSRect, on screen: NSScreen) {
        guard let image = screenshot(selection: selection, screen: screen) else { fail("截图失败，请在系统设置中允许屏幕录制。"); return }
        source = ""
        translation = ""
        learningNote = nil
        beginRequest(.recognizing)
        status = "正在识别文字…"
        let languages = recognitionLanguages()
        let requestID = activeRequestID
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await Task.detached(priority: .userInitiated) {
                    try Self.recognize(image: image, languages: languages)
                }.value
                guard !Task.isCancelled, self.activeRequestID == requestID else { return }
                guard !text.isEmpty else {
                    AppLogger.shared.error("OCR 失败：Vision 未识别到文字（框选翻译流程）")
                    throw TranslationError.message("没有识别到文字。")
                }
                self.source = text
                guard !self.apiKey.isEmpty else {
                    self.status = "已识别原文；请先在设置中填写 \(self.provider.title) API Key 以翻译。"
                    self.isTranslating = false
                    self.state = .idle
                    return
                }
                guard self.activeRequestID == requestID else { return }
                self.state = .translating
                self.status = "正在翻译…"
                try await self.translateRecognizedText(text, requestID: requestID)
            } catch is CancellationError {
                guard self.activeRequestID == requestID else { return }
                self.cancelled()
            } catch {
                guard self.activeRequestID == requestID else { return }
                self.fail(error.localizedDescription)
            }
        }
    }

    /// 只执行 OCR，不访问翻译服务，并自动把识别结果复制到剪贴板。
    func recognize(selection: NSRect, on screen: NSScreen) {
        guard !isTranslating else { return }
        guard let image = screenshot(selection: selection, screen: screen) else {
            fail("截图失败，请在系统设置中允许屏幕录制。")
            return
        }
        source = ""
        translation = ""
        learningNote = nil
        beginRequest(.recognizing)
        status = "正在识别文字…"
        let languages = recognitionLanguages()
        let requestID = activeRequestID
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await Task.detached(priority: .userInitiated) {
                    try Self.recognize(image: image, languages: languages)
                }.value
                guard !Task.isCancelled, self.activeRequestID == requestID else { return }
                guard !text.isEmpty else {
                    AppLogger.shared.error("OCR 失败：Vision 未识别到文字（仅 OCR 流程）")
                    throw TranslationError.message("没有识别到文字。")
                }
                self.source = text
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                self.status = "OCR 完成，结果已复制"
                self.isTranslating = false
                self.state = .succeeded
                NotificationCenter.default.post(name: .ocrCompleted, object: OCRDisplayResult(text: text))
            } catch is CancellationError {
                guard self.activeRequestID == requestID else { return }
                self.cancelled()
            } catch {
                guard self.activeRequestID == requestID else { return }
                self.fail(error.localizedDescription)
            }
        }
    }

    func translateInput(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { status = "请输入要翻译的文字。"; return }
        guard !isTranslating else { return }
        beginTextTranslation(value, status: "正在翻译输入文字…")
    }

    private func beginTextTranslation(_ text: String, status: String) {
        source = text
        translation = ""
        learningNote = nil
        guard !apiKey.isEmpty else {
            self.status = "已读取原文；请先在设置中填写 \(provider.title) API Key。"
            state = .idle
            return
        }
        beginRequest(.translating)
        self.status = status
        let requestID = activeRequestID
        activeTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.translateRecognizedText(text, requestID: requestID) }
            catch is CancellationError { guard self.activeRequestID == requestID else { return }; self.cancelled() }
            catch { guard self.activeRequestID == requestID else { return }; self.fail(error.localizedDescription) }
        }
    }

    /// 读取当前剪贴板中的纯文本，并复用截图翻译的网络流程。
    func translateClipboard() {
        guard !isTranslating else { return }
        guard let clipboardText = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !clipboardText.isEmpty else {
            status = "剪贴板中没有可翻译的文字。"
            return
        }

        source = clipboardText
        translation = ""
        learningNote = nil

        guard !apiKey.isEmpty else {
            status = "已读取剪贴板文字；请先在设置中填写 \(provider.title) API Key。"
            state = .idle
            return
        }

        beginRequest(.translating)
        status = "正在翻译剪贴板文字…"
        let requestID = activeRequestID
        activeTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.translateRecognizedText(clipboardText, requestID: requestID) }
            catch is CancellationError { guard self.activeRequestID == requestID else { return }; self.cancelled() }
            catch { guard self.activeRequestID == requestID else { return }; self.fail(error.localizedDescription) }
        }
    }

    func cancelTranslation() {
        activeTask?.cancel()
        activeTask = nil
        activeRequestID = UUID()
        cancelled()
    }

    func retryLastTranslation() {
        guard !isTranslating, let text = lastRequestText, !apiKey.isEmpty else { return }
        beginRequest(.translating)
        status = "正在重试…"
        let requestID = activeRequestID
        activeTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.translateRecognizedText(text, requestID: requestID) }
            catch is CancellationError { guard self.activeRequestID == requestID else { return }; self.cancelled() }
            catch { guard self.activeRequestID == requestID else { return }; self.fail(error.localizedDescription) }
        }
    }

    private var activeTask: Task<Void, Never>?
    private var lastRequestText: String?
    private var activeRequestID = UUID()

    private func beginRequest(_ newState: TranslationState) {
        lastRequestText = nil
        activeRequestID = UUID()
        state = newState
        isTranslating = newState == .recognizing || newState == .translating
    }

    private func cancelled() {
        state = .cancelled
        status = "请求已取消"
        isTranslating = false
        AppLogger.shared.info("翻译流程已取消")
    }

    private func fail(_ message: String) {
        state = .failed
        status = message
        isTranslating = false
        AppLogger.shared.error("翻译流程失败：\(message)")
    }

    private func translateRecognizedText(_ text: String, requestID: UUID) async throws {
        lastRequestText = text
        AppLogger.shared.info("开始翻译：原文长度 \(text.count)，模型 \(model)，目标语言 \(targetLanguage)")
        let result = try await Self.callChatCompletion(text: text, apiKey: apiKey, model: model, targetLanguage: targetLanguage, provider: provider)
        try Task.checkCancellation()
        guard activeRequestID == requestID else { return }
        translation = result
        status = "翻译完成"
        AppLogger.shared.info("翻译完成：译文长度 \(result.count)")
        isTranslating = false
        state = .succeeded
        NotificationCenter.default.post(name: .translationCompleted,
                                        object: TranslationDisplayResult(source: text, translation: result))
    }

    var canLearnCurrentText: Bool {
        let words = source.split { $0 == " " || $0 == "\n" || $0 == "\t" }
        let compact = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let basic = ["hello", "hi", "thanks", "thank you", "okay", "ok", "yes", "no", "好的", "谢谢", "你好"]
        return compact.count >= 8 && words.count >= 4 && !basic.contains(compact.lowercased())
    }

    func loadLearningNote() {
        guard canLearnCurrentText, !isLoadingLearningNote, !translation.isEmpty else { return }
        guard !apiKey.isEmpty else { status = "请先在设置中填写 \(provider.title) API Key。"; return }
        isLoadingLearningNote = true
        let text = source
        Task { [weak self] in
            guard let self else { return }
            defer { self.isLoadingLearningNote = false }
            do {
                self.learningNote = try await Self.callLearning(text: text, translation: translation, apiKey: self.apiKey, model: self.model, provider: self.provider)
            }
            catch { self.status = error.localizedDescription }
        }
    }

    private func screenshot(selection: NSRect, screen: NSScreen) -> CGImage? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let image = CGDisplayCreateImage(CGDirectDisplayID(number.uint32Value)) else {
            AppLogger.shared.error("截图失败：无法创建显示器图像，屏幕录制权限或显示器 ID 无效")
            return nil
        }
        // SelectionOverlay 的 contentView 使用屏幕本地坐标（左下角为 0,0）。
        // 不要再次减去 NSScreen 的全局 origin，否则副屏上的选区会整体偏移。
        guard let crop = ScreenshotGeometry.cropRect(
            selection: selection,
            screenSize: screen.frame.size,
            imageSize: CGSize(width: image.width, height: image.height)
        ) else {
            AppLogger.shared.error("截图失败：选区裁剪为空，screen=\(screen.frame), selection=\(selection)")
            return nil
        }
        guard let result = image.cropping(to: crop) else {
            AppLogger.shared.error("截图失败：CGImage 裁剪失败，crop=\(crop)")
            return nil
        }
        AppLogger.shared.info("截图完成：像素尺寸 \(result.width)x\(result.height)")
        return result
    }

    private nonisolated static func recognize(image: CGImage, languages: [String]) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        return formatRecognizedText(request.results ?? [])
    }

    /// Vision 返回的 observation 顺序未定义。先按纵向重叠分组为行，再按列和行排序，
    /// 保留列布局与段落间距；每行中的候选文字按 x 坐标排列。
    private nonisolated static func formatRecognizedText(_ observations: [VNRecognizedTextObservation]) -> String {
        struct Item { let text: String; let box: CGRect }
        let items = observations.compactMap { observation -> Item? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return Item(text: text, box: observation.boundingBox)
        }
        guard !items.isEmpty else { return "" }
        var lines: [[Item]] = []
        for item in items.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let index = lines.firstIndex(where: { line in
                let minY = line.map { $0.box.minY }.min()!
                let maxY = line.map { $0.box.maxY }.max()!
                let overlap = min(maxY, item.box.maxY) - max(minY, item.box.minY)
                return overlap > min(item.box.height, maxY - minY) * 0.35 || abs(item.box.midY - (minY + maxY) / 2) < max(item.box.height, maxY - minY) * 0.45
            }) {
                lines[index].append(item)
            } else { lines.append([item]) }
        }
        lines = lines.map { line in
            line.sorted { left, right in left.box.minX < right.box.minX }
        }
        lines.sort { upper, lower in
            let upperY = upper.map { $0.box.midY }.reduce(0, +) / CGFloat(upper.count)
            let lowerY = lower.map { $0.box.midY }.reduce(0, +) / CGFloat(lower.count)
            return upperY > lowerY
        }

        // 将明显分离的 x 区域视为独立栏，栏内仍按从上到下读取。
        let medianHeight = items.map(\.box.height).sorted()[items.count / 2]
        let columnGap = max(0.06, medianHeight * 2.5)
        var columns: [[ [Item] ]] = []
        for line in lines {
            let minX = line.first!.box.minX
            if let index = columns.firstIndex(where: { column in
                let right = column.flatMap { $0 }.map { $0.box.maxX }.max() ?? 0
                return minX <= right + columnGap
            }) { columns[index].append(line) } else { columns.append([line]) }
        }
        columns.sort { ($0.flatMap { $0 }.map { $0.box.minX }.min() ?? 0) < ($1.flatMap { $0 }.map { $0.box.minX }.min() ?? 0) }
        var output: [String] = []
        for column in columns {
            let ordered = column.sorted { ($0.first?.box.midY ?? 0) > ($1.first?.box.midY ?? 0) }
            for (index, line) in ordered.enumerated() {
                if index > 0,
                   let previous = ordered[index - 1].first,
                   let current = line.first,
                   previous.box.minY - current.box.maxY > medianHeight * 1.8 {
                    output.append("")
                }
                output.append(line.map(\.text).joined(separator: " "))
            }
        }
        return output.joined(separator: "\n")
    }

    private func recognitionLanguages() -> [String] {
        switch recognitionLanguage {
        case "中文": return ["zh-Hans"]
        case "English": return ["en-US"]
        case "日本語": return ["ja-JP"]
        case "한국어": return ["ko-KR"]
        default: return ["en-US", "zh-Hans", "ja-JP", "ko-KR"]
        }
    }

    private nonisolated static func callChatCompletion(text: String, apiKey: String, model: String, targetLanguage: String, provider: APIProvider) async throws -> String {
        let requestID = UUID().uuidString.prefix(8)
        let startedAt = Date()
        let body: [String: Any] = ["model": model, "temperature": 0.2, "messages": [
            ["role": "system", "content": "你是专业翻译。准确、完整、自然地翻译用户提供的内容，不得删减、概括、改写或补充原文信息。只输出译文，不要解释、前言或引号。保留原有段落、换行、项目符号、编号、专有名词、变量名、代码和占位符。根据上下文选择准确含义。"],
            ["role": "user", "content": "请将下面的内容翻译成\(targetLanguage)：\n\n原文：\n\(text)"]
        ]]
        var request = URLRequest(url: provider.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"; request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        AppLogger.shared.info("\(provider.title) 请求开始 [\(requestID)]：模型 \(model)，原文长度 \(text.count)，超时 60 秒")
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch let error as URLError where error.code == .timedOut {
            AppLogger.shared.error("\(provider.title) 请求超时 [\(requestID)]：耗时 \(Self.elapsed(since: startedAt))")
            throw TranslationError.message("网络请求超时，请重试（详见日志）")
        }
        catch let error as URLError where error.code == .cancelled {
            AppLogger.shared.info("\(provider.title) 请求已取消 [\(requestID)]：耗时 \(Self.elapsed(since: startedAt))")
            throw CancellationError()
        }
        catch {
            AppLogger.shared.error("\(provider.title) 网络请求失败 [\(requestID)]：\(error.localizedDescription)，耗时 \(Self.elapsed(since: startedAt))")
            throw TranslationError.message("网络请求失败：\(error.localizedDescription)（详见日志）")
        }
        guard let http = response as? HTTPURLResponse else {
            AppLogger.shared.error("\(provider.title) 响应无效 [\(requestID)]：不是 HTTP 响应")
            throw TranslationError.message("服务器响应无效（详见日志）")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let serverMessage = (json?["error"] as? [String: Any])?["message"] as? String
        AppLogger.shared.info("\(provider.title) 响应收到 [\(requestID)]：HTTP \(http.statusCode)，\(data.count) bytes，耗时 \(Self.elapsed(since: startedAt))")
        guard (200..<300).contains(http.statusCode) else {
            AppLogger.shared.error("\(provider.title) 返回错误 [\(requestID)]：HTTP \(http.statusCode)\(serverMessage.map { "，\($0)" } ?? "")")
            switch http.statusCode {
            case 401: throw TranslationError.message("API Key 无效，请检查后重试（详见日志）")
            case 402, 403: throw TranslationError.message("账户或额度不足，请检查 \(provider.title) 账户（详见日志）")
            case 429: throw TranslationError.message("请求过于频繁，请稍后重试（详见日志）")
            case 500...599: throw TranslationError.message("翻译服务暂时不可用，请重试（详见日志）")
            default: throw TranslationError.message(serverMessage ?? "请求失败（HTTP \(http.statusCode)，详见日志）")
            }
        }
        if let serverMessage {
            AppLogger.shared.error("\(provider.title) 成功状态中包含错误 [\(requestID)]：\(serverMessage)")
            throw TranslationError.message(serverMessage)
        }
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            AppLogger.shared.error("\(provider.title) 返回格式异常 [\(requestID)]：未找到 choices[0].message.content")
            throw TranslationError.message("\(provider.title) 返回格式异常（详见日志）")
        }
        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else {
            AppLogger.shared.error("\(provider.title) 返回空译文 [\(requestID)]")
            throw TranslationError.message("\(provider.title) 返回了空译文（详见日志）")
        }
        return result
    }

    private nonisolated static func elapsed(since start: Date) -> String {
        String(format: "%.2f 秒", Date().timeIntervalSince(start))
    }

    private nonisolated static func callLearning(text: String, translation: String, apiKey: String, model: String, provider: APIProvider) async throws -> LearningNote {
        let body: [String: Any] = ["model": model, "temperature": 0.3, "messages": [
            ["role": "system", "content": "你是英语学习助手。请根据原文和译文，提炼真正有帮助的学习内容。只返回严格 JSON，不要 Markdown、不要代码块、不要前言、不要结语、不要输出字段名以外的提示语。JSON 格式固定为：{\"summary\":\"用自然中文简要说明句意，不要写‘句意：’\",\"keyPoints\":\"只写实际的语法或表达规律，不要写‘表达要点：’、‘提示：’或分析过程\",\"words\":\"只列真正值得学习的词或短语，每行一个，格式为‘词 — 中文含义’，不要写‘重点词汇：’或格式说明\"}。如果某一项没有内容，返回空字符串。"],
            ["role": "user", "content": "原文：\n\(text)\n\n译文：\n\(translation)"]
        ]]
        var request = URLRequest(url: provider.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"; request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { throw TranslationError.message("学习笔记生成失败") }
        return try LearningNoteParser.parse(content)
    }
}

enum ShortcutFormatter {
    static func title(keyCode: UInt32, modifiers: UInt32) -> String {
        var title = ""
        if modifiers & UInt32(cmdKey) != 0 { title += "⌘" }
        if modifiers & UInt32(optionKey) != 0 { title += "⌥" }
        if modifiers & UInt32(controlKey) != 0 { title += "⌃" }
        if modifiers & UInt32(shiftKey) != 0 { title += "⇧" }
        return title + keyTitle(for: keyCode)
    }

    private static func keyTitle(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9"
        ]
        return names[keyCode] ?? "键码 \(keyCode)"
    }
}

private enum TranslationError: LocalizedError { case message(String); var errorDescription: String? { if case let .message(value) = self { return value }; return nil } }
