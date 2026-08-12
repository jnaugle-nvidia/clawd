import AppKit
import CoreGraphics

public final class DeskWindow
{
    public var Id: CGWindowID = 0
    public var Pid: pid_t = 0
    public var R = ScreenRect()
    public var Owner = ""       // the application's name, straight from the window server
    public var Title = ""       // only populated if Screen Recording has been granted

    // Windows has to dig the app's name out of the title bar text; the window server
    // hands it over directly, so there is nothing to parse.
    public var AppName: String
    {
        var s = Owner.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return "" }
        if s.count > 24 { s = String(s.prefix(23)).trimmingCharacters(in: .whitespaces) + "…" }
        return s
    }
}

// Keeps a live picture of the visible top-level windows on the desktop.
//
// CGWindowListCopyWindowInfo reports every window's owner, layer and bounds without any
// permission at all. Window *titles* need Screen Recording, so this never asks for one —
// the pet only ever needed a name to say out loud, and the owner name is a better one.
public final class WindowWatcher
{
    public var Windows: [DeskWindow] = []
    public var Foreground: CGWindowID = 0

    public var ForegroundChanged: ((DeskWindow) -> Void)?

    private let ownPid = ProcessInfo.processInfo.processIdentifier

    // The desktop furniture that lives on layer 0 alongside real windows.
    private static let SkipOwners: Set<String> =
    [
        "Window Server", "Dock", "SystemUIServer", "Control Center", "Notification Center",
        "Spotlight", "Wallpaper", "WindowManager", "universalaccessd", "Screenshot"
    ]

    public init() { }

    // Rescan. Cheap enough to call a few times a second.
    public func Poll()
    {
        var found: [DeskWindow] = []
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

        if let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]]
        {
            // The list arrives front-to-back, which is the order the foreground pick wants.
            for d in list
            {
                guard let w = Convert(d) else { continue }
                found.append(w)
            }
        }
        Windows = found

        // The frontmost application's topmost qualifying window. Switching apps changes it,
        // and so does raising a different window inside one app.
        var fg: CGWindowID = 0
        if let front = NSWorkspace.shared.frontmostApplication
        {
            let pid = front.processIdentifier
            if let w = found.first(where: { $0.Pid == pid }) { fg = w.Id }
        }

        if fg != Foreground
        {
            Foreground = fg
            if let dw = Find(fg), let cb = ForegroundChanged { cb(dw) }
        }
    }

    private func Convert(_ d: [String: Any]) -> DeskWindow?
    {
        guard (d[kCGWindowLayer as String] as? Int) == 0 else { return nil }     // normal windows only

        let pid = (d[kCGWindowOwnerPID as String] as? pid_t) ?? 0
        if pid == ownPid { return nil }

        let owner = (d[kCGWindowOwnerName as String] as? String) ?? ""
        if WindowWatcher.SkipOwners.contains(owner) { return nil }

        if let alpha = d[kCGWindowAlpha as String] as? Double, alpha < 0.05 { return nil }

        guard let bounds = d[kCGWindowBounds as String] as? [String: Any],
              let r = Rect(bounds) else { return nil }
        if r.Width < 220 || r.Height < 140 { return nil }

        let v = ScreenUtil.Virtual()
        if r.Right < v.Left || r.Left > v.Right || r.Bottom < v.Top || r.Top > v.Bottom { return nil }

        let w = DeskWindow()
        w.Id = (d[kCGWindowNumber as String] as? CGWindowID) ?? 0
        if w.Id == 0 { return nil }
        w.Pid = pid
        w.R = r
        w.Owner = owner
        w.Title = (d[kCGWindowName as String] as? String) ?? ""
        return w
    }

    // kCGWindowBounds is already flipped: origin top-left of the primary display, points.
    private func Rect(_ b: [String: Any]) -> ScreenRect?
    {
        guard let x = b["X"] as? Double, let y = b["Y"] as? Double,
              let w = b["Width"] as? Double, let h = b["Height"] as? Double else { return nil }
        let r = ScreenRect(left: x, top: y, right: x + w, bottom: y + h)
        return r.Valid ? r : nil
    }

    public func Find(_ id: CGWindowID) -> DeskWindow?
    {
        if id == 0 { return nil }
        for w in Windows where w.Id == id { return w }
        return nil
    }

    // Fresh bounds straight from the window server, so a perched pet rides along as the
    // window moves. Returns nil once the window closes, minimises or moves to another Space.
    public func TryLive(_ id: CGWindowID) -> ScreenRect?
    {
        if id == 0 { return nil }
        guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
              let d = list.first else { return nil }

        // kCGWindowIsOnscreen is simply absent for a minimised or hidden window.
        guard (d[kCGWindowIsOnscreen as String] as? Bool) == true else { return nil }
        guard let bounds = d[kCGWindowBounds as String] as? [String: Any] else { return nil }
        return Rect(bounds)
    }

    // A window worth visiting: usually the active one, sometimes another.
    public func PickInteresting() -> DeskWindow?
    {
        if Windows.isEmpty { return nil }
        if let fg = Find(Foreground), Double.random(in: 0 ..< 1) < 0.65 { return fg }
        return Windows[Int.random(in: 0 ..< Windows.count)]
    }
}
