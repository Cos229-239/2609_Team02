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

    // Device time zone (IANA id, e.g. "America/Chicago") for the household's
    // 9 AM reminders. Read by lib/core/services/time_zone_service.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FamotiveTimeZone") {
      let channel = FlutterMethodChannel(name: "famotive/timezone", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        if call.method == "getLocalTimeZone" {
          result(TimeZone.current.identifier)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
