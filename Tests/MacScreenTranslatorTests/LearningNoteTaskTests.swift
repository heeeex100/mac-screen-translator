import XCTest
@testable import MacScreenTranslator

@MainActor
final class LearningNoteTaskTests: XCTestCase {
    private final class Gate {
        let started = XCTestExpectation(description: "request started")
        var continuation: CheckedContinuation<LearningNote, Error>?
        func run() async throws -> LearningNote {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                started.fulfill()
            }
        }
    }
    private let noteA = LearningNote(summary: "A", keyPoints: "", words: "")
    private let noteB = LearningNote(summary: "B", keyPoints: "", words: "")

    func testLateSuccessDoesNotOverwriteNewResult() async {
        let loader = LearningNoteTask(), a = Gate(), b = Gate()
        var displayed: LearningNote?
        let old = loader.start(operation: a.run) { displayed = try? $0.get() }
        await fulfillment(of: [a.started], timeout: 2)
        let current = loader.start(operation: b.run) { displayed = try? $0.get() }
        await fulfillment(of: [b.started], timeout: 2)
        b.continuation?.resume(returning: noteB)
        await current.value
        a.continuation?.resume(returning: noteA)
        await old.value
        XCTAssertEqual(displayed, noteB)
    }

    func testOldFailureDoesNotClearNewLoadingStateOrReportError() async {
        let loader = LearningNoteTask(), a = Gate(), b = Gate()
        var loading = true
        var error: Error?
        let old = loader.start(operation: a.run) { result in
            loading = false
            if case .failure(let value) = result { error = value }
        }
        await fulfillment(of: [a.started], timeout: 2)
        let current = loader.start(operation: b.run) { _ in loading = false }
        await fulfillment(of: [b.started], timeout: 2)
        a.continuation?.resume(throwing: NSError(domain: "old request", code: 1))
        await old.value
        XCTAssertTrue(loading)
        XCTAssertNil(error)
        b.continuation?.resume(returning: noteB)
        await current.value
        XCTAssertFalse(loading)
    }

    func testCancelRejectsResultEvenIfOperationIgnoresCancellation() async {
        let loader = LearningNoteTask(), gate = Gate()
        var completed = false
        let task = loader.start(operation: gate.run) { _ in completed = true }
        await fulfillment(of: [gate.started], timeout: 2)
        loader.cancel()
        gate.continuation?.resume(returning: noteA)
        await task.value
        XCTAssertFalse(completed)
    }

    func testStoreSnapshotsInputAndInvalidatesOnTextChangeWithoutAPIKey() async {
        let gate = Gate()
        var received: (String, String)?
        let store = TranslationStore(apiKey: "test", learningOperation: { text, translated, _, _, _ in
            received = (text, translated)
            return try await gate.run()
        })
        store.source = "This is the first sentence."
        store.translation = "第一句"
        let task = store.loadLearningNote()
        await fulfillment(of: [gate.started], timeout: 2)
        XCTAssertEqual(received?.0, "This is the first sentence.")
        XCTAssertEqual(received?.1, "第一句")
        store.apiKey = ""
        store.translateInput("This is the second sentence.")
        XCTAssertFalse(store.isLoadingLearningNote)
        XCTAssertNil(store.learningNote)
        let status = store.status
        gate.continuation?.resume(returning: noteA)
        await task?.value
        XCTAssertNil(store.learningNote)
        XCTAssertEqual(store.status, status)
    }

    func testStoreTranslationChangeCancelsLearning() async {
        let gate = Gate()
        let store = TranslationStore(apiKey: "test", learningOperation: { _, _, _, _, _ in try await gate.run() })
        store.source = "This is a sentence worth learning."
        store.translation = "旧译文"
        let task = store.loadLearningNote()
        await fulfillment(of: [gate.started], timeout: 2)
        store.translation = "新译文"
        XCTAssertFalse(store.isLoadingLearningNote)
        gate.continuation?.resume(throwing: NSError(domain: "old", code: 1))
        await task?.value
        XCTAssertNil(store.learningNote)
        XCTAssertEqual(store.status, "准备就绪。输入原文，或使用上方按钮获取文字。")
    }

    func testStoreOldCompletionCannotClearNewRequestLoadingState() async {
        let a = Gate(), b = Gate()
        let store = TranslationStore(apiKey: "test", learningOperation: { text, _, _, _, _ in
            try await (text.contains("first") ? a : b).run()
        })
        store.source = "This is the first sentence."
        store.translation = "第一句"
        let old = store.loadLearningNote()
        await fulfillment(of: [a.started], timeout: 2)
        store.source = "This is the second sentence."
        store.translation = "第二句"
        let current = store.loadLearningNote()
        await fulfillment(of: [b.started], timeout: 2)
        a.continuation?.resume(returning: noteA)
        await old?.value
        XCTAssertTrue(store.isLoadingLearningNote)
        XCTAssertNil(store.learningNote)
        b.continuation?.resume(returning: noteB)
        await current?.value
        XCTAssertFalse(store.isLoadingLearningNote)
        XCTAssertEqual(store.learningNote, noteB)
    }

    func testCurrentFailureStillReportsErrorAndAllowsRetry() async {
        let gate = Gate()
        let store = TranslationStore(apiKey: "test", learningOperation: { _, _, _, _, _ in try await gate.run() })
        store.source = "This is a sentence worth learning."
        store.translation = "译文"
        let task = store.loadLearningNote()
        await fulfillment(of: [gate.started], timeout: 2)
        let error = NSError(domain: "learning", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "测试请求失败"])
        gate.continuation?.resume(throwing: error)
        await task?.value
        XCTAssertEqual(store.status, "测试请求失败")
        XCTAssertEqual(store.learningError, "测试请求失败")
        XCTAssertFalse(store.isLoadingLearningNote)
        XCTAssertNil(store.learningNote)
    }

}
