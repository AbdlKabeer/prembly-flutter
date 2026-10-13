import Foundation
import Security

/// The app-scoped device ID. Created on first use and kept in the Keychain, marked "this device
/// only", so it survives an app reinstall but is not copied to another device by a backup.
/// Ported from prembly-tm-native (TMDeviceIdStore).
enum DeviceIdStore {
  private static let service = "com.prembly.tmsdk.device"
  private static let account = "device_id"
  private static let lock = NSLock()

  private static var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  private static func storedId() -> String? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data,
      let value = String(data: data, encoding: .utf8),
      !value.isEmpty
    else { return nil }
    return value
  }

  static func deviceId() -> String {
    lock.lock()
    defer { lock.unlock() }

    if let existing = storedId() { return existing }

    let fresh = UUID().uuidString.lowercased()
    var attributes = baseQuery
    attributes[kSecValueData as String] = Data(fresh.utf8)
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    // If the Keychain is unavailable the ID is simply not kept: the next call makes a new one.
    SecItemAdd(attributes as CFDictionary, nil)
    return fresh
  }
}
