import CoreGraphics
import XCTest
@testable import MacScreenTranslator

final class PinContractTests: XCTestCase {
    func testHalfOpenRectExcludesFarEdges() {
        let rect = PixelRect(x: 10, y: 20, width: 2, height: 3)
        XCTAssertTrue(rect.contains(x: 10, y: 20))
        XCTAssertTrue(rect.contains(x: 11, y: 22))
        XCTAssertFalse(rect.contains(x: 12, y: 20))
        XCTAssertFalse(rect.contains(x: 10, y: 23))
    }

    func testPinTextRejectsBlankAndKeepsSurroundingSpaces() throws {
        XCTAssertThrowsError(try PinContent.fromText(" \n\t")) { error in
            XCTAssertEqual(error as? PinContentError, .blankText)
        }
        let content = try PinContent.fromText("  你好  ")
        XCTAssertNil(content.image)
        XCTAssertEqual(content.text, "  你好  ")
    }

    func testImageAndTextStayExclusive() throws {
        let content = try PinContent.fromImage(solidImage(width: 2, height: 2, red: 10, green: 20, blue: 30))
        XCTAssertNotNil(content.image)
        XCTAssertNil(content.text)
    }

    func testCaptureCommitCopiesPixelsAndDoesNotShareTheSourceObject() throws {
        let source = solidImage(width: 2, height: 2, red: 9, green: 8, blue: 7)
        let commit = try CaptureCommit(image: source, kind: .pinImage)
        XCTAssertFalse(commit.image === source)
        XCTAssertEqual(pixels(commit.image), pixels(source))
        XCTAssertEqual(commit.kind, .pinImage)
    }

    func testOnePixelCropStaysRejected() {
        let screen = CGSize(width: 100, height: 100)
        XCTAssertNil(ScreenshotGeometry.cropRect(
            selection: CGRect(x: 4, y: 4, width: 1, height: 8),
            screenSize: screen,
            imageSize: screen
        ))
        XCTAssertNil(ScreenshotGeometry.cropRect(
            selection: CGRect(x: 4, y: 4, width: 8, height: 1),
            screenSize: screen,
            imageSize: screen
        ))
    }

    func testCancelThenNextAttemptKeepsCorrelationAndOpensAFreshToken() throws {
        let lifetime = PinLifetime()
        let job = TranslationJob.start(lifetime: lifetime)
        let first = job.attemptID
        var firstFired = false
        try job.registerCancellation { firstFired = true }

        job.cancel()
        let retry = job.nextAttempt()

        XCTAssertTrue(firstFired)
        XCTAssertEqual(retry.correlationID, job.correlationID)
        XCTAssertNotEqual(retry.attemptID, first)
        XCTAssertFalse(job.accepts(first))
        XCTAssertFalse(retry.isCancellationRequested)
        XCTAssertTrue(retry.accepts(retry.attemptID))
        XCTAssertFalse(retry.accepts(job.correlationID))
    }

    func testNextAttemptWithoutCancelLeavesThePreviousAttemptOpen() throws {
        let job = TranslationJob.start()
        var fired = false
        try job.registerCancellation { fired = true }
        let next = job.nextAttempt()

        XCTAssertFalse(fired)
        XCTAssertFalse(job.isCancellationRequested)
        XCTAssertTrue(job.accepts(job.attemptID))
        XCTAssertFalse(next.isCancellationRequested)
        XCTAssertEqual(next.correlationID, job.correlationID)
        XCTAssertNotEqual(next.attemptID, job.attemptID)
    }

    func testCancelledTokenStillAcceptsAnotherRegistration() throws {
        let job = TranslationJob.start()
        job.cancel()
        var fired = false
        try job.registerCancellation { fired = true }
        XCTAssertTrue(fired)
        XCTAssertFalse(job.accepts(job.attemptID))
    }

    func testDisposeDoesNotCancelOrFire() throws {
        let lifetime = PinLifetime()
        let job = TranslationJob.start(lifetime: lifetime)
        var fired = false
        try job.registerCancellation { fired = true }

        job.dispose()
        lifetime.cancel()

        XCTAssertFalse(fired)
        XCTAssertFalse(job.isCancellationRequested)
        XCTAssertTrue(job.accepts(job.attemptID))
        XCTAssertThrowsError(try job.registerCancellation {}) { error in
            XCTAssertEqual(error as? PinTokenError, .disposed)
        }
    }

