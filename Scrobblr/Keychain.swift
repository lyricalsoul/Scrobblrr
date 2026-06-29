//
//  Keychain.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//

import Foundation
import Security
import os

enum Keychain {
    private static let service = "io.lyricalsoul.Scrobblrr.credentials"

    static func set(_ value: String?, for account: String) {
        guard let value, let data = value.data(using: .utf8) else {
            remove(account)
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                Logger.keychain.error("SecItemAdd(\(account, privacy: .public)) failed: \(addStatus)")
            }
        } else if status != errSecSuccess {
            Logger.keychain.error("SecItemUpdate(\(account, privacy: .public)) failed: \(status)")
        }
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecSuccess && status != errSecItemNotFound {
                Logger.keychain.error("SecItemCopyMatching(\(account, privacy: .public)) failed: \(status)")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
