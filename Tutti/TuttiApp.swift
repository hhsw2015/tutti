import SwiftUI

@main
struct TuttiApp: App {
    @StateObject private var manager = AudioDeviceManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(manager)
        } label: {
            Image(nsImage: TuttiPulseIcon.image(level: iconLevel))
        }
        .menuBarExtraStyle(.window)
    }

    private var iconLevel: Int {
        if manager.isMuted { return 0 }
        let v = manager.masterVolume
        if v <= 0 { return 0 }
        return v > 0.5 ? 2 : 1
    }
}
