import Foundation

struct Preset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var deviceUIDs: [String]
}

final class PresetStore: ObservableObject {
    @Published var presets: [Preset] = [] {
        didSet { save() }
    }

    init() { load() }

    func add(name: String, uids: [String]) {
        presets.append(Preset(name: name, deviceUIDs: uids))
    }

    func delete(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: "presets")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "presets"),
              let decoded = try? JSONDecoder().decode([Preset].self, from: data) else { return }
        presets = decoded
    }
}
