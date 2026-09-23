// Development helper: store only this disposable test home's token for the
// already installed plugin. No tokens enter command arguments or logs.
import Foundation
import Security
@main struct ImportCredential {
    static func main() throws {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let object = try JSONSerialization.jsonObject(with: input) as! [String: String]
        guard object["server"] == "http://127.0.0.1:18123", let token = object["plugin_token"], let executable = object["executable"], executable.hasSuffix("/Plugin.app/Contents/MacOS/HomeAssistantPlugin") else { throw NSError(domain: "TestHome", code: 1) }
        var app: SecTrustedApplication?
        guard SecTrustedApplicationCreateFromPath(executable, &app) == errSecSuccess, let app else { throw NSError(domain: "TestHome", code: 2) }
        var access: SecAccess?
        guard SecAccessCreate("NeroNook disposable test-home token" as CFString, [app] as CFArray, &access) == errSecSuccess, let access else { throw NSError(domain: "TestHome", code: 3) }
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "cafe.nero.plugin.homeassistant.auth", kSecAttrAccount as String: object["server"]!]
        let data = Data(token.utf8)
        var item = base; item[kSecValueData as String] = data; item[kSecAttrAccess as String] = access
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let result = SecItemAdd(item as CFDictionary, nil)
        if result == errSecDuplicateItem {
            let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        } else if result != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
        print("Stored the disposable test-home token for the installed plugin.")
    }
}
