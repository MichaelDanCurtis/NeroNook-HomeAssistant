import Foundation
import Security

enum CredentialStore {
    static func token(for device: String, allowUI: Bool) throws -> String? {
        var query = base(device); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        // Automatic reconnect must never wait on a hidden system approval.
        // Only the user's explicit Connect gesture may request Keychain UI.
        query[kSecUseAuthenticationUI as String] = allowUI ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail
        var value: CFTypeRef?
        let result = SecItemCopyMatching(query as CFDictionary, &value)
        if result == errSecItemNotFound { return nil }
        guard result == errSecSuccess, let data = value as? Data, let token = String(data: data, encoding: .utf8) else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
        return token
    }
    static func save(_ token: String, for device: String) throws {
        let query = base(device), data = Data(token.utf8)
        let result = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data; item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(item as CFDictionary, nil); guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        } else if result != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
    }
    static func remove(_ device: String) throws {
        let status = SecItemDelete(base(device) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
    private static func base(_ device: String) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "cafe.nero.plugin.homeassistant.auth", kSecAttrAccount as String: device] }
}
