import Flutter
import UIKit

/// Device signals for Prembly Transaction Monitoring. Hosted workflows run in a Flutter WebView and
/// need nothing from this class.
///
/// Every result is a JSON string (the same shape prembly-tm-native returns), so the Dart side parses
/// one format on both platforms.
public class PremblyPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "prembly/tm", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(PremblyPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getAppInfo":
      result(Self.json(SignalCollector.appInfo()))

    case "getDeviceId":
      // Off the main thread: the Keychain read can block.
      DispatchQueue.global(qos: .utility).async {
        let id = DeviceIdStore.deviceId()
        DispatchQueue.main.async { result(id) }
      }

    case "collectSignals":
      let includeLocation = (call.arguments as? [String: Any])?["includeLocation"] as? Bool ?? false
      // Off the main thread: the checks touch the file system. The collector hops to the main
      // thread itself for the few UIKit and CoreLocation reads.
      DispatchQueue.global(qos: .utility).async {
        let json = Self.json(SignalCollector.collect(includeLocation: includeLocation))
        DispatchQueue.main.async { result(json) }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func json(_ object: Any) -> String {
    guard JSONSerialization.isValidJSONObject(object),
      let data = try? JSONSerialization.data(withJSONObject: object),
      let text = String(data: data, encoding: .utf8)
    else { return "{}" }
    return text
  }
}
