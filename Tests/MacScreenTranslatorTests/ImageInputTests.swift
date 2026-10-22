import AppKit
import XCTest
@testable import MacScreenTranslator

@MainActor
final class ImageInputTests: XCTestCase {
    private func image() -> CGImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return bitmap.cgImage!
    }
    private func pasteboard() -> NSPasteboard { NSPasteboard.withUniqueName() }
    private func writeImage(_ image: CGImage, to board: NSPasteboard, type: NSPasteboard.PasteboardType = .png) {
        let bitmap = NSBitmapImageRep(cgImage: image)
        board.setData(type == .tiff ? bitmap.tiffRepresentation! : bitmap.representation(using: .png, properties: [:])!, forType: type)
    }

    func testReadsPNGAndTIFFClipboardImages() {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            let board = pasteboard()
            defer { board.releaseGlobally() }
            writeImage(image(), to: board, type: type)
            guard case .image(let result) = ClipboardInput.read(from: board) else { return XCTFail("missing image") }
            XCTAssertEqual(result.width, 8)
            XCTAssertEqual(result.height, 8)
        }
    }

    func testImageTakesPriorityOverAccompanyingText() {
        let board = pasteboard(); defer { board.releaseGlobally() }
        writeImage(image(), to: board)
        board.setString("https://example.com/image.png", forType: .string)
        guard case .image = ClipboardInput.read(from: board) else { return XCTFail("URL selected instead of image") }
    }

    func testReadsTrimmedTextAndEmptyClipboard() {
        let board = pasteboard(); defer { board.releaseGlobally() }
        guard case .empty = ClipboardInput.read(from: board) else { return XCTFail() }
        board.setString("  Hello\n", forType: .string)
        guard case .text(let text) = ClipboardInput.read(from: board) else { return XCTFail() }
        XCTAssertEqual(text, "Hello")
    }

    func testClipboardImageRecognizesThenTranslates() async {
        let board = pasteboard(); defer { board.releaseGlobally() }
        writeImage(image(), to: board)
        let store = TranslationStore(apiKey: "test", translationOperation: { text, _, _, _, _ in
            XCTAssertEqual(text, "image text")
            return "图片译文"
        }, imageRecognitionOperation: { image, configuration in
            XCTAssertEqual(image.width, 8)
            guard case .local(let languages) = configuration else { XCTFail(); return "" }
            XCTAssertEqual(languages, ["en-US"])
            return " image text\n"
        }, recognitionConfiguration: { .local(languages: ["en-US"]) })
        await store.translateClipboard(from: board)?.value
        XCTAssertEqual(store.source, "image text")
        XCTAssertEqual(store.translation, "图片译文")
        XCTAssertEqual(store.state, .succeeded)
    }

    func testClipboardTextBypassesImageRecognition() async {
        let board = pasteboard(); defer { board.releaseGlobally() }
        board.setString("hello", forType: .string)
        let store = TranslationStore(apiKey: "test", translationOperation: { text, _, _, _, _ in text },
                                     imageRecognitionOperation: { _, _ in XCTFail("should not recognize"); return "" })
        await store.translateClipboard(from: board)?.value
        XCTAssertEqual(store.translation, "hello")
    }

    func testEmptyClipboardDoesNotStartRequest() {
        let board = pasteboard(); defer { board.releaseGlobally() }
        let store = TranslationStore(apiKey: "test", translationOperation: { _, _, _, _, _ in XCTFail(); return "" })
        XCTAssertNil(store.translateClipboard(from: board))
        XCTAssertFalse(store.isTranslating)
        XCTAssertTrue(store.status.contains("文字或图片"))
    }

    func testMissingTranslationKeyStillPreservesRecognizedText() async {
        let store = TranslationStore(apiKey: "", translationOperation: { _, _, _, _, _ in XCTFail(); return "" },
                                     imageRecognitionOperation: { _, _ in "recognized text" })
        await store.translateImage(image()).value
        XCTAssertEqual(store.source, "recognized text")
        XCTAssertEqual(store.state, .idle)
        XCTAssertFalse(store.isTranslating)
    }

    func testNoRecognizedTextDoesNotCallTranslation() async {
        let store = TranslationStore(apiKey: "test", translationOperation: { _, _, _, _, _ in XCTFail(); return "" },
                                     imageRecognitionOperation: { _, _ in " \n " })
        await store.translateImage(image()).value
        XCTAssertEqual(store.state, .failed)
        XCTAssertEqual(store.status, "没有识别到文字。")
    }

    func testImageRequestUsesSettingsSnapshotAndRejectsLateRecognition() async {
        let started = expectation(description: "image started")
        var pending: CheckedContinuation<String, Error>?
        var settings = VisionModelSettings(baseURL: "https://example.com/v1", model: "vision-a", apiKey: "vision-test")
        let store = TranslationStore(apiKey: "translation-test", translationOperation: { text, key, _, _, _ in
            XCTAssertEqual(key, text == "new text" ? "changed-key" : "translation-test")
            return text
        }, imageRecognitionOperation: { _, configuration in
            guard case .model(let snapshot) = configuration else { XCTFail(); return "" }
            XCTAssertEqual(snapshot.model, "vision-a")
            XCTAssertEqual(snapshot.apiKey, "vision-test")
            return try await withCheckedThrowingContinuation { pending = $0; started.fulfill() }
        }, recognitionConfiguration: { .model(settings) })
        let old = store.translateImage(image())
        settings = VisionModelSettings(baseURL: "https://other.example/v1", model: "vision-b", apiKey: "changed")
        store.apiKey = "changed-key"
        await fulfillment(of: [started], timeout: 2)
        // The translation key must also remain the one captured before recognition.
        pending?.resume(returning: "image text")
        await old.value
        XCTAssertEqual(store.translation, "image text")
        // Start another image, then replace it with text before recognition returns.
        let lateStarted = expectation(description: "late image started")
        var late: CheckedContinuation<String, Error>?
        let other = TranslationStore(apiKey: "test", translationOperation: { text, _, _, _, _ in text },
                                     imageRecognitionOperation: { _, _ in
            try await withCheckedThrowingContinuation { late = $0; lateStarted.fulfill() }
        })
        let stale = other.translateImage(image())
        await fulfillment(of: [lateStarted], timeout: 2)
        await other.translateInput("new text")?.value
        late?.resume(returning: "old image")
        await stale.value
        XCTAssertEqual(other.source, "new text")
        XCTAssertEqual(other.translation, "new text")
        XCTAssertEqual(other.state, .succeeded)
    }

    func testLocalVisionReadsGeneratedImage() async throws {
        guard ProcessInfo.processInfo.environment["MAC_TRANSLATOR_LIVE_OCR_TEST"] == "1" else {
            throw XCTSkip("真实 Vision 集成测试需显式启用；依赖系统识别模型和 Neural Engine。")
        }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 180,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 900, height: 180).fill()
        NSString(string: "Clipboard image translation").draw(at: NSPoint(x: 25, y: 65),
            withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        let text = try await ImageRecognition.recognize(bitmap.cgImage!, configuration: .local(languages: ["en-US"]))
        XCTAssertEqual(text, "Clipboard image translation")
    }
    func testAutomaticVisionReadsChineseAndEnglish() async throws {
        guard ProcessInfo.processInfo.environment["MAC_TRANSLATOR_LIVE_OCR_TEST"] == "1" else {
            throw XCTSkip("真实 Vision 集成测试需显式启用。")
        }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 240,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1200, height: 240).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black]
        NSString(string: "小小的行动带来巨大的改变。").draw(at: NSPoint(x: 25, y: 140), withAttributes: attributes)
        NSString(string: "Small steps make a big difference.").draw(at: NSPoint(x: 25, y: 50), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        let text = try await ImageRecognition.recognize(bitmap.cgImage!, configuration: .local(languages: ["en-US", "zh-Hans", "ja-JP", "ko-KR"]))
        XCTAssertTrue(text.contains("小小的行动带来巨大的改变"), text)
        XCTAssertTrue(text.contains("Small steps make a big difference"), text)
    }

}
