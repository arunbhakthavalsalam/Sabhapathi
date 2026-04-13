import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        PythonBackendManager.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        PythonBackendManager.shared.stop()
        AudioEngineService.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
