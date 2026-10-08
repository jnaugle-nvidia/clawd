import AppKit
import CoreGraphics

// Clawd: a blocky pixel crab. Everything is built on a unit grid (u) and snapped to whole
// points so the edges stay hard. Drawn with (0,0) at the centre of the body, into a
// flipped context so y grows downward exactly as it does on Windows.
//
// Grid, in units, with the body centre at the origin:
//   body      x -5..5      y -4..3
//   claws     x -6..-5 and 5..6,  y -2..0
//   legs      four, 1.75 wide, hanging off the bottom edge
//   eyes      1.7 squares centred at (+-2.6, -2.05)
public enum Character
{
    private static func Rgb(_ r: Int, _ g: Int, _ b: Int, _ a: Double = 1) -> CGColor
    {
        return CGColor(srgbRed: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0,
                       blue: CGFloat(b) / 255.0, alpha: CGFloat(a))
    }

    private static let Coral      = Rgb(0xD9, 0x77, 0x57)
    private static let Sticker    = Rgb(0xFA, 0xF9, 0xF5)
    private static let Ink        = Rgb(0x18, 0x14, 0x12)
    private static let Shade      = Rgb(0, 0, 0, 0x30 / 255.0)
    private static let Spark      = Rgb(0xFF, 0xC9, 0x6B)
    private static let GhostCyan  = Rgb(0x4F, 0xE0, 0xE8, 0x55 / 255.0)
    private static let GhostRed   = Rgb(0xFF, 0x4D, 0x67, 0x50 / 255.0)
    private static let ScanLine   = Rgb(0xFF, 0xFF, 0xFF, 0x3A / 255.0)
    private static let HeartBrush = Rgb(0xE2, 0x5C, 0x52)
    private static let EyeShine   = Rgb(0xFA, 0xF9, 0xF5)

    private static let InkText   = NSColor(srgbRed: 0x18 / 255.0, green: 0x14 / 255.0, blue: 0x12 / 255.0, alpha: 1)
    private static let CoralText = NSColor(srgbRed: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x57 / 255.0, alpha: 1)

    // 5x5 square spiral for dizzy eyes.
    private static let Spiral: [[Int]] =
    [
        [1, 1, 1, 1, 1],
        [0, 0, 0, 0, 1],
        [1, 1, 1, 0, 1],
        [1, 0, 0, 0, 1],
        [1, 1, 1, 1, 1]
    ]

    // 5x5 pixel heart.
    private static let Heart: [[Int]] =
    [
        [0, 1, 0, 1, 0],
        [1, 1, 1, 1, 1],
        [1, 1, 1, 1, 1],
        [0, 1, 1, 1, 0],
        [0, 0, 1, 0, 0]
    ]

    public static func Draw(_ ctx: CGContext, _ p: Pet)
    {
        let u = max(2, (p.R / 5.0).rounded())

        let ease = 1 - pow(1 - p.Appear, 3)
        if ease <= 0.02 { return }

        // The shadow marks the ground plane: it does not bob, sway or spin.
        if p.Grounded { DrawGroundShadow(ctx, u) }

        let sway = p.State == .dance ? p.DanceSwayPx.rounded() : 0
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(sway), y: CGFloat(p.Bob.rounded()))

        // Rotation happens in quarter turns only, which keeps the grid square: continuous
        // while tossed, a decaying twirl during a dance accent.
        let q = ((p.Spin / 90.0).rounded() * 90.0).truncatingRemainder(dividingBy: 360.0)
        let rot = q > 0.5 || q < -0.5
        if rot
        {
            ctx.saveGState()
            ctx.rotate(by: CGFloat(q * Double.pi / 180.0))
        }

        // Scaling is allowed in two places only. The spawn pop lasts about half a second...
        let popping = p.Appear < 0.999
        if popping
        {
            let pop = ease * (1 + 0.12 * sin(p.Appear * Double.pi))
            ctx.saveGState()
            ctx.scaleBy(x: CGFloat(pop), y: CGFloat(pop))
        }