    func testNextAttemptAfterLifetimeCancelStartsCancelled() {
        let lifetime = PinLifetime()
        let job = TranslationJob.start(lifetime: lifetime)
        lifetime.cancel()
        let born = job.nextAttempt()
        XCTAssertTrue(born.isCancellationRequested)
        XCTAssertFalse(born.accepts(born.attemptID))
        XCTAssertEqual(born.correlationID, job.correlationID)
    }

    func testLifetimeCancelPropagatesOnlyThroughItsOwnJob() throws {
        let lifetime = PinLifetime()
        let job = TranslationJob.start(lifetime: lifetime)
        let other = TranslationJob.start()
        var fired = false
        try job.registerCancellation { fired = true }

        lifetime.cancel()

        XCTAssertTrue(fired)
        XCTAssertFalse(job.accepts(job.attemptID))
        XCTAssertTrue(other.accepts(other.attemptID))
    }

    private func solidImage(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) -> CGImage {
        let bytesPerRow = width * 4
        var data = Data(count: height * bytesPerRow)
        for pixel in 0..<(width * height) {
            data[pixel * 4] = red
            data[pixel * 4 + 1] = green
            data[pixel * 4 + 2] = blue
            data[pixel * 4 + 3] = 255
        }
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        var data = Data(count: image.height * image.width * 4)
        data.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return [UInt8](data)
    }
}

@MainActor
final class PinBoardTests: XCTestCase {
    func testClosingOnePinLeavesTheOtherJobAndPixels() throws {
        let board = PinBoard()
        let image = solidImage(width: 3, height: 2, red: 1, green: 2, blue: 3)
        let first = try board.pinImage(image)
        let second = try board.pinText("译文")
        var firstFired = false
        try first.job.registerCancellation { firstFired = true }
        let firstPixels = pixels(first.content.image!)

        board.close(first)

        XCTAssertTrue(firstFired)
        XCTAssertFalse(first.job.accepts(first.job.attemptID))
        XCTAssertFalse(second.job.isCancellationRequested)
        XCTAssertTrue(second.job.accepts(second.job.attemptID))
        XCTAssertEqual(board.pins.map { $0.content.text }, ["译文"])
        XCTAssertEqual(firstPixels, pixels(image))
        XCTAssertFalse(first.content.image! === image)
        XCTAssertFalse(first.panel.isVisible)
        XCTAssertFalse(second.panel.isVisible)
        board.close(second)
    }

    func testNextAttemptOnOnePinDoesNotCancelItsPreviousTokenOrTheOtherPin() throws {
        let board = PinBoard()
        let pin = try board.pinText("原文")
        let other = try board.pinText("另一张")
        let previous = pin.job
        var fired = false
        try previous.registerCancellation { fired = true }

        let next = pin.nextAttempt()

        XCTAssertFalse(fired)
        XCTAssertTrue(previous.accepts(previous.attemptID))
        XCTAssertTrue(next.accepts(next.attemptID))
        XCTAssertEqual(next.correlationID, previous.correlationID)
        XCTAssertTrue(other.job.accepts(other.job.attemptID))
        XCTAssertFalse(pin.panel.isVisible)
        board.close(pin)
        board.close(other)
    }

    func testPinningDoesNotClearTheTranslationStore() throws {
        let store = TranslationStore(apiKey: "test", translationOperation: { _, _, _, _, _ in "不应被调用" })
        store.source = "主窗口原文"
        store.translation = "主窗口译文"
        let board = PinBoard()
        let pin = try board.pinText("贴图")
        XCTAssertEqual(store.source, "主窗口原文")
        XCTAssertEqual(store.translation, "主窗口译文")
        XCTAssertEqual(store.state, .idle)
        board.close(pin)
    }

    private func solidImage(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) -> CGImage {
        let bytesPerRow = width * 4
        var data = Data(count: height * bytesPerRow)
        for pixel in 0..<(width * height) {
            data[pixel * 4] = red
            data[pixel * 4 + 1] = green
            data[pixel * 4 + 2] = blue
            data[pixel * 4 + 3] = 255
        }
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        var data = Data(count: image.height * image.width * 4)
        data.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return [UInt8](data)
    }
}
