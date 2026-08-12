import AppKit

// The view the pet is painted onto. Flipped, so y grows downward and the artwork code is
// the same shape as the Windows original.
final class PetVisual: NSView
{
    var Target: Pet?
    var CX = 0.0, CY = 0.0   // pet centre inside the window, points

    var OnDown: ((Double, Double) -> Void)?
    var OnUp: (() -> Void)?
    var OnRight: (() -> Void)?

    override var isFlipped: Bool { return true }

    // The app never activates, so the very first click has to count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }

    override func draw(_ dirtyRect: NSRect)
    {
        guard let ctx = NSGraphicsContext.current?.cgContext, let p = Target else { return }
        ctx.saveGState()
        // Pixel art: no antialiasing. Hard edges, and abutting rectangles meet without the
        // faint seam that half-covered edge pixels leave behind.
        ctx.setShouldAntialias(false)
        ctx.interpolationQuality = .none
        ctx.translateBy(x: CGFloat(CX), y: CGFloat(CY))
        Character.Draw(ctx, p)
        ctx.restoreGState()
    }

    override func mouseDown(with event: NSEvent)
    {
        let c = Native.CursorPos()
        OnDown?(c.x, c.y)
    }

    override func mouseUp(with event: NSEvent) { OnUp?() }
    override func rightMouseDown(with event: NSEvent) { }
    override func rightMouseUp(with event: NSEvent) { OnRight?() }
    override func menu(for event: NSEvent) -> NSMenu? { return nil }
}

// A non-activating panel: clicking the pet never takes focus away from whatever you are
// typing in. This is the AppKit spelling of WS_EX_NOACTIVATE.
final class OverlayPanel: NSPanel
{
    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }
}

public final class Overlay
{
    public var Pet: ClaudePet.Pet { return pet }
    public var MenuRequested: (() -> Void)?

    private let cfg: Settings
    private let pet: ClaudePet.Pet
    private let visual = PetVisual()
    private let panel: OverlayPanel

    private var lastT = 0.0
    private var topmostT = 0.0
    private var winW = 300.0, winH = 280.0
    private var timer: Timer?

    private var dragging = false
    private var downX = 0.0, downY = 0.0, downTime = 0.0
    private var lastSig = Int.min
    private var lastPosX = Double.nan, lastPosY = Double.nan

    private func Now() -> Double { return ProcessInfo.processInfo.systemUptime }

