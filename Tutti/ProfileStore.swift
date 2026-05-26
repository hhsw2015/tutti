import Foundation

struct Profile: Codable, Identifiable {
    var id = UUID()
    var name: String
    var deviceUIDs: [String]
}

@MainActor
final class ProfileStore: ObservableObject {
    @Published var profiles: [Profile] = [] {
        didSet { save() }
    }

    private let storageKey = "profiles"

    init() { load() }

    func add(name: String, uids: [String]) {
        profiles.append(Profile(name: name, deviceUIDs: uids))
    }

    func delete(_ profile: Profile) {
        profiles.removeAll { $0.id == profile.id }
    }

    func rename(_ profile: Profile, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx].name = trimmed
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Profile].self, from: data) else { return }
        profiles = decoded
    }
}
