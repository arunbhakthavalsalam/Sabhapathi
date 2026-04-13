import SwiftUI

@main
struct SabhapathiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var projectManager = ProjectManager.shared
    @StateObject private var backendManager = PythonBackendManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(projectManager)
                .environmentObject(backendManager)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import MP3...") {
                    NotificationCenter.default.post(name: .importMP3, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let importMP3 = Notification.Name("importMP3")
}
