import Foundation
import IOKit
import Security

@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    enum Status: Equatable {
        case inactive
        case activated
        case offlineGrace(daysLeft: Int)
        case expired
    }

    enum LicenseError: LocalizedError {
        case invalidKey
        case activationLimitReached
        case network(String)
        case noLicense

        var errorDescription: String? {
            switch self {
            case .invalidKey:
                return String(localized: "license key 无效或已被吊销")
            case .activationLimitReached:
                return String(localized: "已达激活上限（2 台设备）。请在旧设备的 Tutti 设置里停用后再试。")
            case .network(let msg):
                return String(localized: "网络错误：\(msg)")
            case .noLicense:
                return String(localized: "尚未激活")
            }
        }
    }

    @Published private(set) var status: Status = .inactive
    @Published private(set) var maskedKey: String?

    /// 唯一的 gate 判断。Pro 包含已激活和离线宽限期，过期则回到 free。
    var isPro: Bool {
        switch status {
        case .activated, .offlineGrace: return true
        case .inactive, .expired: return false
        }
    }

    /// 升级跳转地址。Landing page 上线前是占位。
    let purchaseURL = URL(string: "https://tutti.recents.com/buy")!

    private let baseURL: URL = {
        #if DEBUG
        return URL(string: "https://test.dodopayments.com")!
        #else
        return URL(string: "https://live.dodopayments.com")!
        #endif
    }()

    private let gracePeriodDays = 30
    private let activeWindowDays = 7
    private let keychainAccount = "tutti.license"
    private let keychainServiceKey = "license_key"
    private let keychainServiceInstance = "license_key_instance_id"
    private let lastValidatedKey = "tutti.license.lastValidatedAt"

    private init() {
        recomputeStatusFromStorage()
        Task { await refreshIfPossible() }
    }

    // MARK: - Public API

    func activate(licenseKey raw: String) async throws {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw LicenseError.invalidKey }

        struct Response: Decodable { let id: String }
        let body: [String: String] = ["license_key": key, "name": deviceName()]
        let response: Response = try await post("/licenses/activate", body: body)

        try saveKeychain(service: keychainServiceKey, value: key)
        try saveKeychain(service: keychainServiceInstance, value: response.id)
        UserDefaults.standard.set(Date(), forKey: lastValidatedKey)
        updateMaskedKey(key)
        status = .activated
    }

    func validate() async throws {
        guard let key = readKeychain(service: keychainServiceKey) else {
            throw LicenseError.noLicense
        }

        struct Response: Decodable { let valid: Bool }
        let body: [String: String] = ["license_key": key]
        let response: Response = try await post("/licenses/validate", body: body)

        if response.valid {
            UserDefaults.standard.set(Date(), forKey: lastValidatedKey)
            status = .activated
        } else {
            // 服务端明确告知失效（退款、人工吊销）— 清掉本地凭据
            clearStorage()
            status = .inactive
            throw LicenseError.invalidKey
        }
    }

    func deactivate() async throws {
        guard let key = readKeychain(service: keychainServiceKey),
              let instance = readKeychain(service: keychainServiceInstance) else {
            throw LicenseError.noLicense
        }
        let body: [String: String] = [
            "license_key": key,
            "license_key_instance_id": instance,
        ]
        _ = try await postEmpty("/licenses/deactivate", body: body)

        clearStorage()
        status = .inactive
    }

    /// 启动时调用，能联网就 validate，失败就保留宽限期状态。
    func refreshIfPossible() async {
        guard readKeychain(service: keychainServiceKey) != nil else { return }
        try? await validate()
    }

    // MARK: - Storage / Status

    private func recomputeStatusFromStorage() {
        guard let key = readKeychain(service: keychainServiceKey) else {
            status = .inactive
            maskedKey = nil
            return
        }
        updateMaskedKey(key)

        let lastValidated = (UserDefaults.standard.object(forKey: lastValidatedKey) as? Date) ?? .distantPast
        let days = daysBetween(lastValidated, Date())
        if days <= activeWindowDays {
            status = .activated
        } else if days <= gracePeriodDays {
            status = .offlineGrace(daysLeft: gracePeriodDays - days)
        } else {
            status = .expired
        }
    }

    private func daysBetween(_ a: Date, _ b: Date) -> Int {
        Calendar.current.dateComponents([.day], from: a, to: b).day ?? Int.max
    }

    private func updateMaskedKey(_ key: String) {
        let prefix = key.prefix(4)
        let suffix = key.suffix(4)
        maskedKey = "\(prefix)…\(suffix)"
    }

    private func clearStorage() {
        deleteKeychain(service: keychainServiceKey)
        deleteKeychain(service: keychainServiceInstance)
        UserDefaults.standard.removeObject(forKey: lastValidatedKey)
        maskedKey = nil
    }

    // MARK: - HTTP

    private func post<T: Decodable>(_ path: String, body: [String: String]) async throws -> T {
        let data = try await postRaw(path, body: body)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LicenseError.network("解码失败：\(error.localizedDescription)")
        }
    }

    private func postEmpty(_ path: String, body: [String: String]) async throws {
        _ = try await postRaw(path, body: body)
    }

    private func postRaw(_ path: String, body: [String: String]) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LicenseError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LicenseError.network("无效响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw parseError(data: data, status: http.statusCode)
        }
        return data
    }

    private func parseError(data: Data, status: Int) -> LicenseError {
        let raw = (String(data: data, encoding: .utf8) ?? "").lowercased()
        if raw.contains("limit") || raw.contains("max") {
            return .activationLimitReached
        }
        if raw.contains("invalid") || raw.contains("not found") || status == 404 || status == 400 {
            return .invalidKey
        }
        return .network("HTTP \(status)")
    }

    // MARK: - Device identity

    private func deviceName() -> String {
        let host = Host.current().localizedName ?? "Mac"
        let uuid = ioPlatformUUID()?.prefix(8) ?? "unknown"
        return "\(host) (\(uuid))"
    }

    private func ioPlatformUUID() -> String? {
        let dict = IOServiceMatching("IOPlatformExpertDevice")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, dict)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let cf = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)
        return cf?.takeRetainedValue() as? String
    }

    // MARK: - Keychain

    private func saveKeychain(service: String, value: String) throws {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount,
        ]
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw LicenseError.network("Keychain 写入失败 (\(addStatus))")
            }
        } else if status != errSecSuccess {
            throw LicenseError.network("Keychain 更新失败 (\(status))")
        }
    }

    private func readKeychain(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    private func deleteKeychain(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