    public init(_ cfg: Settings, _ watcher: WindowWatcher)
    {
        self.cfg = cfg
        self.pet = ClaudePet.Pet(cfg, watcher)

        panel = OverlayPanel(
            contentRect: NSRect(x: -4000, y: -4000, width: winW, height: winH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = false

        // Follow the user across Spaces and sit alongside full-screen apps rather than
        // being left behind on one desktop.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        visual.Target = pet
        visual.OnDown = { [weak self] x, y in self?.Down(x, y) }
        visual.OnUp = { [weak self] in self?.Up() }
        visual.OnRight = { [weak self] in self?.MenuRequested?() }
        panel.contentView = visual

        lastT = Now()
        ApplyScale()

        // A timer, not a display link: the pet only causes work when it moves or its pose
        // changes, and a render callback would pin the compositor open at full rate.
        // Common mode keeps him alive while a menu is tracking.
        let t = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in self?.OnFrame() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // ---- sizing ----

    public func ApplyScale()
    {
        // Points, not device pixels: AppKit already accounts for the display's scale, so
        // the crab is the same physical size on a Retina panel as on a 1x one.
        pet.R = 44.0 * cfg.Scale
        winW = max(300, pet.R * 5.4).rounded()
        winH = max(280, pet.R * 5.2).rounded()
        visual.CX = winW / 2.0
        visual.CY = winH * 0.62
        panel.setContentSize(NSSize(width: winW, height: winH))
        lastPosX = Double.nan          // force a move at the new size
        lastSig = Int.min              // force a repaint
        visual.needsDisplay = true
    }

    public func ApplyClickThrough()
    {
        let c = Native.CursorPos()
        panel.ignoresMouseEvents = cfg.ClickThrough || (!OverPet(c.x, c.y) && !dragging)
    }

    public func Show()
    {
        panel.orderFrontRegardless()
    }

    public func SetPaused(_ paused: Bool)
    {
        cfg.Paused = paused
        if paused { panel.orderOut(nil) }
        else
        {
            panel.orderFrontRegardless()
            pet.SetMood(.happy, 1.4)
            pet.Emit(0, 6)
        }
    }

    // ---- frame loop ----

    private func OnFrame()
    {
        if cfg.Paused { return }
        let now = Now()
        var dt = now - lastT
        if dt <= 0 { return }
        lastT = now
        if dt > 0.25 { dt = 0.25 }

        if dragging
        {
            let c = Native.CursorPos()
            pet.DragTo(c.x, c.y, dt)
        }

        pet.Update(dt)

        // An AppKit window is a plain rectangle as far as event routing is concerned: it
        // does not pass clicks through its transparent pixels the way a Windows layered
        // window does. So it has to be told, every frame, whether the cursor is actually
        // on the crab — otherwise a 300pt box of empty air would swallow clicks meant for
        // the app underneath.
        let c = Native.CursorPos()
        let over = OverPet(c.x, c.y)
        pet.Hovered = over
        panel.ignoresMouseEvents = cfg.ClickThrough || (!over && !dragging)

        Reposition()

        let sig = pet.VisualSignature(pet.R / 5.0)
        if sig != lastSig
        {
            lastSig = sig
            visual.needsDisplay = true
        }

        topmostT -= dt
        if topmostT <= 0
        {
            topmostT = 2.0
            panel.orderFrontRegardless()
            DebugDump()
        }
    }

    private func Reposition()
    {
        let x = (pet.X - visual.CX).rounded()
        let y = (pet.Y - visual.CY).rounded()
        if x == lastPosX && y == lastPosY { return }
        lastPosX = x; lastPosY = y
        panel.setFrameOrigin(Native.AppKitOrigin(x: x, y: y, height: Double(panel.frame.height)))
    }

    // Opt-in diagnostics: create ~/Library/Application Support/ClaudePet/debug.on to get a
    // once-a-second status line in status.txt. Delete it to stop.
    private func DebugDump()
    {
        let dir = Settings.Dir
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("debug.on").path) else { return }
        let m = pet.Music
        let line = "state=\(pet.State)"
            + " meter=" + m.MeterState
            + " active=\(m.MusicActive)"
            + " beats=\(m.ProvidesBeats)"
            + String(format: " env=%.3f avg=%.3f beatIv=%.2f glitch=%.1f", m.Env, m.Avg, m.BeatInterval, pet.GlitchAmt)
            + " pos=\(Int(pet.X)),\(Int(pet.Y))"
        try? line.write(to: dir.appendingPathComponent("status.txt"), atomically: true, encoding: .utf8)
    }

    // ---- input ----

    // The crab is a box, not a disc: claws out to +-6.5 units, legs down to 5.5.
    private func OverPet(_ sx: Double, _ sy: Double) -> Bool
    {
        let u = pet.R / 5.0
        let dx = sx - pet.X, dy = sy - (pet.Y + pet.Bob)
        return dx >= -6.6 * u && dx <= 6.6 * u && dy >= -4.6 * u && dy <= 5.6 * u
    }

    private func Down(_ cx: Double, _ cy: Double)
    {
        if !OverPet(cx, cy) { return }
        dragging = true
        downX = cx; downY = cy
        downTime = Now()
        pet.BeginDrag(cx, cy)
    }

    private func Up()
    {
        if !dragging { return }
        dragging = false

        let c = Native.CursorPos()
        let dx = c.x - downX, dy = c.y - downY
        let moved = (dx * dx + dy * dy).squareRoot()
        let held = Now() - downTime
        pet.EndDrag(moved < 6 && held < 0.45)
    }
}
