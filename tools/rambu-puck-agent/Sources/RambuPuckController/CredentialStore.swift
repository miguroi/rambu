import Foundation
import Security

public struct PuckCredential: Codable, Equatable, Sendable {
    public let puckID: String
    public let familyID: String
    public let displayName: String
    public let accessToken: String

    public init(puckID: String, familyID: String, displayName: String, accessToken: String) {
        self.puckID = puckID
        self.familyID = familyID
        self.displayName = displayName
        self.accessToken = accessToken
    }
}

public protocol PuckCredentialStoring: Sendable {
    func load() throws -> PuckCredential?
    func save(_ credential: PuckCredential) throws
    func clear() throws
}

public struct PuckCredentialStoreError: Error, CustomStringConvertible, Sendable {
    public let operation: String
    public let status: OSStatus

    public var description: String {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return "Keychain \(operation) failed: \(detail)"
    }
}

public final class PuckCredentialStore: PuckCredentialStoring, @unchecked Sendable {
    private let service: String
    private let account: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(service: String = "id.rambu.puck.controller", account: String = "paired-puck") {
        self.service = service
        self.account = account
    }

    public func load() throws -> PuckCredential? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw PuckCredentialStoreError(operation: "load", status: status)
        }
        return try decoder.decode(PuckCredential.self, from: data)
    }

    public func save(_ credential: PuckCredential) throws {
        let data = try encoder.encode(credential)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let deleteStatus = SecItemDelete(baseQuery as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw PuckCredentialStoreError(operation: "replace", status: deleteStatus)
        }
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PuckCredentialStoreError(operation: "save", status: status)
        }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PuckCredentialStoreError(operation: "clear", status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
