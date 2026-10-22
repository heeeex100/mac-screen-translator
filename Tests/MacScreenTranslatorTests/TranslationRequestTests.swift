import XCTest
@testable import MacScreenTranslator

@MainActor
final class TranslationRequestTests: XCTestCase {
    private final class Gate {
        let started = XCTestExpectation(description: "translation started")
        var continuation: CheckedContinuation<String, Error>?
        func run() async throws -> String {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                started.fulfill()
            }
        }
    }

    func testNewTranslationReplacesPendingRequestAndRejectsLateSuccess() async {
        let a = Gate(), b = Gate()
        let store = TranslationStore(apiKey: "test", translationOperation: { text, _, _, _, _ in
            try await (text == "A" ? a : b).run()
        })
        let old = store.translateInput("A")
        await fulfillment(of: [a.started], timeout: 2)
        let current = store.translateInput("B")
        await fulfillment(of: [b.started], timeout: 2)
        b.continuation?.resume(returning: "译文 B")
        await current?.value
        a.continuation?.resume(returning: "译文 A")
        await old?.value
        XCTAssertEqual(store.source, "B")
        XCTAssertEqual(store.translation, "译文 B")
        XCTAssertEqual(store.state, .succeeded)
    }

    func testPreparingCaptureImmediatelyCancelsPendingRequestAndRejectsLateFailure() async {
        let gate = Gate()
        let store = TranslationStore(apiKey: "test", translationOperation: { _, _, _, _, _ in try await gate.run() })
        let old = store.translateInput("A")
        await fulfillment(of: [gate.started], timeout: 2)
        XCTAssertTrue(store.isTranslating)
        store.prepareForCapture()
        XCTAssertFalse(store.isTranslating)
        XCTAssertEqual(store.state, .idle)
        store.status = "请框选要翻译的区域…"
        gate.continuation?.resume(throwing: NSError(domain: "old", code: 1))
        await old?.value
        XCTAssertEqual(store.status, "请框选要翻译的区域…")
        XCTAssertEqual(store.state, .idle)
    }

    func testOldFailureCannotStopReplacementTranslation() async {
        let a = Gate(), b = Gate()
        let store = TranslationStore(apiKey: "test", translationOperation: { text, _, _, _, _ in
            try await (text == "A" ? a : b).run()
        })
        let old = store.translateInput("A")
        await fulfillment(of: [a.started], timeout: 2)
        store.prepareForCapture()
        let current = store.translateInput("B")
        await fulfillment(of: [b.started], timeout: 2)
        a.continuation?.resume(throwing: NSError(domain: "old", code: 1))
        await old?.value
        XCTAssertTrue(store.isTranslating)
        XCTAssertEqual(store.state, .translating)
        XCTAssertEqual(store.status, "正在翻译输入文字…")
        b.continuation?.resume(returning: "译文 B")
        await current?.value
        XCTAssertEqual(store.translation, "译文 B")
    }
    func testEditingSourceWhileRequestRunsRejectsMismatchedResult() async {
        let gate = Gate()
        let store = TranslationStore(apiKey: "test", translationOperation: { _, _, _, _, _ in try await gate.run() })
        let task = store.translateInput("Original sentence")
        await fulfillment(of: [gate.started], timeout: 2)
        store.source = "Edited sentence"
        gate.continuation?.resume(returning: "旧原文的译文")
        await task?.value
        XCTAssertTrue(store.translation.isEmpty)
        XCTAssertFalse(store.isTranslating)
        XCTAssertEqual(store.status, "原文已修改，请重新翻译。")
    }

    func testRetryUsesEditedSource() async {
        var inputs: [String] = []
        let store = TranslationStore(apiKey: "test", translationOperation: { text, _, _, _, _ in
            inputs.append(text)
            throw TranslationError.message("暂时不可用")
        })
        await store.translateInput("Original")?.value
        store.source = "Edited"
        store.retryLastTranslation()
        for _ in 0..<20 where inputs.count < 2 { await Task.yield() }
        XCTAssertEqual(inputs, ["Original", "Edited"])
    }

    func testEditedSourceCannotGenerateLearningFromOldTranslation() async {
        let store = TranslationStore(apiKey: "test", translationOperation: { _, _, _, _, _ in "译文" })
        await store.translateInput("This sentence is worth learning.")?.value
        XCTAssertTrue(store.hasCurrentTranslation)
        store.source = "This is a different sentence."
        XCTAssertFalse(store.hasCurrentTranslation)
        XCTAssertNil(store.loadLearningNote())
    }

    func testMissingModelFailsBeforeCallingService() async {
        let store = TranslationStore(apiKey: "test", translationOperation: { _, _, _, _, _ in
            XCTFail("empty model should not reach network operation")
            return ""
        })
        let originalModel = store.model
        defer { store.model = originalModel }
        store.model = "  "
        await store.translateInput("Test sentence")?.value
        XCTAssertEqual(store.state, .failed)
        XCTAssertEqual(store.status, "请在设置中填写翻译模型名称。")
    }

}
