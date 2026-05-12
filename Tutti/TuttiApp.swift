import SwiftUI

@main
struct TuttiApp: App {
    @StateObject private var manager = AudioDeviceManager()
    @StateObject private var presets = PresetStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(manager)
                .environmentObject(presets)
        } label: {
            Label("Tutti", systemImage: manager.isActive ? "speaker.wave.2.fill" : "speaker.fill")
                .labelStyle(.iconOnly)
        }
        .menuBarExtraStyle(.window)
    }
}
