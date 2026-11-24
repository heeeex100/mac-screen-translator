import CoreGraphics
import Foundation

/// 物理像素矩形，左上角含、右下角不含。
struct PixelRect: Equatable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    var maxX: Int { x + width }
    var maxY: Int { y + height }

    func contains(x px: Int, y py: Int) -> Bool {
        px >= x && py >= y && px < maxX && py < maxY
    }
}

/// 一次冻结只提交一种输出。复制和取消必须用不同的值表示，不能再收成空图。
enum OutputKind: Equatable {
    case copyImage
    case savePNG
    case pinImage
    case recognizeOnly
    case translate
}

/// 确认后的合成图。只保存这一张裁剪结果，不保存整屏帧。
struct CaptureCommit {
    let image: CGImage
    let kind: OutputKind

    init(image: CGImage, kind: OutputKind) throws {
        self.image = try PinImages.copy(image)
        self.kind = kind
    }
}

enum PinContentError: Error, Equatable {
    case blankText
    case copyFailed
}

/// 贴图内容是图像或文字，二者互斥。图像是确认时刻的像素副本。
struct PinContent {
    let image: CGImage?
    let text: String?

    static func fromImage(_ image: CGImage) throws -> PinContent {
        PinContent(image: try PinImages.copy(image), text: nil)
    }

    static func fromText(_ text: String) throws -> PinContent {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PinContentError.blankText
        }
        return PinContent(image: nil, text: text)
    }
}

enum PinTokenError: Error, Equatable {
    case disposed
}

/// 一张贴图或一条工作会话的生存期。取消它会取消只链接到它的尝试，不会取消别的生存期。
final class PinLifetime {
    private let lock = NSLock()
    private var cancelled = false
    private var observers: [UUID: () -> Void] = [:]

    var isCancellationRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        let callbacks: [() -> Void] = {
            lock.lock()
            defer { lock.unlock() }
            guard !cancelled else { return [] }
            cancelled = true
            let values = Array(observers.values)
            observers.removeAll()
            return values
        }()
        callbacks.forEach { $0() }
    }

    @discardableResult
    func register(_ handler: @escaping () -> Void) -> UUID {
        lock.lock()
        if cancelled {
            lock.unlock()
            handler()
            return UUID()
        }
        let id = UUID()
        observers[id] = handler
        lock.unlock()
        return id
    }

    func unregister(_ id: UUID) {
        lock.lock()
        observers[id] = nil
        lock.unlock()
    }
}

/// 日志用稳定的 `correlationID`。界面能不能写回只看这一次 `attemptID` 和令牌。
/// `nextAttempt` 只链接当初的生存期，不链接上一次已取消的令牌。
final class TranslationJob {
    let correlationID: UUID
    let attemptID: UUID
    private let lifetime: PinLifetime
    private let attempt: AttemptCancellation

    private init(correlationID: UUID, lifetime: PinLifetime) {
        self.correlationID = correlationID
        self.attemptID = UUID()
        self.lifetime = lifetime
        self.attempt = AttemptCancellation(lifetime: lifetime)
    }

    static func start(lifetime: PinLifetime = PinLifetime()) -> TranslationJob {
        TranslationJob(correlationID: UUID(), lifetime: lifetime)
    }

    var isCancellationRequested: Bool { attempt.isCancellationRequested }

    /// 同一关联 Id，新的尝试。不取消接收者自己。
    func nextAttempt() -> TranslationJob {
        TranslationJob(correlationID: correlationID, lifetime: lifetime)
    }

    /// 只取消这一次尝试，不释放令牌源。
    func cancel() { attempt.cancel() }

    func accepts(_ completedAttemptID: UUID) -> Bool {
        completedAttemptID == attemptID && !attempt.isCancellationRequested
    }

    /// 只释放令牌源，不取消，也不触发已登记的取消回调。
    func dispose() { attempt.dispose() }

    func registerCancellation(_ handler: @escaping () -> Void) throws {
        try attempt.register(handler)
    }
}

private final class AttemptCancellation {
    private let lock = NSLock()
    private var locallyCancelled = false
    private var disposed = false
    private var observers: [UUID: () -> Void] = [:]
    private let lifetime: PinLifetime
    private var lifetimeRegistration: UUID?

    init(lifetime: PinLifetime) {
        self.lifetime = lifetime
        if lifetime.isCancellationRequested {
            locallyCancelled = true
            return
        }
        lifetimeRegistration = lifetime.register { [weak self] in
            self?.cancel()
        }
    }

    var isCancellationRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return locallyCancelled
    }

    func cancel() {
        let callbacks: [() -> Void] = {
            lock.lock()
            defer { lock.unlock() }
            if disposed || locallyCancelled { return [] }
            locallyCancelled = true
            let values = Array(observers.values)
            observers.removeAll()
            return values
        }()
        callbacks.forEach { $0() }
    }

    func dispose() {
        let registration: UUID? = {
            lock.lock()
            defer { lock.unlock() }
            if disposed { return nil }
            disposed = true
            observers.removeAll()
            let id = lifetimeRegistration
            lifetimeRegistration = nil
            return id
        }()
        if let registration { lifetime.unregister(registration) }
    }

    func register(_ handler: @escaping () -> Void) throws {
        lock.lock()
        if disposed {
            lock.unlock()
            throw PinTokenError.disposed
        }
        if locallyCancelled {
            lock.unlock()
            handler()
            return
        }
        observers[UUID()] = handler
        lock.unlock()
    }
}

enum PinImages {
    static func copy(_ image: CGImage) throws -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { throw PinContentError.copyFailed }
        let bytesPerRow = width * 4
        var data = Data(count: height * bytesPerRow)
        let drew = data.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew, let provider = CGDataProvider(data: data as CFData) else { throw PinContentError.copyFailed }
        guard let copied = CGImage(
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
        ) else { throw PinContentError.copyFailed }
        return copied
    }
}
