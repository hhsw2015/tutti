import AppKit
import Foundation
import IOKit
import Security
import SystemConfiguration

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
    /// Last successfully activated key on this Mac. Preserved across
    /// deactivate so the activate form can re-fill itself — saves the user
    /// from digging the key out of their email again to reactivate.
    @Published private(set) var lastUsedKey: String?

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
    private let keychainServiceLastUsed = "license_key_last_used"
    private let lastValidatedKey = "tutti.license.lastValidatedAt"

    private init() {
        // Backfill: if a key is already active but the convenience slot is
        // empty (e.g. the user activated on a pre-prefill build), promote
        // the active key now so deactivate→reactivate works for them too.
        if readKeychain(service: keychainServiceLastUsed) == nil,
           let active = readKeychain(service: keychainServiceKey) {
            try? saveKeychain(service: keychainServiceLastUsed, value: active)
        }
        lastUsedKey = readKeychain(service: keychainServiceLastUsed)
        recomputeStatusFromStorage()
        Task { await refreshIfPossible() }
    }

    // MARK: - Public API

    func activate(licenseKey raw: String) async throws {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw LicenseError.invalidKey }

        // Free any previously-bound instance on this Mac before claiming a new
        // one — otherwise repeated activate() calls (rebinds, retries after a
        // partial failure) silently leak activation slots on the server.
        if let oldKey = readKeychain(service: keychainServiceKey),
           let oldInstance = readKeychain(service: keychainServiceInstance) {
            let cleanup: [String: String] = [
                "license_key": oldKey,
                "license_key_instance_id": oldInstance,
            ]
            _ = try? await postEmpty("/licenses/deactivate", body: cleanup)
        }

        struct Response: Decodable { let id: String }
        let body: [String: String] = ["license_key": key, "name": deviceName()]
        let response: Response = try await post("/licenses/activate", body: body)

        try saveKeychain(service: keychainServiceKey, value: key)
        try saveKeychain(service: keychainServiceInstance, value: response.id)
        // Convenience prefill, kept across deactivate. Best-effort: a
        // failure here is harmless, the user just retypes.
        try? saveKeychain(service: keychainServiceLastUsed, value: key)
        lastUsedKey = key
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

        // Preserve the user-pasted key for one-click reactivation later.
        // clearStorage() only wipes the active credentials; the convenience
        // slot survives so the activate form re-fills itself.
        try? saveKeychain(service: keychainServiceLastUsed, value: key)
        lastUsedKey = key

        clearStorage()
        status = .inactive
    }

    /// 启动时调用，能联网就 validate，失败就保留宽限期状态。
    func refreshIfPossible() async {
        guard readKeychain(service: keychainServiceKey) != nil else { return }
        try? await validate()
    }

    /// Copy the full active license key (not the masked form) to the
    /// pasteboard. Returns false if no active key is stored.
    @discardableResult
    func copyKeyToPasteboard() -> Bool {
        guard let key = readKeychain(service: keychainServiceKey) else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key, forType: .string)
        return true
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
        // Clamp future timestamps to 0 so clock skew (manual change or NTP
        // correction) can't extend the grace period.
        let days = max(0, daysBetween(lastValidated, Date()))
        if days <= activeWindowDays {
            status = .activated
        } else if days <= gracePeriodDays {
            // +1 so the last legal grace day reads "1 day left", not "0".
            status = .offlineGrace(daysLeft: gracePeriodDays - days + 1)
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
            throw LicenseError.network(String(localized: "解码失败：\(error.localizedDescription)"))
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
            throw LicenseError.network(String(localized: "无效响应"))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw parseError(data: data, status: http.statusCode)
        }
        return data
    }

    private func parseError(data: Data, status: Int) -> LicenseError {
        // Prefer the structured error code DodoPayments returns so we don't
        // misclassify on substring collisions like "invalid token" (auth) or
        // "rate limit" (throttle).
        struct ErrorBody: Decodable { let code: String? }
        let code = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.code ?? ""

        switch code {
        case "LICENSE_KEY_LIMIT_REACHED":
            return .activationLimitReached
        case "LICENSE_KEY_NOT_FOUND",
             "LICENSE_KEY_INVALID",
             "LICENSE_KEY_REVOKED",
             "LICENSE_KEY_EXPIRED":
            return .invalidKey
        default:
            break
        }

        // No structured code — fall back to status-only classification. 404 is
        // the only one DodoPayments uses for "key not found" reliably; treat
        // 400 the same since the server returns it for empty/malformed keys.
        if status == 404 || status == 400 {
            return .invalidKey
        }
        return .network(String(localized: "HTTP \(status)"))
    }

    // MARK: - Device identity

    private func deviceName() -> String {
        // SCDynamicStoreCopyComputerName returns the user-set "Computer Name"
        // from System Settings → General → About, which is the same name shown
        // in the DodoPayments dashboard for the activation. ProcessInfo's
        // hostName can return a network-derived "localhost.local" form.
        let host = (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
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
                throw LicenseError.network(String(localized: "Keychain 写入失败 (\(Int(addStatus)))"))
            }
        } else if status != errSecSuccess {
            throw LicenseError.network(String(localized: "Keychain 更新失败 (\(Int(status)))"))
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
