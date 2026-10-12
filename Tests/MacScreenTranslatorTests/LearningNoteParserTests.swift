import XCTest
@testable import MacScreenTranslator

final class LearningNoteParserTests: XCTestCase {
    func testPreservesUnicodeAndMultipleLines() throws {
        let response = #"{"summary":"理解句意 😀","keyPoints":"第一段\n第二段","words":"take off — 起飞\nland — 降落"}"#
        let note = try LearningNoteParser.parse(response)
        XCTAssertEqual(note, LearningNote(summary: "理解句意 😀", keyPoints: "第一段\n第二段",
                                          words: "take off — 起飞\nland — 降落"))
    }

    func testAcceptsMarkdownCodeFence() throws {
        let response = "```json\n{\"summary\":\"句子含义\"}\n```"
        XCTAssertEqual(try LearningNoteParser.parse(response).summary, "句子含义")
    }

    func testAcceptsExplanationAroundJSON() throws {
        let response = "以下是学习笔记：\n{\"words\":\"context — 上下文\"}\n希望对你有帮助。"
        XCTAssertEqual(try LearningNoteParser.parse(response).words, "context — 上下文")
    }

    func testMissingFieldsBecomeEmptyStrings() throws {
        XCTAssertEqual(try LearningNoteParser.parse("{}"),
                       LearningNote(summary: "", keyPoints: "", words: ""))
        XCTAssertEqual(try LearningNoteParser.parse(#"{"summary":"仅句意"}"#),
                       LearningNote(summary: "仅句意", keyPoints: "", words: ""))
    }

    func testRemovesLeadingLabelsAndSurroundingWhitespace() throws {
        let response = #"{"summary":" 句意： 自然表达 \n","keyPoints":"表达要点: 提示： 使用过去时","words":"重点词汇： 格式: word — 含义 "}"#
        XCTAssertEqual(try LearningNoteParser.parse(response),
                       LearningNote(summary: "自然表达", keyPoints: "使用过去时", words: "word — 含义"))
    }

    func testDoesNotStripLabelsInsideActualContent() throws {
        let note = try LearningNoteParser.parse(#"{"keyPoints":"这里的提示：需要保留","words":"格式化 — format"}"#)
        XCTAssertEqual(note.keyPoints, "这里的提示：需要保留")
        XCTAssertEqual(note.words, "格式化 — format")
    }

    func testRejectsMalformedJSONAndWrongFieldTypes() {
        for response in ["", "不是 JSON", "{broken}", "[]",
                         #"{"summary":42}"#, #"{"summary":null}"#] {
            XCTAssertThrowsError(try LearningNoteParser.parse(response), response) { error in
                XCTAssertEqual(error.localizedDescription, "学习笔记格式异常")
            }
        }
    }
}
