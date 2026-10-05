import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = NotchWindowController()
        controller?.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.prepareToQuit()
    }
}
