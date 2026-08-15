import Foundation
import Security
import CryptoKit

/// Stores and verifies the unlock password.
///
/// The password itself is never persisted. Instead we generate a random salt,
/// hash `salt + password` with SHA-256, and store `salt || hash` as a single
/// blob in the user's Keychain. Verification re-hashes the candidate password
/// with the stored salt and compares digests.
enum PasswordStore {

    private static let service = "com.jugomo.keylocker"
    private static let account = "unlock-password"
    private static let saltLength = 16

    /// Returns true if an unlock password has already been configured.
    static func hasPasswordSet() -> Bool {
        readBlob() != nil
    }

    /// Hashes and stores `password`, replacing any previously stored password.
    @discardableResult
    static func setPassword(_ password: String) -> Bool {
        var salt = Data(count: saltLength)
        let result = salt.withUnsafeMutableBytes { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, saltLength, base)
        }
        guard result == errSecSuccess else { return false }

        let digest = hash(password: password, salt: salt)
        let blob = salt + digest
        return writeBlob(blob)
    }

    /// Returns true if `password` matches the stored password.
    static func verify(_ password: String) -> Bool {
        guard let blob = readBlob(), blob.count > saltLength else { return false }
        let salt = blob.prefix(saltLength)
        let storedDigest = blob.suffix(from: saltLength)
        let candidateDigest = hash(password: password, salt: Data(salt))
        // Constant-time-ish comparison via CryptoKit's Digest Equatable
        // conformance is not directly usable across Data, so compare bytes.
        return candidateDigest.count == storedDigest.count
            && timingSafeEqual(candidateDigest, Data(storedDigest))
    }

    /// Removes any stored password.
    static func clearPassword() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Hashing

    private static func hash(password: String, salt: Data) -> Data {
        var input = salt
        input.append(Data(password.utf8))
        let digest = SHA256.hash(data: input)
        return Data(digest)
    }

    private static func timingSafeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(lhs, rhs) {
            diff |= a ^ b
        }
        return diff == 0
    }

    // MARK: - Keychain

    private static func readBlob() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    private static func writeBlob(_ blob: Data) -> Bool {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // Try update first; if no item exists yet, add one.
        let attributesToUpdate: [String: Any] = [kSecValueData as String: blob]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = blob
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }
}
