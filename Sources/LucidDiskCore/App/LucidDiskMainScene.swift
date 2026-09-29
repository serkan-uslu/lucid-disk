import SwiftUI

/// The main window, menus and Settings, shared by every edition's `@main` app.
/// An edition installs its `LucidDiskExtension` before this scene is created
/// and may add scenes of its own next to it.
public struct LucidDiskMainScene: Scene {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1_050, minHeight: 640)
                .tint(Theme.accent)
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Lucid Disk") { AppSupport.shared.show(.about) }
            }
            CommandGroup(replacing: .help) {
                Button("How to Use") { AppSupport.shared.show(.guide) }
                    .keyboardShortcut("/", modifiers: [.command, .shift])
                Button("Keyboard Shortcuts") { AppSupport.shared.show(.shortcuts) }
                Button("Privacy & Safety") { AppSupport.shared.show(.privacy) }
            }
        }

        Settings {
            SettingsView()
        }
    }
}
