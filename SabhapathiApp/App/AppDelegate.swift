import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if !AppFlags.allServicesNative {
            PythonBackendManager.shared.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if !AppFlags.allServicesNative {
            PythonBackendManager.shared.stop()
        }
        AudioEngineService.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
