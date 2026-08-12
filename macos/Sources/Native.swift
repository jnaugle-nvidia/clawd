import AppKit
import CoreGraphics

// A rectangle in flipped global screen coordinates: the origin is the top-left corner of
// the primary display and y grows downward, measured in points. Win32 and CGWindowList
// both hand out coordinates in exactly that sense, so the pet keeps one coordinate system
// on both platforms and only the AppKit boundary — placing the overlay window — converts.
public struct ScreenRect
{
    public var Left = 0.0
    public var Top = 0.0
    public var Right = 0.0
    public var Bottom = 0.0

    public var Width: Double { return Right - Left }
    public var Height: Double { return Bottom - Top }
    public var Valid: Bool { return Right > Left && Bottom > Top }

    public init() { }

    public init(left: Double, top: Double, right: Double, bottom: Double)
    {
        Left = left; Top = top; Right = right; Bottom = bottom
    }
}

// Thin platform layer. Everything here works in flipped global screen points.
public enum Native
{
    // ---- displays ----
    //
    // NSScreen.screens allocates a fresh array on every access, and the pet asks for the
    // work area several times a frame. The layout only changes when a display is plugged,
    // unplugged or rearranged, so cache it and let the notification invalidate it.

    fileprivate struct Display
    {
        var frame = NSRect.zero
        var visible = NSRect.zero
    }

    fileprivate private(set) static var displays: [Display] = []
    private static var primaryTop: CGFloat = 0
    private static var observing = false

    public static func Start()
    {
        if !observing
        {
            observing = true
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main) { _ in Native.RefreshDisplays() }
        }
        RefreshDisplays()
    }

    public static func RefreshDisplays()
    {
        let screens = NSScreen.screens
        displays = screens.map { Display(frame: $0.frame, visible: $0.visibleFrame) }

        // Global flipped y is measured from the top of the screen that owns the menu bar,
        // which is the one sitting at the AppKit origin.
        let primary = screens.first(where: { $0.frame.origin == .zero }) ?? screens.first
        primaryTop = primary?.frame.maxY ?? 0
    }

    fileprivate static func EnsureDisplays()
    {
        if displays.isEmpty { RefreshDisplays() }
    }

    // ---- flipped <-> AppKit ----

    public static func Flip(_ y: CGFloat) -> Double
    {
        return Double(primaryTop - y)
    }

    public static func Flipped(_ r: NSRect) -> ScreenRect
    {
        return ScreenRect(left: Double(r.minX), top: Double(primaryTop - r.maxY),
                          right: Double(r.maxX), bottom: Double(primaryTop - r.minY))
    }

    // Where AppKit wants a window's origin so that its top-left lands on a flipped point.
    public static func AppKitOrigin(x: Double, y: Double, height: Double) -> NSPoint
    {
        return NSPoint(x: CGFloat(x), y: primaryTop - CGFloat(y) - CGFloat(height))
    }

    // ---- cursor and idle ----

    public static func CursorPos() -> (x: Double, y: Double)
    {
        let p = NSEvent.mouseLocation
        return (Double(p.x), Flip(p.y))
    }

    // kCGAnyInputEventType. It shares its value with .tapDisabledByUserInput, which is a
    // real case, so the lookup succeeds — but fall back to polling the input events we
    // care about rather than trusting that.
    private static let anyInput = CGEventType(rawValue: ~0)

    private static let fallbackTypes: [CGEventType] =
        [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .flagsChanged, .scrollWheel]

    // Seconds since the user last touched keyboard or mouse.
    public static func IdleSeconds() -> Double
    {
        if let any = anyInput
        {
            return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: any)
        }
        var best = Double.greatestFiniteMagnitude
        for t in fallbackTypes
        {
            best = min(best, CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: t))
        }
        return best == Double.greatestFiniteMagnitude ? 0 : best
    }
}

public enum ScreenUtil
{
    // The usable area of the display under a point: excludes the menu bar and the Dock.
    public static func WorkArea(_ x: Double, _ y: Double) -> ScreenRect
    {
        Native.EnsureDisplays()
        let all = Native.displays
        if all.isEmpty { return ScreenRect(left: 0, top: 0, right: 1440, bottom: 900) }

        var best = all[0]
        var bestDist = Double.greatestFiniteMagnitude
        for d in all
        {
            let f = Native.Flipped(d.frame)
            if x >= f.Left && x < f.Right && y >= f.Top && y < f.Bottom { return Native.Flipped(d.visible) }

            // Off every display (a window dragged half off the edge): take the nearest,
            // which is what Screen.FromPoint does on Windows.
            let dx = max(f.Left - x, 0, x - f.Right)
            let dy = max(f.Top - y, 0, y - f.Bottom)
            let dist = dx * dx + dy * dy
            if dist < bestDist { bestDist = dist; best = d }
        }
        return Native.Flipped(best.visible)
    }

    // The bounding box of every display, the way Windows describes its virtual screen.
    public static func Virtual() -> ScreenRect
    {
        Native.EnsureDisplays()
        let all = Native.displays
        if all.isEmpty { return ScreenRect(left: 0, top: 0, right: 1440, bottom: 900) }

        var u = Native.Flipped(all[0].frame)
        for i in 1 ..< all.count
        {
            let f = Native.Flipped(all[i].frame)
            u.Left = min(u.Left, f.Left)
            u.Top = min(u.Top, f.Top)
            u.Right = max(u.Right, f.Right)
            u.Bottom = max(u.Bottom, f.Bottom)
        }
        return u
    }
}
