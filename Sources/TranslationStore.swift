import AppKit
import Carbon.HIToolbox
import Vision
import SwiftUI

extension Notification.Name {
    static let captureHotkeyChanged = Notification.Name("captureHotkeyChanged")
    static let openTranslationSettings = Notification.Name("openTranslationSettings")
    static let translationCompleted = Notification.Name("translationCompleted")
}

/// 保存界面状态，并串联截图、Vision OCR 和 DeepSeek 翻译三个阶段。
final class TranslationStore: ObservableObject {
    @Published var source = ""
    @Published var translation = ""
    @Published var status = "准备就绪。使用下方按钮或菜单栏快捷键框选翻译。"
    @Published var isTranslating = false
    @Published var apiKey: String {
        didSet {
            guard apiKey != oldValue else { return }
            do {
                try KeychainStore.saveAPIKey(apiKey)
                apiKeyStorageError = nil
            } catch {
                apiKeyStorageError = error.localizedDescription
            }
        }
    }
    @Published var apiKeyStorageError: String?

    @AppStorage("deepseekModel") var model = "deepseek-flash"
    @AppStorage("targetLanguage") var targetLanguage = "中文（简体）"
    @AppStorage("captureHotKeyCode") private var captureHotKeyCode = Int(kVK_ANSI_T)
    @AppStorage("captureHotKeyModifiers") private var captureHotKeyModifiers = Int(controlKey | shiftKey)

    init() {
        // 首次升级时，把旧版本 UserDefaults 中的明文 Key 一次性迁移到钥匙串。
        let legacyKey = UserDefaults.standard.string(forKey: "deepseekAPIKey") ?? ""
        do {
            if let storedKey = try KeychainStore.loadAPIKey() {
                apiKey = storedKey
                apiKeyStorageError = nil
            } else if !legacyKey.isEmpty {
                try KeychainStore.saveAPIKey(legacyKey)
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

    var captureShortcutTitle: String {
        ShortcutFormatter.title(keyCode: UInt32(captureHotKeyCode), modifiers: UInt32(captureHotKeyModifiers))
    }

    var captureShortcut: (keyCode: UInt32, modifiers: UInt32) {
        (UInt32(captureHotKeyCode), UInt32(captureHotKeyModifiers))
    }

    func setCaptureShortcut(keyCode: UInt32, modifiers: UInt32) {
        captureHotKeyCode = Int(keyCode)
        captureHotKeyModifiers = Int(modifiers)
        objectWillChange.send()
        NotificationCenter.default.post(name: .captureHotkeyChanged, object: nil)
    }

    func translate(selection: NSRect, on screen: NSScreen) {
        guard let image = screenshot(selection: selection, screen: screen) else { status = "截图失败，请在系统设置中允许屏幕录制。"; return }
        source = ""
        translation = ""
        isTranslating = true
        status = "正在识别文字…"
        // Vision 识别和网络请求不能阻塞 SwiftUI 主线程。
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let text = try self.recognize(image: image)
                guard !text.isEmpty else { throw TranslationError.message("没有识别到文字。") }
                DispatchQueue.main.async {
                    self.source = text
                    guard !self.apiKey.isEmpty else {
                        self.status = "已识别原文；请先在设置中填写 DeepSeek API Key 以翻译。"
                        self.isTranslating = false
                        return
                    }
                    self.status = "正在使用 DeepSeek 翻译…"
                    self.translateRecognizedText(text)
                }
            } catch {
                DispatchQueue.main.async { self.status = error.localizedDescription; self.isTranslating = false }
            }
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

        guard !apiKey.isEmpty else {
            status = "已读取剪贴板文字；请先在设置中填写 DeepSeek API Key。"
            return
        }

        isTranslating = true
        status = "正在翻译剪贴板文字…"
        translateRecognizedText(clipboardText)
    }

    private func translateRecognizedText(_ text: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let result = try self.callDeepSeek(text: text)
                DispatchQueue.main.async {
                    self.translation = result
                    self.status = "翻译完成"
                    self.isTranslating = false
                    NotificationCenter.default.post(
                        name: .translationCompleted,
                        object: TranslationDisplayResult(source: text, translation: result)
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    self.status = error.localizedDescription
                    self.isTranslating = false
                }
            }
        }
    }

    private func screenshot(selection: NSRect, screen: NSScreen) -> CGImage? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let image = CGDisplayCreateImage(CGDirectDisplayID(number.uint32Value)) else { return nil }
        // NSView 坐标原点在左下角，CGImage 裁剪坐标原点在左上角；同时要换算 Retina 比例。
        let scale = CGFloat(image.width) / screen.frame.width
        let crop = CGRect(x: selection.minX * scale,
                          y: (screen.frame.height - selection.maxY) * scale,
                          width: selection.width * scale, height: selection.height * scale).integral
        return image.cropping(to: crop)
    }

    private func recognize(image: CGImage) throws -> String {
        // 指定常用的中英文语言模型；Vision 会按视觉顺序返回识别结果。
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "zh-Hans"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private func callDeepSeek(text: String) throws -> String {
        // 该方法在后台队列执行，用信号量把 URLSession 回调转换成同步结果。
        let body: [String: Any] = ["model": model, "temperature": 0.2, "messages": [
            ["role": "system", "content": "你是专业翻译。只输出译文，保留原有段落、项目符号、专有名词与代码。"],
            ["role": "user", "content": "把以下内容翻译成\(targetLanguage)：\n\n\(text)"]
        ]]
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"; request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error> = .failure(TranslationError.message("网络请求未完成"))
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { result = .failure(error) }
            else if let data { result = .success(data) }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 65)
        let data = try result.get()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let error = json?["error"] as? [String: Any], let message = error["message"] as? String { throw TranslationError.message(message) }
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { throw TranslationError.message("DeepSeek 返回格式异常") }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
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
