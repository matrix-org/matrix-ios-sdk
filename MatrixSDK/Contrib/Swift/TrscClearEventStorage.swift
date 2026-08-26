//
// Copyright 2026 TRSC contributors.
// SPDX-License-Identifier: Apache-2.0
//

import CryptoKit
import Foundation
import Security

/// Seals decrypted-event JSON before it is written into the file store, and
/// opens it again on load.
///
/// Why it exists: Android persists the decryption result next to the event in
/// an encrypted Realm, so a cold start reads plaintext history instantly. The
/// iOS `MXFileStore` is NOT encrypted — persisting `clearEvent` verbatim would
/// put E2EE plaintext on disk in the open, which is exactly what E2EE exists
/// to prevent. So the persisted copy is sealed with AES-GCM under a random
/// 256-bit key that lives in the keychain
/// (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, never synced): the
/// protection parity of Android's Keystore-held Realm key.
///
/// Failure is always graceful: a missing key (fresh install, an extension
/// without keychain access) or an unreadable box just means "no cached
/// decryption" — the session decrypts the event again, same as before this
/// class existed.
@objc(MXTrscClearEventStorage)
public final class MXTrscClearEventStorage: NSObject {

    @objc public static let shared = MXTrscClearEventStorage()

    private let keychainService = "trsc.clear-event.storage"
    private let keychainAccount = "aes-key"
    private let queue = DispatchQueue(label: "trsc.clear-event.storage")
    private var cachedKey: SymmetricKey?

    @objc public func protect(_ json: [AnyHashable: Any]) -> Data? {
        guard let key = loadOrCreateKey(),
              JSONSerialization.isValidJSONObject(json),
              let plain = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? AES.GCM.seal(plain, using: key).combined
    }

    @objc public func unprotect(_ sealed: Data) -> [AnyHashable: Any]? {
        guard let key = loadOrCreateKey(),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let plain = try? AES.GCM.open(box, using: key) else { return nil }
        return (try? JSONSerialization.jsonObject(with: plain)) as? [AnyHashable: Any]
    }

    private func loadOrCreateKey() -> SymmetricKey? {
        queue.sync {
            if let cachedKey { return cachedKey }

            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainAccount,
                kSecReturnData as String: true,
            ]
            var item: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
               let data = item as? Data, data.count == 32 {
                let key = SymmetricKey(data: data)
                cachedKey = key
                return key
            }

            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
            let data = Data(bytes)
            let add: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainAccount,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                kSecValueData as String: data,
            ]
            let status = SecItemAdd(add as CFDictionary, nil)
            if status == errSecDuplicateItem {
                // Lost the race to another process (NSE): read theirs so both
                // sides seal with ONE key — two keys would silently corrupt
                // each other's boxes forever.
                if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                   let raced = item as? Data, raced.count == 32 {
                    let key = SymmetricKey(data: raced)
                    cachedKey = key
                    return key
                }
                return nil
            }
            guard status == errSecSuccess else { return nil }
            let key = SymmetricKey(data: data)
            cachedKey = key
            return key
        }
    }
}
