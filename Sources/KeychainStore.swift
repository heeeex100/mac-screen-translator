import Foundation
import Security

/// 对 Security.framework 的轻量封装，按 API 提供商分别保存 API Key。
enum KeychainStore {
    // 使用固定 service，确保 `swift run` 和打包后的 App 访问同一条钥匙串记录。
    private static let service = "com.yangchenjie.mac-screen-translator"
    private static let legacyAccount = "deepseek-api-key"

    static func loadAPIKey(provider: APIProvider = .deepSeek) throws -> String? {
        try load(account: account(for: provider))
    }

    static func saveAPIKey(_ value: String, provider: APIProvider = .deepSeek) throws {
        try save(value, account: account(for: provider))
    }

    static func loadVisionAPIKey() throws -> String? { try load(account: "vision-api-key") }
    static func saveVisionAPIKey(_ value: String) throws { try save(value, account: "vision-api-key") }

    // 旧版本只保存 DeepSeek Key，保留无参数 API 方便迁移和兼容。
    static func loadAPIKey() throws -> String? { try load(account: legacyAccount) }
    static func saveAPIKey(_ value: String) throws { try save(value, account: legacyAccount) }

    private static func load(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return value
    }

    private static func save(_ value: String, account: String) throws {
        // 空字符串表示用户主动清除 Key，应删除记录而不是保存空数据。
        if value.isEmpty {
            let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError(status: status)
            }
            return
        }

        let data = Data(value.utf8)
        // 优先更新现有记录；不存在时再新增，避免生成重复项。
        let updateStatus = SecItemUpdate(
            baseQuery(account: account) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecItemNotFound {
            var item = baseQuery(account: account)
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError(status: updateStatus)
        }
    }

    private static func account(for provider: APIProvider) -> String {
        provider == .openAI ? "openai-api-key" : legacyAccount
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private enum KeychainError: LocalizedError {
    case invalidData
    case status(OSStatus)

    init(status: OSStatus) {
        self = .status(status)
    }

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "钥匙串中的 API Key 数据无效。"
        case let .status(status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "未知错误"
            return "钥匙串操作失败：\(message)（\(status)）"
        }
    }
}
