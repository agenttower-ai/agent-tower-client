import Cocoa
import FlutterMacOS
import Security

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerPlatformChannels(with: flutterViewController.engine.binaryMessenger)
    self.minSize = NSSize(width: 400, height: 640)

    super.awakeFromNib()
  }

  private func registerPlatformChannels(with messenger: FlutterBinaryMessenger) {
    let credentials = FlutterMethodChannel(name: "com.agenttower.mobile/credentials", binaryMessenger: messenger)
    credentials.setMethodCallHandler { call, result in
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.agenttower.macos",
        kSecAttrAccount as String: "connection.v1"
      ]
      func failure(_ status: OSStatus) {
        result(FlutterError(code: "secure_storage", message: "Keychain operation failed (\(status))", details: nil))
      }
      switch call.method {
      case "readLanguage":
        result(UserDefaults.standard.string(forKey: "agenttower.language"))
      case "writeLanguage", "writeProjectPreferences":
        guard let text = call.arguments as? String else {
          result(FlutterError(code: "preferences", message: "Invalid preferences", details: nil)); return
        }
        let key = call.method == "writeLanguage" ? "agenttower.language" : "agenttower.project_preferences"
        UserDefaults.standard.set(text, forKey: key)
        result(nil)
      case "readProjectPreferences":
        result(UserDefaults.standard.string(forKey: "agenttower.project_preferences"))
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
        let changes: [String: Any] = [kSecValueData as String: data]
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
    let links = FlutterMethodChannel(name: "com.agenttower.mobile/project-links", binaryMessenger: messenger)
    links.setMethodCallHandler { call, result in
      guard call.method == "openLink" else { result(FlutterMethodNotImplemented); return }
      guard let value = call.arguments as? String, let url = URL(string: value) else {
        result(FlutterError(code: "project_link", message: "Invalid project link", details: nil)); return
      }
      let web = url.scheme == "https" && !(url.host ?? "").isEmpty && url.user == nil && url.password == nil
      let email = value.range(of: "^mailto:[^\\s@]+@[^\\s@]+$", options: .regularExpression) != nil
      guard web || email else {
        result(FlutterError(code: "project_link", message: "Invalid project link", details: nil)); return
      }
      if NSWorkspace.shared.open(url) { result(nil) }
      else { result(FlutterError(code: "project_link", message: "Unable to open project link", details: nil)) }
    }
  }
}
