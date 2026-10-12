import Foundation

/// 独立解析服务返回的学习笔记，不依赖网络或界面状态。
enum LearningNoteParser {
    static func parse(_ response: String) throws -> LearningNote {
        var content = response.replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}"), start < end {
            content = String(content[start...end])
        }
        guard let data = content.data(using: .utf8),
              let note = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw ParseError.invalidFormat
        }
        return LearningNote(
            summary: clean(note["summary"] ?? "", prefixes: ["句意：", "句意:"]),
            keyPoints: clean(note["keyPoints"] ?? "", prefixes: ["表达要点：", "表达要点:", "提示：", "提示:"]),
            words: clean(note["words"] ?? "", prefixes: ["重点词汇：", "重点词汇:", "格式：", "格式:"])
        )
    }

    private static func clean(_ text: String, prefixes: [String]) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in prefixes where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    enum ParseError: LocalizedError {
        case invalidFormat
        var errorDescription: String? { "学习笔记格式异常" }
    }
}
