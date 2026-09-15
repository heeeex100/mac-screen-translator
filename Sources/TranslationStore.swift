import AppKit
import Vision
import SwiftUI

final class TranslationStore: ObservableObject {
    @Published var source = ""
    @Published var translation = ""
    @Published var status = "准备就绪。按 Ctrl+Shift+T 框选翻译。"
    @Published var isTranslating = false

    @AppStorage("deepseekAPIKey") var apiKey = ""
    @AppStorage("deepseekModel") var model = "deepseek-flash"
    @AppStorage("targetLanguage") var targetLanguage = "中文（简体）"

    func translate(selection: NSRect, on screen: NSScreen) {
        guard !apiKey.isEmpty else { status = "请先在设置中填写 DeepSeek API Key。"; return }
        guard let image = screenshot(selection: selection, screen: screen) else { status = "截图失败，请在系统设置中允许屏幕录制。"; return }
        isTranslating = true; status = "正在识别文字…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let text = try self.recognize(image: image)
                guard !text.isEmpty else { throw TranslationError.message("没有识别到文字。") }
                DispatchQueue.main.async { self.source = text; self.status = "正在使用 DeepSeek 翻译…" }
                let result = try self.callDeepSeek(text: text)
                DispatchQueue.main.async {
                    self.translation = result; self.status = "翻译完成"; self.isTranslating = false
                }
            } catch {
                DispatchQueue.main.async { self.status = error.localizedDescription; self.isTranslating = false }
            }
        }
    }

    private func screenshot(selection: NSRect, screen: NSScreen) -> CGImage? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let image = CGDisplayCreateImage(CGDirectDisplayID(number.uint32Value)) else { return nil }
        let scale = CGFloat(image.width) / screen.frame.width
        let crop = CGRect(x: selection.minX * scale,
                          y: (screen.frame.height - selection.maxY) * scale,
                          width: selection.width * scale, height: selection.height * scale).integral
        return image.cropping(to: crop)
    }

    private func recognize(image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "zh-Hans"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private func callDeepSeek(text: String) throws -> String {
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

private enum TranslationError: LocalizedError { case message(String); var errorDescription: String? { if case let .message(value) = self { return value }; return nil } }