        // ...and the "Claude needs you" throb, which is meant to be impossible to miss.
        let throbbing = p.NeedsYouScale != 1
        if throbbing
        {
            ctx.saveGState()
            ctx.scaleBy(x: CGFloat(p.NeedsYouScale), y: CGFloat(p.NeedsYouScale))
        }

        let parts = BuildParts(p, u)

        if p.GlitchAmt > 0.01 { DrawGlitched(ctx, p, u, parts) }
        else { DrawCrab(ctx, p, u, parts) }

        if throbbing { ctx.restoreGState() }
        if popping { ctx.restoreGState() }
        if rot { ctx.restoreGState() }
        ctx.restoreGState()

        DrawParticles(ctx, p)
        if p.SayT > 0 && !p.Say.isEmpty { DrawBubble(ctx, p, u) }
    }

    private static func Fill(_ ctx: CGContext, _ color: CGColor, _ r: CGRect)
    {
        ctx.setFillColor(color)
        ctx.fill(r)
    }

    private static func DrawCrab(_ ctx: CGContext, _ p: Pet, _ u: Double, _ parts: [CGRect])
    {
        ctx.setFillColor(Coral)
        ctx.fill(parts)
        DrawEyes(ctx, p, u)
    }

    // ---- hologram glitch ----
    // RGB ghost fringes behind the body, the sprite sliced into bands that jump sideways,
    // the odd band dropping out entirely, and a scanline shimmer.

    private static func DrawGlitched(_ ctx: CGContext, _ p: Pet, _ u: Double, _ parts: [CGRect])
    {
        let seed = p.GlitchSeed
        ctx.saveGState()
        ctx.setAlpha(CGFloat(0.72 + 0.28 * H(seed, 99)))              // signal flicker

        let off = max(1, (u * (0.5 + 1.7 * H(seed, 50))).rounded())
        let jy = ((H(seed, 51) - 0.5) * u * 0.8).rounded()

        ctx.saveGState()
        ctx.translateBy(x: CGFloat(-off), y: CGFloat(jy))
        ctx.setFillColor(GhostCyan)
        ctx.fill(parts)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.translateBy(x: CGFloat(max(1, (off * 0.7).rounded())), y: CGFloat(-jy))
        ctx.setFillColor(GhostRed)
        ctx.fill(parts)
        ctx.restoreGState()

        let box = CGRect(x: -7 * u, y: -5 * u, width: 14 * u, height: 11 * u)
        let bands = 5
        let bh = box.height / CGFloat(bands)
        for i in 0 ..< bands
        {
            if H(seed, i * 7 + 3) < 0.10 { continue }                 // dropout: signal loss
            let hh = H(seed, i * 3 + 1)
            let dx = hh < 0.5 ? ((hh - 0.25) * 4 * 1.3 * u).rounded() : 0
            ctx.saveGState()
            ctx.clip(to: CGRect(x: box.minX, y: box.minY + CGFloat(i) * bh, width: box.width, height: bh))
            ctx.translateBy(x: CGFloat(dx), y: 0)
            DrawCrab(ctx, p, u, parts)
            ctx.restoreGState()
        }

        // scanlines, clipped to the body so they never reveal the window rectangle
        for k in 0 ..< 2
        {
            let sy = box.minY + CGFloat(H(seed, 60 + k)) * box.height
            let scan = CGRect(x: box.minX, y: sy, width: box.width, height: CGFloat(max(1, (u * 0.22).rounded())))
            ctx.setFillColor(ScanLine)
            for part in parts
            {
                let ri = part.intersection(scan)
                if !ri.isNull && ri.width > 0 && ri.height > 0 { ctx.fill(ri) }
            }
        }

        ctx.restoreGState()
    }

    // Deterministic per-seed noise so a glitch frame holds still until the seed rerolls.
    private static func H(_ seed: Int, _ i: Int) -> Double
    {
        var x = UInt32(truncatingIfNeeded: seed &* 73856093) ^ UInt32(truncatingIfNeeded: i &* 19349663)
        x ^= x << 13; x ^= x >> 17; x ^= x << 5
        return Double(x % 10000) / 10000.0
    }

    // ---- silhouette ----

    private static func BuildParts(_ p: Pet, _ u: Double) -> [CGRect]
    {
        var parts: [CGRect] = []

        // Moving fast squashes the body a unit wider and shorter.
        let sq = p.Squash > 0.07 ? 1.0 : 0.0
        let bodyL = -5 * u - sq * 0.4 * u
        let bodyR = 5 * u + sq * 0.4 * u
        let bodyT = -4 * u + sq * 0.5 * u
        let bodyB = 3 * u
        parts.append(LTRB(bodyL, bodyT, bodyR, bodyB))

        // Claws lift when happy or when the cursor is on the pet: it waves. Dancing, they
        // alternate on the beat - or both go up for "raise the roof".
        var liftL = 0.0, liftR = 0.0
        if p.State == .dance
        {
            let up = -(0.5 + 1.1 * p.DancePulse) * u
            if p.DanceMove == 1 { liftL = up; liftR = up }
            else if p.DanceParity { liftL = up; liftR = 0 }
            else { liftL = 0; liftR = up }
        }
        else
        {
            var lift = 0.0
            if p.CurrentMood == .happy { lift = -1.0 * u }
            else if p.HoverPop > 0.3 { lift = -0.6 * u * p.HoverPop }
            else if p.CurrentMood == .surprised { lift = -0.5 * u }
            if p.Grounded && abs(p.VX) > 25 { lift += sin(p.Clock * 9) * 0.25 * u }
            liftL = lift; liftR = lift
        }

        parts.append(LTRB(bodyL - u, -2 * u + liftL, bodyL, 0 * u + liftL))
        parts.append(LTRB(bodyR, -2 * u + liftR, bodyR + u, 0 * u + liftR))

        // Four legs. Tucked up a little while airborne; alternate kicks on the beat.
        let legLen = p.Grounded ? 2.3 * u : 1.9 * u
        let dancing = p.State == .dance
        let walking = p.Grounded && abs(p.VX) > 25 && !dancing
        let lx = [-5.0, -2.25, 0.5, 3.25]
        for i in 0 ..< 4
        {
            var step = 0.0
            if walking { step = sin(p.Clock * 9 + Double(i) * 1.7) > 0 ? -0.45 * u : 0 }
            else if dancing && ((i % 2 == 0) == p.DanceParity) { step = -0.6 * u * p.DancePulse }
            parts.append(LTRB(lx[i] * u, bodyB, (lx[i] + 1.75) * u, bodyB + legLen + step))
        }

        // The middle notch is shallower than the outer two.
        parts.append(LTRB(-0.5 * u, bodyB, 0.5 * u, bodyB + min(1.0 * u, legLen)))

        return parts
    }

    private static func LTRB(_ l: Double, _ t: Double, _ r: Double, _ b: Double) -> CGRect
    {
        let x = l.rounded(), y = t.rounded()
        return CGRect(x: x, y: y, width: max(1, r.rounded() - x), height: max(1, b.rounded() - y))
    }

    private static func DrawGroundShadow(_ ctx: CGContext, _ u: Double)
    {
        let y = 3 * u + 2.3 * u + 0.5 * u
        Fill(ctx, Shade, LTRB(-4.2 * u, y, 4.2 * u, y + 0.55 * u))
    }

    // ---- eyes ----

    private static func DrawEyes(_ ctx: CGContext, _ p: Pet, _ u: Double)
    {
        // Dancing reads as happy unless something stronger is showing.
        var mood = p.CurrentMood
        if p.State == .dance && (mood == .neutral || mood == .curious) { mood = .happy }

        let dx = (p.LookX * 0.55 * u).rounded()
        let dy = (p.LookY * 0.45 * u).rounded()
        let ey = -2.05 * u + dy

        for s in [-1.0, 1.0]
        {
            let ex = s * 2.6 * u + dx
            let shut = mood == .sleepy || p.Blink > 0.55

            if shut
            {
                Fill(ctx, Ink, LTRB(ex - 0.85 * u, ey - 0.22 * u, ex + 0.85 * u, ey + 0.22 * u))
            }
            else if mood == .happy
            {
                // stepped chevron: ^ ^
                let k = 0.56 * u
                Fill(ctx, Ink, LTRB(ex - 1.5 * k, ey + 0.1 * u, ex - 0.5 * k, ey + 0.1 * u + k))
                Fill(ctx, Ink, LTRB(ex - 0.5 * k, ey - 0.5 * u, ex + 0.5 * k, ey - 0.5 * u + k))
                Fill(ctx, Ink, LTRB(ex + 0.5 * k, ey + 0.1 * u, ex + 1.5 * k, ey + 0.1 * u + k))
            }
            else if mood == .dizzy
            {
                let c = 0.42 * u
                ctx.setFillColor(Ink)
                for gy in 0 ..< 5
                {
                    for gx in 0 ..< 5 where Spiral[gy][gx] != 0
                    {
                        ctx.fill(LTRB(ex + (Double(gx) - 2.5) * c, ey + (Double(gy) - 2.5) * c,
                                      ex + (Double(gx) - 1.5) * c, ey + (Double(gy) - 1.5) * c))
                    }
                }
            }
            else
            {
                let half = (mood == .surprised ? 1.0 : 0.85) * u
                let hh = half * (1 - p.Blink * 0.85)
                Fill(ctx, Ink, LTRB(ex - half, ey - hh, ex + half, ey + hh))
                if mood == .surprised || mood == .curious
                {
                    Fill(ctx, EyeShine, LTRB(ex - half + 0.18 * u, ey - hh + 0.18 * u,
                                             ex - half + 0.62 * u, ey - hh + 0.62 * u))
                }
            }
        }
    }

    // ---- particles ----

    private static func DrawParticles(_ ctx: CGContext, _ p: Pet)
    {
        for q in p.Parts
        {
            let a = max(0, min(1, q.Life / q.MaxLife))
            var fade = a > 0.7 ? (1 - a) / 0.3 : a / 0.7
            fade = max(0, min(1, fade))
            if fade <= 0.02 { continue }

            ctx.saveGState()
            ctx.setAlpha(CGFloat(fade))
            switch q.Kind
            {
            case 0: DrawSparkle(ctx, q)
            case 1: DrawPixelGrid(ctx, Heart, q.X, q.Y, q.Size * 0.42, HeartBrush)
            case 2: DrawGlyph(ctx, q, "z", italic: true, CoralText)
            default: DrawGlyph(ctx, q, "!", italic: false, CoralText)
            }
            ctx.restoreGState()
        }
    }

    // A pixel sparkle: a plus, with the arms trimmed as it fades.
    private static func DrawSparkle(_ ctx: CGContext, _ q: Particle)
    {
        let c = max(1, (q.Size * 0.42).rounded())
        let x = q.X.rounded(), y = q.Y.rounded()
        ctx.setFillColor(Spark)
        ctx.fill(CGRect(x: x - c * 0.5, y: y - c * 1.5, width: c, height: c * 3))
        ctx.fill(CGRect(x: x - c * 1.5, y: y - c * 0.5, width: c * 3, height: c))
    }

    private static func DrawPixelGrid(_ ctx: CGContext, _ grid: [[Int]], _ cx: Double, _ cy: Double,
                                      _ cell: Double, _ color: CGColor)
    {
        let c = max(1, cell.rounded())
        let n = grid.count
        let ox = (cx - Double(n) * c / 2).rounded(), oy = (cy - Double(n) * c / 2).rounded()
        ctx.setFillColor(color)
        for gy in 0 ..< n
        {
            for gx in 0 ..< n where grid[gy][gx] != 0
            {
                ctx.fill(CGRect(x: ox + Double(gx) * c, y: oy + Double(gy) * c, width: c, height: c))
            }
        }
    }

    // ---- text ----

    private static func Font(_ size: Double, italic: Bool) -> NSFont
    {
        let pts = CGFloat(max(7, size))
        let base = NSFont.boldSystemFont(ofSize: pts)
        if !italic { return base }
        let d = base.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: d, size: pts) ?? base
    }

    private static func DrawGlyph(_ ctx: CGContext, _ q: Particle, _ text: String,
                                  italic: Bool, _ color: NSColor)
    {
        let attrs: [NSAttributedString.Key: Any] =
            [.font: Font(q.Size, italic: italic), .foregroundColor: color]
        let s = text as NSString
        let size = s.size(withAttributes: attrs)

        // Rectangles are drawn hard-edged; glyphs are the one thing that wants smoothing.
        ctx.saveGState()
        ctx.setShouldAntialias(true)
        s.draw(at: NSPoint(x: (q.X - Double(size.width) / 2).rounded(),
                           y: (q.Y - Double(size.height) / 2).rounded()),
               withAttributes: attrs)
        ctx.restoreGState()
    }

    // ---- speech bubble ----

    private static func DrawBubble(_ ctx: CGContext, _ p: Pet, _ u: Double)
    {
        let fade = min(1.0, p.SayT > 0.45 ? 1.0 : p.SayT / 0.45)

        let para = NSMutableParagraphStyle()
        para.alignment = .left
        para.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] =
        [
            .font: Font(max(10, u * 1.5), italic: false),
            .foregroundColor: InkText,
            .paragraphStyle: para
        ]

        let str = NSAttributedString(string: p.Say, attributes: attrs)
        let maxW = u * 20
        let opts: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let measured = str.boundingRect(
            with: CGSize(width: maxW, height: .greatestFiniteMagnitude), options: opts)
        let tw = Double(ceil(measured.width)), th = Double(ceil(measured.height))

        let padX = u * 0.9, padY = u * 0.55
        let w = (tw + padX * 2).rounded(), h = (th + padY * 2).rounded()
        let left = (-w / 2).rounded(), top = (-5.6 * u - h).rounded()

        ctx.saveGState()
        ctx.setAlpha(CGFloat(fade))

        let b = max(1, (u * 0.22).rounded())
        Fill(ctx, Ink, CGRect(x: left - b, y: top - b, width: w + b * 2, height: h + b * 2))
        Fill(ctx, Sticker, CGRect(x: left, y: top, width: w, height: h))

        // stepped tail
        let t0 = top + h
        Fill(ctx, Ink, CGRect(x: -1.6 * u - b, y: t0, width: 1.6 * u + b * 2, height: u * 0.7 + b))
        Fill(ctx, Ink, CGRect(x: -1.6 * u - b, y: t0 + u * 0.7, width: 0.9 * u + b * 2, height: u * 0.7 + b))
        Fill(ctx, Sticker, CGRect(x: -1.6 * u, y: t0 - 1, width: 1.6 * u, height: u * 0.7 + 1))
        Fill(ctx, Sticker, CGRect(x: -1.6 * u, y: t0 + u * 0.7 - 1, width: 0.9 * u, height: u * 0.7 + 1))

        ctx.saveGState()
        ctx.setShouldAntialias(true)
        str.draw(with: CGRect(x: (left + padX).rounded(), y: (top + padY).rounded(),
                              width: maxW, height: th),
                 options: opts)
        ctx.restoreGState()

        ctx.restoreGState()
    }
}
