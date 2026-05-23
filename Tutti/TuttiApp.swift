import SwiftUI

@main
struct TuttiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Must run before any UI renders so SwiftUI / NSWindow titles pick up
        // the user's chosen language. UserDefaults writes here are committed
        // synchronously, so the value is visible to Foundation's locale lookup.
        AppearancePrefs.applySavedLanguageAtStartup()
    }

    var body: some Scene {
        Settings { EmptyView() }
    }
}
