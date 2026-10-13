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
}
