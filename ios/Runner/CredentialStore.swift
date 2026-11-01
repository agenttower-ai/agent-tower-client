import Flutter
import Security

enum CredentialStore {
    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "com.agenttower.mobile/credentials", binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.agenttower.mobile",
                kSecAttrAccount as String: "connection.v1"
            ]
            func failure(_ status: OSStatus) {
                result(FlutterError(code: "secure_storage", message: "Keychain operation failed (\(status))", details: nil))
            }
            switch call.method {
            case "readLanguage":
                result(UserDefaults.standard.string(forKey: "agenttower.language"))
            case "writeLanguage":
                guard let text = call.arguments as? String else { result(FlutterError(code: "preferences", message: "Invalid language", details: nil)); return }
                UserDefaults.standard.set(text, forKey: "agenttower.language")
                result(nil)
            case "readProjectPreferences":
                result(UserDefaults.standard.string(forKey: "agenttower.project_preferences"))
            case "writeProjectPreferences":
                guard let text = call.arguments as? String else { result(FlutterError(code: "preferences", message: "Invalid preferences", details: nil)); return }
                UserDefaults.standard.set(text, forKey: "agenttower.project_preferences")
                result(nil)
            case "read":
                var read = query
                read[kSecReturnData as String] = true
                read[kSecMatchLimit as String] = kSecMatchLimitOne
                var value: CFTypeRef?
                let status = SecItemCopyMatching(read as CFDictionary, &value)
                if status == errSecItemNotFound { result(nil) }
                else if status == errSecSuccess, let data = value as? Data, let text = String(data: data, encoding: .utf8) { result(text) }
                else { failure(status) }
            case "write":
                guard let text = call.arguments as? String, let data = text.data(using: .utf8) else {
                    result(FlutterError(code: "argument", message: "Expected credential string", details: nil)); return
                }
                let changes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
                var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
                if status == errSecItemNotFound {
                    var item = query
                    changes.forEach { item[$0.key] = $0.value }
                    status = SecItemAdd(item as CFDictionary, nil)
                }
                if status == errSecSuccess { result(nil) } else { failure(status) }
            case "clear":
                let status = SecItemDelete(query as CFDictionary)
                if status == errSecSuccess || status == errSecItemNotFound { result(nil) } else { failure(status) }
            default: result(FlutterMethodNotImplemented)
            }
        }
    }
}
