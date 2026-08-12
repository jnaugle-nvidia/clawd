import AppKit
import Darwin

// Only one Clawd at a time. A held flock on a file under the settings directory is the
// mac spelling of the named mutex the Windows build takes: the kernel drops it when the
// process dies, however it dies.
private func TakeSingleInstanceLock() -> Bool
{
    try? FileManager.default.createDirectory(at: Settings.Dir, withIntermediateDirectories: true)
    let path = Settings.Dir.appendingPathComponent("instance.lock").path
    let fd = open(path, O_CREAT | O_RDWR, 0o644)
    if fd < 0 { return true }                      // can't lock: better to run than not to
    if flock(fd, LOCK_EX | LOCK_NB) != 0 { close(fd); return false }
    lockFd = fd                                    // held for the life of the process
    return true
}

private var lockFd: Int32 = -1

final class AppDelegate: NSObject, NSApplicationDelegate
{
    private var overlay: Overlay?
    private var tray: Tray?

    func applicationDidFinishLaunching(_ note: Notification)
    {
        Native.Start()

        let cfg = Settings.Load()
        let watcher = WindowWatcher()
        watcher.Poll()

        let overlay = Overlay(cfg, watcher)
        let tray = Tray(cfg, overlay)
        overlay.MenuRequested = { [weak tray] in tray?.ShowMenu() }

        self.overlay = overlay
        self.tray = tray

        if !cfg.Paused
        {
            overlay.Show()
            overlay.Pet.SayText("hi :)", 3.2)
        }
    }

    func applicationWillTerminate(_ note: Notification)
    {
        tray?.Dispose()
    }
}

if !TakeSingleInstanceLock() { exit(0) }            // already running

let app = NSApplication.shared
app.setActivationPolicy(.accessory)                 // no Dock icon, no app menu
let delegate = AppDelegate()
app.delegate = delegate
app.run()
