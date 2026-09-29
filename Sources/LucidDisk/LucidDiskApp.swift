import SwiftUI

@main
struct LucidDiskApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1_050, minHeight: 640)
                .tint(Color(red: 0.15, green: 0.68, blue: 0.78))
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
    }
}
