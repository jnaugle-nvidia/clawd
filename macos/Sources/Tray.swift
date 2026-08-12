import AppKit
import ServiceManagement

// Menu-bar item and menu. The icon is drawn at runtime, so there are no image files.
public final class Tray: NSObject, NSMenuDelegate
{
    private let cfg: Settings
    private let overlay: Overlay
    private let item: NSStatusItem
    private let menu = NSMenu()

    private var miFollow: NSMenuItem!
    private var miPerch: NSMenuItem!
    private var miDance: NSMenuItem!
    private var miGlitch: NSMenuItem!
    private var miChatty: NSMenuItem!
    private var miThrough: NSMenuItem!
    private var miPause: NSMenuItem!
    private var miStartup: NSMenuItem!
    private var miSmall: NSMenuItem!
    private var miMedium: NSMenuItem!
    private var miLarge: NSMenuItem!

    public init(_ cfg: Settings, _ overlay: Overlay)
    {
        self.cfg = cfg
        self.overlay = overlay
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        menu.autoenablesItems = false
        menu.delegate = self

        let title = NSMenuItem(title: "Clawd", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        menu.addItem(Add("Come here", #selector(OnComeHere)))
        menu.addItem(Add("Say something", #selector(OnSay)))
        menu.addItem(Add("Dance!", #selector(OnDance)))
        menu.addItem(.separator())

        miFollow = Add("Follow my cursor", #selector(OnFollow))
        miPerch = Add("Perch on windows", #selector(OnPerch))
        miDance = Add("Dance to music", #selector(OnDanceToMusic))
        miGlitch = Add("Hologram glitch", #selector(OnGlitch))
        miChatty = Add("Chatty", #selector(OnChatty))
        miThrough = Add("Click through pet", #selector(OnClickThrough))
        for mi in [miFollow, miPerch, miDance, miGlitch, miChatty, miThrough] { menu.addItem(mi!) }

        let size = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let sizes = NSMenu()
        sizes.autoenablesItems = false
        miSmall = Add("Small", #selector(OnSmall))
        miMedium = Add("Medium", #selector(OnMedium))
        miLarge = Add("Large", #selector(OnLarge))
        for mi in [miSmall, miMedium, miLarge] { sizes.addItem(mi!) }
        size.submenu = sizes
        menu.addItem(size)

        menu.addItem(.separator())
        miPause = Add("Pause", #selector(OnPause))
        menu.addItem(miPause)
        miStartup = Add("Open at login", #selector(OnStartup))
        menu.addItem(miStartup)
        menu.addItem(.separator())
        menu.addItem(Add("Quit", #selector(OnQuit)))

        item.button?.image = BuildIcon(18)
        item.button?.toolTip = "Clawd"
        item.menu = menu
    }

    private func Add(_ text: String, _ sel: Selector) -> NSMenuItem
    {
        let mi = NSMenuItem(title: text, action: sel, keyEquivalent: "")
        mi.target = self
        return mi
    }

    // ---- commands ----

    @objc private func OnComeHere() { overlay.Pet.ComeHere() }
    @objc private func OnSay() { overlay.Pet.Speak() }
    @objc private func OnDance() { overlay.Pet.ForceDance() }

    @objc private func OnFollow() { cfg.FollowCursor = !cfg.FollowCursor; cfg.Save() }
    @objc private func OnPerch() { cfg.Perch = !cfg.Perch; cfg.Save() }
    @objc private func OnDanceToMusic() { cfg.Dance = !cfg.Dance; cfg.Save() }
    @objc private func OnGlitch() { cfg.Glitch = !cfg.Glitch; cfg.Save() }
    @objc private func OnChatty() { cfg.Chatty = !cfg.Chatty; cfg.Save() }

    @objc private func OnClickThrough()
    {
        cfg.ClickThrough = !cfg.ClickThrough
        overlay.ApplyClickThrough()
        cfg.Save()
    }

    @objc private func OnSmall() { SetScale(0.72) }
    @objc private func OnMedium() { SetScale(1.0) }
    @objc private func OnLarge() { SetScale(1.45) }

    private func SetScale(_ s: Double)
    {
        cfg.Scale = s
        overlay.ApplyScale()
        overlay.Pet.Emit(0, 8)
        cfg.Save()
    }

    @objc private func OnPause() { overlay.SetPaused(!cfg.Paused) }
    @objc private func OnStartup() { SetStartup(!IsStartupEnabled()) }
    @objc private func OnQuit() { NSApp.terminate(nil) }

    // ---- checkmarks ----

    public func menuNeedsUpdate(_ menu: NSMenu) { Refresh() }

    private func Refresh()
    {
        miFollow.state = cfg.FollowCursor ? .on : .off
        miPerch.state = cfg.Perch ? .on : .off
        miDance.state = cfg.Dance ? .on : .off
        miGlitch.state = cfg.Glitch ? .on : .off
        miChatty.state = cfg.Chatty ? .on : .off
        miThrough.state = cfg.ClickThrough ? .on : .off
        miPause.state = cfg.Paused ? .on : .off
        miStartup.state = IsStartupEnabled() ? .on : .off
        miSmall.state = cfg.Scale < 0.85 ? .on : .off
        miMedium.state = (cfg.Scale >= 0.85 && cfg.Scale < 1.2) ? .on : .off
        miLarge.state = cfg.Scale >= 1.2 ? .on : .off
    }

    public func ShowMenu()
    {
        Refresh()
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // ---- open at login ----

    private func IsStartupEnabled() -> Bool
    {
        return SMAppService.mainApp.status == .enabled
    }

    private func SetStartup(_ on: Bool)
    {
        do
        {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        }
        catch
        {
            // Registering only works from inside a signed .app bundle; running the bare
            // binary straight out of the build directory will land here.
            Log.Once("open at login: \(error)")
        }
    }

    // ---- runtime-drawn icon ----

    private func BuildIcon(_ size: CGFloat) -> NSImage
    {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: true)
        { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setShouldAntialias(false)                 // pixel art: no antialiasing

            let u = Double(size) / 12.6
            let cx = Double(size) / 2.0
            let cy = Double(size) / 2.0 - 0.5 * u         // sprite spans -4..+5 units

            // A template image is a mask, so the body is drawn solid and the eyes are
            // punched back out of it. The menu bar then tints the whole thing for us,
            // light mode or dark.
            ctx.setFillColor(NSColor.black.cgColor)
            for r in Tray.CrabRects(u)
            {
                ctx.fill(CGRect(x: Snap(cx + r.minX), y: Snap(cy + r.minY),
                                width: max(1, Snap(r.width)), height: max(1, Snap(r.height))))
            }

            ctx.setBlendMode(.clear)
            let e = max(1, Snap(u * 1.7))
            ctx.fill(CGRect(x: Snap(cx - 2.6 * u - e / 2), y: Snap(cy - 2.05 * u - e / 2), width: e, height: e))
            ctx.fill(CGRect(x: Snap(cx + 2.6 * u - e / 2), y: Snap(cy - 2.05 * u - e / 2), width: e, height: e))
            return true
        }
        img.isTemplate = true
        return img
    }

    // Clawd's silhouette on the unit grid, matching Character.BuildParts.
    static func CrabRects(_ u: Double) -> [CGRect]
    {
        var l: [CGRect] = []
        l.append(CGRect(x: -5 * u, y: -4 * u, width: 10 * u, height: 7 * u))    // body
        l.append(CGRect(x: -6 * u, y: -2 * u, width: 1 * u, height: 2 * u))     // left claw
        l.append(CGRect(x: 5 * u, y: -2 * u, width: 1 * u, height: 2 * u))      // right claw
        for x in [-5.0, -2.25, 0.5, 3.25]
        {
            l.append(CGRect(x: x * u, y: 3 * u, width: 1.75 * u, height: 2 * u))
        }
        l.append(CGRect(x: -0.5 * u, y: 3 * u, width: 1 * u, height: 1 * u))    // shallow middle notch
        return l
    }

    public func Dispose()
    {
        NSStatusBar.system.removeStatusItem(item)
    }
}

private func Snap(_ v: CGFloat) -> CGFloat { return v.rounded() }
