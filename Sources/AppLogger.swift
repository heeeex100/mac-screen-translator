import AppKit
import Foundation
import os

/// 同时写入 macOS 统一日志和可直接打开的文本文件。
/// 请求正文、API Key 和原文都不写入日志，只记录定位网络问题所需的元数据。
final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()

    let fileURL: URL

    private let logger = Logger(subsystem: "com.yangchenjie.mac-screen-translator", category: "translation")
    private let lock = NSLock()
    private let dateFormatter: ISO8601DateFormatter

    private init() {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = library.appendingPathComponent("Logs/MacScreenTranslator", isDirectory: true)
        fileURL = directory.appendingPathComponent("translation.log")
        dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
        } catch {
            // 统一日志仍然可用，调用方不应因为日志文件不可写而中断翻译。
            logger.error("无法创建日志文件：\(error.localizedDescription, privacy: .public)")
        }
    }

    func info(_ message: String) {
        write(message, level: .info)
    }

    func error(_ message: String) {
        write(message, level: .error)
    }

    func openInFinder() {
        ensureFileExists()
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private func write(_ message: String, level: OSLogType) {
        switch level {
        case .error:
            logger.error("\(message, privacy: .public)")
        default:
            logger.info("\(message, privacy: .public)")
        }

        lock.lock()
        defer { lock.unlock() }
        let line = "[\(dateFormatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        do {
            ensureFileExists()
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            logger.error("无法写入日志文件：\(error.localizedDescription, privacy: .public)")
        }
    }

    private func ensureFileExists() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        } catch {
            logger.error("无法初始化日志文件：\(error.localizedDescription, privacy: .public)")
        }
    }
}
