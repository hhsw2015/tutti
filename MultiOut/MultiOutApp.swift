import SwiftUI

@main
struct MultiOutApp: App {
    @StateObject private var manager = AudioDeviceManager()
    @StateObject private var presets = PresetStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(manager)
                .environmentObject(presets)
        } label: {
            Label("MultiOut", systemImage: manager.isActive ? "speaker.wave.2.fill" : "speaker.fill")
                .labelStyle(.iconOnly)
        }
        .menuBarExtraStyle(.window)
    }
}
