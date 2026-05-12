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
            Image(nsImage: TuttiPulseIcon.image(active: !manager.isMuted))
        }
        .menuBarExtraStyle(.window)
    }
}
