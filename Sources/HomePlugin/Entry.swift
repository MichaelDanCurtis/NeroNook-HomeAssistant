import AppKit
@main struct HomeEntry {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = HomeModule()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
