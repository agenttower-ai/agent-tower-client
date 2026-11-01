import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    CredentialStore.register(with: engineBridge.applicationRegistrar.messenger())
    FlutterMethodChannel(name: "com.agenttower.mobile/project-links", binaryMessenger: engineBridge.applicationRegistrar.messenger())
      .setMethodCallHandler { call, result in
        guard call.method == "openLink" else { result(FlutterMethodNotImplemented); return }
        guard let value = call.arguments as? String,
          let url = URL(string: value) else {
          result(FlutterError(code: "project_link", message: "Invalid project link", details: nil)); return
        }
        let web = url.scheme == "https" && !(url.host ?? "").isEmpty && url.user == nil && url.password == nil
        let email = value.range(of: "^mailto:[^\\s@]+@[^\\s@]+$", options: .regularExpression) != nil
        guard web || email else {
          result(FlutterError(code: "project_link", message: "Invalid project link", details: nil)); return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
          if opened { result(nil) }
          else { result(FlutterError(code: "project_link", message: "Unable to open project link", details: nil)) }
        }
      }
  }
}
