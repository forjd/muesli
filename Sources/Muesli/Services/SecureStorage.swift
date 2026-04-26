import CryptoKit
import Foundation
import Security

protocol SecureStorageKeyProvider {
    func storageKey() throws -> SymmetricKey
}

enum SecureStorageError: LocalizedError {
    case invalidEncryptedData
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidEncryptedData:
            "Encrypted storage data is invalid."
        case let .keychainReadFailed(status):
            "Could not read the local storage encryption key from Keychain (\(status))."
        case let .keychainWriteFailed(status):
            "Could not save the local storage encryption key to Keychain (\(status))."
        }
    }
}

struct SecureStorage {
    private static let header = Data("MUESLIENC1".utf8)

    private let keyProvider: SecureStorageKeyProvider

    init(keyProvider: SecureStorageKeyProvider = KeychainStorageKeyProvider()) {
        self.keyProvider = keyProvider
    }

    func isEncrypted(_ data: Data) -> Bool {
        data.starts(with: Self.header)
    }

    func encrypt(_ data: Data) throws -> Data {
        let key = try keyProvider.storageKey()
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw SecureStorageError.invalidEncryptedData
        }
        return Self.header + combined
    }

    func decrypt(_ data: Data) throws -> Data {
        guard isEncrypted(data) else { return data }
        let encryptedPayload = data.dropFirst(Self.header.count)
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedPayload)
        return try AES.GCM.open(sealedBox, using: keyProvider.storageKey())
    }

    func encryptFile(at url: URL) throws {
        let data = try Data(contentsOf: url)
        guard !isEncrypted(data) else { return }
        try encrypt(data).write(to: url, options: [.atomic])
    }

    func decryptedTemporaryFile(from url: URL, fileExtension: String = "wav") throws -> URL {
        let data = try Data(contentsOf: url)
        let decrypted = try decrypt(data)
        let temporaryURL = FileManager.default.temporaryDirectory
            .appending(path: "Muesli-\(UUID().uuidString).\(fileExtension)")
        try decrypted.write(to: temporaryURL, options: [.atomic])
        return temporaryURL
    }
}

struct KeychainStorageKeyProvider: SecureStorageKeyProvider {
    private let service = "com.local.Muesli.secure-storage"
    private let account = "storage-encryption-key"

    func storageKey() throws -> SymmetricKey {
        if let existingKeyData = try readKeyData() {
            return SymmetricKey(data: existingKeyData)
        }

        var keyData = Data(count: 32)
        let status = keyData.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw SecureStorageError.keychainWriteFailed(status)
        }

        try saveKeyData(keyData)
        return SymmetricKey(data: keyData)
    }

    private func readKeyData() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SecureStorageError.keychainReadFailed(status)
        }
        return result as? Data
    }

    private func saveKeyData(_ data: Data) throws {
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureStorageError.keychainWriteFailed(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
