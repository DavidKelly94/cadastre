import Foundation
import Security

/// The store's pairing code (ADR-0029), kept in the Keychain.
///
/// It is what lets a device put files in the PC's inbox, so it does not belong
/// in `UserDefaults`, which travels with backups in the clear. One generic
/// password item, readable after the first unlock so a send started with the
/// phone in a pocket can still read it.
enum PairingCode {
  private static let service = "ai.vividhome.app.pc"
  private static let account = "pairing-code"

  private static var base: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  static func read() -> String? {
    var query = base
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// Store the code, or remove it when given nothing but whitespace.
  static func write(_ code: String) {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      SecItemDelete(base as CFDictionary)
      return
    }
    let data = Data(trimmed.utf8)
    let update: [String: Any] = [kSecValueData as String: data]
    let status = SecItemUpdate(base as CFDictionary, update as CFDictionary)
    if status == errSecItemNotFound {
      var add = base
      add[kSecValueData as String] = data
      add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      SecItemAdd(add as CFDictionary, nil)
    }
  }
}
