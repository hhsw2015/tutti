import Foundation
import SwiftUI

// TODO: replace with the real GitHub repo path before first release
private let githubRepo = "OWNER/tutti"

@MainActor
final class UpdateChecker: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(version: String, url: URL)
        case error(String)
    }

    @Published private(set) var status: Status = .idle
    @Published var autoCheckEnabled: Bool {
        didSet { UserDefaults.standard.set(autoCheckEnabled, forKey: "autoCheckUpdates") }
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var hasUpdate: Bool {
        if case .updateAvailable = status { return true }
        return false
    }

    init() {
        autoCheckEnabled = UserDefaults.standard.bool(forKey: "autoCheckUpdates")
        if autoCheckEnabled {
            Task { await check() }
        }
    }

    func check() async {
        status = .checking
        guard let endpoint = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest") else {
            status = .error("无效的更新地址")
            return
        }
        do {
            var request = URLRequest(url: endpoint)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                status = .error("无法连接到 GitHub")
                return
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let htmlString = json["html_url"] as? String,
                  let releaseURL = URL(string: htmlString) else {
                status = .error("解析失败")
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            if compareVersions(latest, currentVersion) > 0 {
                status = .updateAvailable(version: latest, url: releaseURL)
            } else {
                status = .upToDate
            }
        } catch {
            status = .error("检查失败")
        }
    }
}

private func compareVersions(_ a: String, _ b: String) -> Int {
    let aParts = a.split(separator: ".").compactMap { Int($0) }
    let bParts = b.split(separator: ".").compactMap { Int($0) }
    for i in 0..<max(aParts.count, bParts.count) {
        let av = i < aParts.count ? aParts[i] : 0
        let bv = i < bParts.count ? bParts[i] : 0
        if av > bv { return 1 }
        if av < bv { return -1 }
    }
    return 0
}
