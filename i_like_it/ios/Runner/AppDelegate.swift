import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let CHANNEL = "shared_link"
  private let APP_GROUP = "group.com.ilikeit.app"
  private let SHARED_KEY = "sharedText"
  private var methodChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // Clear any stale sharedText left from previous app builds
    // (old flow used this key; new native Share Extension uses pendingSaveLink instead)
    if let defaults = UserDefaults(suiteName: APP_GROUP) {
      defaults.removeObject(forKey: SHARED_KEY)
      defaults.synchronize()
    }

    if methodChannel == nil, let controller = window?.rootViewController as? FlutterViewController {
      setupChannel(messenger: controller.binaryMessenger)
    }

    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SharedLinkPlugin") {
      setupChannel(messenger: registrar.messenger())
    }
  }

  private func setupChannel(messenger: FlutterBinaryMessenger) {
    guard methodChannel == nil else { return }
    let channel = FlutterMethodChannel(name: CHANNEL, binaryMessenger: messenger)
    self.methodChannel = channel

    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else { return }
      let defaults = UserDefaults(suiteName: self.APP_GROUP)

      switch call.method {
      case "getSharedText":
        let sharedText = defaults?.string(forKey: self.SHARED_KEY)
        result(sharedText)
      case "clearSharedText":
        defaults?.removeObject(forKey: self.SHARED_KEY)
        defaults?.synchronize()
        result(nil)
      case "closeApp":
        UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
        result(nil)
      case "saveFolders":
        // Flutter sends a JSON string of folders so the Share Extension can display them
        if let jsonString = call.arguments as? String {
          defaults?.set(jsonString, forKey: "cachedFolders")
          defaults?.synchronize()
        }
        result(nil)
      case "getPendingSave":
        // Share Extension may save a link directly; main app retrieves it here
        let pending = defaults?.string(forKey: "pendingSaveLink")
        let pendingFolder = defaults?.string(forKey: "pendingSaveFolderId")
        if let link = pending {
          result(["link": link, "folderId": pendingFolder ?? ""])
        } else {
          result(nil)
        }
      case "clearPendingSave":
        defaults?.removeObject(forKey: "pendingSaveLink")
        defaults?.removeObject(forKey: "pendingSaveFolderId")
        defaults?.synchronize()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme?.lowercased() == "ilikeit" && (url.host?.lowercased() == "share" || url.absoluteString.contains("share")) {
      let defaults = UserDefaults(suiteName: APP_GROUP)
      if let sharedText = defaults?.string(forKey: SHARED_KEY) {
        methodChannel?.invokeMethod("sharedText", arguments: sharedText)
      }
    }
    return super.application(app, open: url, options: options)
  }
}
