// KeychainManager.swift
// Secure storage for API keys using iOS Keychain.
// Replaces UserDefaults for all sensitive credentials.

import Security
import Foundation

enum KeychainManager {

    // MARK: - Keys

    enum Key: String {
        case claudeAPIKey  = "com.walkie.key.claude"
        case openAIAPIKey  = "com.walkie.key.openai"
        case geminiAPIKey  = "com.walkie.key.gemini"
        case grokAPIKey    = "com.walkie.key.grok"
        case deviceId      = "com.walkie.device.id"
    }

    // MARK: - Save

    @discardableResult
    static func save(_ value: String, for key: Key) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrAccount as String:      key.rawValue,
            kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        // Delete existing before saving
        SecItemDelete(query as CFDictionary)

        if value.isEmpty { return true }  // Empty = delete only

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Load

    static func load(_ key: Key) -> String {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return "" }
        return string
    }

    // MARK: - Delete

    @discardableResult
    static func delete(_ key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    // MARK: - Clear all app keys

    static func clearAll() {
        Key.allCases.forEach { delete($0) }
    }
}

extension KeychainManager.Key: CaseIterable {}
