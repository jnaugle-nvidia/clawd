import CoreGraphics
import Foundation

public enum PetState { case hover, approach, perch, sleep, drag, toss, dance }
public enum Mood { case neutral, happy, curious, surprised, sleepy, dizzy }

public struct Particle
{
    public var X = 0.0, Y = 0.0, VX = 0.0, VY = 0.0
    public var Life = 0.0, MaxLife = 0.0, Size = 0.0, Rot = 0.0
    public var Kind = 0   // 0 sparkle, 1 heart, 2 z, 3 exclaim
}

// The pet's mind and body. Pure logic in flipped screen points: no drawing code in here.
public final class Pet
{
    // ---- state the renderer reads ----
    public var X = 0.0, Y = 0.0          // body centre
    public var VX = 0.0, VY = 0.0
    public var R = 48.0                  // body radius
    public var State = PetState.hover
    public var CurrentMood = Mood.neutral
    public var Tilt = 0.0                // degrees
    public var Squash = 0.0              // 0..0.18
    public var Spin = 0.0                // burst rotation, degrees
    public var Bob = 0.0                 // vertical bob
    public var LookX = 0.0, LookY = 0.0  // -1..1 gaze direction
    public var Blink = 0.0               // 0 open .. 1 shut
    public var Grounded = false          // draw legs + shadow
    public var Hovered = false           // cursor is over the pet
    public var HoverPop = 0.0            // eased 0..1 version of Hovered
    public var Appear = 0.0              // 0..1 spawn animation
    public var Say = ""
    public var SayT = 0.0
    public var Parts: [Particle] = []

    // dance, read by the renderer
    public var DancePulse = 0.0          // 1 on the beat, decays between beats
    public var DanceParity = false       // flips every beat: which claw / legs are up
    public var DanceMove = 0             // current move, changes every 8 beats
    public var DanceSwayPx = 0.0         // side-to-side body offset

    // hologram glitch, read by the renderer
    public var GlitchAmt = 0.0           // 0 or 1: a burst is happening
    public var GlitchSeed = 0            // reroll = the slices jump

    public let Watcher: WindowWatcher
    public let Music = MusicMeter()
    public private(set) var Clock = 0.0

    // The window the user picked out of the menu, or 0 when he is free to roam. While this
    // is set he only ever perches here, and he stays put instead of wandering off again.
    public private(set) var PinnedWindow: CGWindowID = 0

    // ---- internals ----
    private let cfg: Settings

    private var pollT = 0.0, moodT = 0.0, blinkT = 0.0, blinkPhase = 0.0
    private var wanderT = 0.0, walkT = 0.0, perchTimer = 0.0, perchIdleT = 0.0
    private var zT = 0.0, quipT = 0.0, noticeCool = 0.0, startleCool = 0.0
    private var dash = 0.0, settleT = 0.0, tossT = 0.0, orbitA = 0.0
    private var wanderX = 0.0, wanderY = 0.0, sleepX = 0.0, sleepY = 0.0
    private var grabDX = 0.0, grabDY = 0.0, dragVX = 0.0, dragVY = 0.0
    private var lastCx = 0.0, lastCy = 0.0
    private var spinVel = 0.0
    private var perchWindow: CGWindowID = 0
    private var perchFrac = 0.3
    private var pinRetryT = 0.0      // wait this long before trying the pinned window again
    private var pinLostT = 0.0       // how long the pinned window has been unreachable

    private var forcedDanceT = 0.0, danceCool = 0.0, dancePhase = 0.0, beatTimer = 0.0
    private var beatInterval = 0.5
    private var danceX = 0.0, danceY = 0.0
    private var danceOnPerch = false
    private var beatCount = 0

    private var glitchNextT = 2.5, glitchBurstT = 0.0, glitchSeedT = 0.0

    private let SleepAfter = 180.0   // seconds idle before a nap
    private let Gravity = 1600.0
    private let PinGiveUp = 30.0     // a pinned window gone this long is gone for good

    private static let Quips =
    [
        "hi :)", "boop", "just vibing", "nice window", "i live here now",
        "don't mind me", "you're doing great", "need a hand?",
        "cosy up here", "*small burst noises*", "still here!", "hello again"
    ]

    public init(_ cfg: Settings, _ watcher: WindowWatcher)
    {
        self.cfg = cfg
        self.Watcher = watcher

        let wa = ScreenUtil.WorkArea(0, 0)
        X = wa.Left + wa.Width * 0.62
        Y = wa.Top + wa.Height * 0.32
        NewWanderTarget()
        blinkT = 2.0
        quipT = 40
        perchIdleT = 6
        SetMood(.happy, 2.4)
        Emit(0, 10)

        watcher.ForegroundChanged = { [weak self] w in self?.OnForegroundChanged(w) }
    }

    // ================= public commands =================

    public func ComeHere()
    {
        WakeUp()
        if State == .drag { return }
        forcedDanceT = 0
        danceCool = 4                 // called mid-dance: sit this one out
        danceOnPerch = false
        State = .hover
        let c = Native.CursorPos()
        wanderX = c.x
        wanderY = c.y - R * 1.5
        wanderT = 5
        dash = 1.6
        perchIdleT = 14
        pinRetryT = 14                // pinned or not, he was called over: stay a while
        SetMood(.happy, 1.6)
        Emit(0, 6)
    }

    // Send him to one specific window and keep him there. Replaces any earlier pin.
    public func PinTo(_ w: DeskWindow)
    {
        WakeUp()
        PinnedWindow = w.Id
        pinRetryT = 0
        pinLostT = 0
        SetMood(.happy, 1.6)
        Emit(0, 5)
        // Mid-throw or mid-drag he finishes what he is doing; DoHover picks the pin up after.
        if State == .drag || State == .toss { return }
        forcedDanceT = 0
        danceOnPerch = false
        GoPerch(w)
    }

    // Back to roaming. He sits out the rest of this perch, then carries on as before.
    public func Unpin()
    {
        if PinnedWindow == 0 { return }
        PinnedWindow = 0
        pinRetryT = 0
        pinLostT = 0
        perchTimer = min(perchTimer, 8)
    }

    public func PetIt()
    {
        WakeUp()
        SetMood(.happy, 2.2)
        Emit(1, 5)
        VY -= 380
        if State == .perch { perchTimer = max(perchTimer, 8) }
    }

    public func Speak()
    {
        WakeUp()
        var line = Pet.Quips.randomElement() ?? "hi :)"
        if let fg = Watcher.Find(Watcher.Foreground), !fg.AppName.isEmpty,
           Double.random(in: 0 ..< 1) < 0.35
        {
            line = "ooh, " + fg.AppName
        }
        SayText(line, 3.0)
        SetMood(.happy, 1.8)
    }

    public func BeginDrag(_ cx: Double, _ cy: Double)
    {
        WakeUp()
        State = .drag
        grabDX = X - cx
        grabDY = Y - cy
        dragVX = 0; dragVY = 0
        SetMood(.surprised, 0.7)
    }

    public func DragTo(_ cx: Double, _ cy: Double, _ dt: Double)
    {
        if State != .drag { return }
        let nx = cx + grabDX, ny = cy + grabDY
        if dt > 0.0001
        {
            let ivx = (nx - X) / dt, ivy = (ny - Y) / dt
            dragVX += (ivx - dragVX) * 0.35
            dragVY += (ivy - dragVY) * 0.35
        }
        X = nx; Y = ny
    }

    public func EndDrag(_ wasClick: Bool)
    {
        if State != .drag { return }
        if wasClick
        {
            State = .hover
            NewWanderTarget()
            PetIt()
            return
        }
        State = .toss
        VX = Pet.Clamp(dragVX, -2600, 2600)
        VY = Pet.Clamp(dragVY, -2600, 2600)
        spinVel = Pet.Clamp(VX * 0.45, -700, 700)
        tossT = 0; settleT = 0
        let sp = (VX * VX + VY * VY).squareRoot()
        if sp > 700 { SetMood(.surprised, 1.0); Emit(3, 1) }
    }

    // ================= main loop =================

    public func Update(_ dtIn: Double)
    {
        let dt = min(dtIn, 0.1)   // survive a stall without teleporting
        Clock += dt
        Appear = min(1.0, Appear + dt * 2.2)

        let c = Native.CursorPos()
        let cx = c.x, cy = c.y
        let cursorSpeed = Pet.Dist(cx, cy, lastCx, lastCy) / max(dt, 0.001)
        lastCx = cx; lastCy = cy

        pollT -= dt
        if pollT <= 0 { pollT = 0.3; Watcher.Poll() }

        Tick(&moodT, dt); Tick(&noticeCool, dt); Tick(&startleCool, dt)
        Tick(&dash, dt); Tick(&SayT, dt); Tick(&perchIdleT, dt)
        Tick(&forcedDanceT, dt); Tick(&danceCool, dt)
        if moodT <= 0 { CurrentMood = (State == .sleep) ? .sleepy : .neutral }

        if cfg.Dance || forcedDanceT > 0 { Music.Poll(dt) }
        let wantDance = (cfg.Dance && Music.MusicActive) || forcedDanceT > 0

        let idle = Native.IdleSeconds()
        if State != .drag && State != .toss
        {
            if idle > SleepAfter && State != .sleep && !wantDance { EnterSleep() }
            else if idle < 1.0 && State == .sleep { WakeUp() }
        }

        Startle(cx, cy, cursorSpeed)

        if State == .dance
        {
            if !wantDance { LeaveDance() }
        }
        else if wantDance && danceCool <= 0 &&
                (State == .hover || State == .approach || State == .perch || State == .sleep)
        {
            EnterDance()
        }

        switch State
        {
        case .hover:    DoHover(dt, cx, cy)
        case .approach: DoApproach(dt)
        case .perch:    DoPerch(dt)
        case .sleep:    DoSleep(dt)
        case .drag:     DoDrag(dt)
        case .toss:     DoToss(dt)
        case .dance:    DoDance(dt)
        }

        UpdateGlitch(dt)

        ClampToVirtual()
        UpdateFace(dt, cx, cy)
        UpdateParticles(dt)

        if cfg.Chatty
        {
            quipT -= dt
            if quipT <= 0
            {
                quipT = 240 + Double.random(in: 0 ..< 320)
                if State == .hover || State == .perch { Speak() }
            }
        }
    }

    // ================= behaviours =================

    private func DoHover(_ dt: Double, _ cx: Double, _ cy: Double)
    {
        Grounded = false

        // Turning perching off entirely drops the pin too; the two would contradict.
        if !cfg.Perch && PinnedWindow != 0 { Unpin() }

        if cfg.FollowCursor && dash <= 0
        {
            orbitA += dt * 0.8
            let rad = R * 2.3
            Spring(cx + cos(orbitA) * rad, cy - R * 1.4 + sin(orbitA) * rad * 0.45, dt, 20, 8)
        }
        else
        {
            wanderT -= dt
            if wanderT <= 0 || Pet.Dist(X, Y, wanderX, wanderY) < R * 0.7 { NewWanderTarget() }
            if dash > 0 { Spring(wanderX, wanderY, dt, 24, 8.6) }
            else { Spring(wanderX, wanderY, dt, 9, 5.6) }
        }

        // A pinned pet never picks a window at random: he keeps checking his own one and
        // goes back the moment it is reachable again.
        if PinnedWindow != 0
        {
            pinLostT += dt
            pinRetryT -= dt
            if pinRetryT <= 0 && dash <= 0
            {
                pinRetryT = 1.2
                if Watcher.TryLive(PinnedWindow) != nil { GoPerchId(PinnedWindow) }
                else if pinLostT > PinGiveUp { Unpin() }   // closed for good: roam again
            }
            return
        }

        if cfg.Perch && perchIdleT <= 0 && dash <= 0
        {
            let w = Watcher.PickInteresting()
            perchIdleT = 22 + Double.random(in: 0 ..< 26)
            if let w = w { GoPerch(w) }
        }
    }

    private func DoApproach(_ dt: Double)
    {
        guard let r = Watcher.TryLive(perchWindow) else { LeavePerch(true); return }
        if perchWindow == PinnedWindow { pinLostT = 0 }
        let (tx, ty) = PerchPoint(r)
        Spring(tx, ty, dt, 17, 7.4)
        Grounded = false
        if Pet.Dist(X, Y, tx, ty) < R * 0.5
        {
            State = .perch
            walkT = 2.5 + Double.random(in: 0 ..< 4)
            Emit(0, 4)
        }
    }

    private func DoPerch(_ dt: Double)
    {
        guard let r = Watcher.TryLive(perchWindow) else { LeavePerch(true); return }
        if perchWindow == PinnedWindow { pinLostT = 0 }

        walkT -= dt
        if walkT <= 0
        {
            walkT = 3 + Double.random(in: 0 ..< 6)
            perchFrac = Pet.Clamp(perchFrac + (Double.random(in: 0 ..< 1) - 0.5) * 0.34, 0.03, 0.97)
        }

        let (tx, ty) = PerchPoint(r)
        Spring(tx, ty, dt, 44, 11)
        Grounded = true

        perchTimer -= dt
        if perchTimer <= 0
        {
            // The pinned window is home: he re-ups the timer instead of wandering off.
            if perchWindow == PinnedWindow { perchTimer = 20 }
            else { LeavePerch(false) }
        }
    }

    // Sit on the window's top edge; if that would land under the menu bar, sit on the
    // title bar itself instead.
    private func PerchPoint(_ r: ScreenRect) -> (Double, Double)
    {
        let margin = R * 0.95
        let usable = max(r.Width - margin * 2, 8)
        let tx = r.Left + margin + perchFrac * usable
        var ty = r.Top - R * 0.56
        let wa = ScreenUtil.WorkArea(tx, max(ty, r.Top + 4))
        if ty - R * 0.8 < wa.Top { ty = r.Top + R * 0.62 }
        return (tx, ty)
    }

    private func GoPerch(_ w: DeskWindow) { GoPerchId(w.Id) }

    private func GoPerchId(_ id: CGWindowID)
    {
        perchWindow = id
        perchFrac = 0.1 + Double.random(in: 0 ..< 0.55)
        perchTimer = 16 + Double.random(in: 0 ..< 28)
        State = .approach
    }

    private func LeavePerch(_ startled: Bool)
    {
        perchWindow = 0
        State = .hover
        Grounded = false
        NewWanderTarget()
        perchIdleT = 10 + Double.random(in: 0 ..< 20)
        // Knocked off his pinned window: circle for a moment, then go back to it.
        if PinnedWindow != 0 { pinRetryT = startled ? 3.0 : 1.2 }
        if startled { SetMood(.surprised, 0.8); VY -= 220 }
    }

    // ---- dance ----

    public func ForceDance()
    {
        WakeUp()
        forcedDanceT = 12
        danceCool = 0
    }

    private func EnterDance()
    {
        WakeUp()
        danceOnPerch = State == .perch && perchWindow != 0
        if !danceOnPerch && PinnedWindow != 0 && Watcher.TryLive(PinnedWindow) != nil
        {
            perchWindow = PinnedWindow      // pinned: dance on his window, not down on the floor
            danceOnPerch = true
        }
        if !danceOnPerch
        {
            let wa = ScreenUtil.WorkArea(X, Y)
            danceX = Pet.Clamp(X, wa.Left + R * 2, wa.Right - R * 2)
            danceY = wa.Bottom - R * 1.12
        }
        State = .dance
        dancePhase = 0; beatTimer = 0.05; beatCount = 0
        DanceMove = 0; DancePulse = 0
        SetMood(.happy, 2.0)
        Emit(0, 5)
        if cfg.Chatty && Double.random(in: 0 ..< 1) < 0.5 { SayText("♪ let's go", 2.2) }
    }

    private func LeaveDance()
    {
        DancePulse = 0; DanceSwayPx = 0
        if danceCool < 1.0 { danceCool = 1.0 }
        if danceOnPerch, Watcher.TryLive(perchWindow) != nil
        {
            State = .perch
            walkT = 2
            if perchTimer < 8 { perchTimer = 8 }
        }
        else
        {
            State = .hover
            NewWanderTarget()
        }
        danceOnPerch = false
    }

    private func DoDance(_ dt: Double)
    {
        Grounded = true
        var tx = danceX, ty = danceY
        if danceOnPerch
        {
            if let r = Watcher.TryLive(perchWindow)
            {
                (tx, ty) = PerchPoint(r)
            }
            else
            {
                danceOnPerch = false
                let wa = ScreenUtil.WorkArea(X, Y)
                danceX = Pet.Clamp(X, wa.Left + R * 2, wa.Right - R * 2)
                danceY = wa.Bottom - R * 1.12
                tx = danceX; ty = danceY
            }
        }
        Spring(tx, ty, dt, 30, 9)

        // Sway crosses the body once per beat, alternating sides; beats resync it.
        dancePhase += dt / max(0.25, beatInterval)
        let amp = R * (DanceMove == 2 ? 0.30 : 0.20)
        DanceSwayPx = sin(min(dancePhase, 1.0) * Double.pi) * amp * (DanceParity ? 1 : -1)
        DancePulse -= DancePulse * min(1, dt * 5)

        var beat: Bool
        if Music.MusicActive && Music.ProvidesBeats
        {
            beat = Music.BeatNow                           // real beats from the speakers
            if Music.BeatInterval > 0.2 { beatInterval = Music.BeatInterval }
        }
        else
        {
            beatTimer -= dt                                // no envelope to follow: 128 bpm
            beat = beatTimer <= 0
            if beat { beatTimer += 0.469; beatInterval = 0.469 }
        }
        if beat { OnDanceBeat() }
    }

    private func OnDanceBeat()
    {
        DancePulse = 1
        DanceParity = !DanceParity
        dancePhase = 0
        beatCount += 1
        if beatCount % 8 == 0 { DanceMove = (DanceMove + 1) % 3 }
        if beatCount % 16 == 0 { Spin = Double.random(in: 0 ..< 1) < 0.5 ? 360 : -360 }   // a quarter-turn twirl
        if cfg.Chatty && Double.random(in: 0 ..< 1) < 0.04 { SayText("♪", 1.3) }
    }

    // ---- hologram glitch ----

    private func UpdateGlitch(_ dt: Double)
    {
        if !cfg.Glitch { GlitchAmt = 0; return }

        if glitchBurstT > 0
        {
            glitchBurstT -= dt
            glitchSeedT -= dt
            if glitchSeedT <= 0
            {
                glitchSeedT = 0.05 + Double.random(in: 0 ..< 0.05)   // slices jump every few frames
                GlitchSeed = Int.random(in: 1 ..< (1 << 30))
            }
            GlitchAmt = glitchBurstT > 0 ? 1 : 0
        }
        else
        {
            GlitchAmt = 0
            glitchNextT -= dt
            if glitchNextT <= 0
            {
                // mostly short flickers, occasionally a long bad-signal fit
                glitchBurstT = 0.10 + Double.random(in: 0 ..< (Double.random(in: 0 ..< 1) < 0.25 ? 0.5 : 0.22))
                glitchNextT = 2.0 + Double.random(in: 0 ..< 6.0)
                GlitchSeed = Int.random(in: 1 ..< (1 << 30))
                glitchSeedT = 0.06
            }
        }
    }

    private func DoSleep(_ dt: Double)
    {
        Spring(sleepX, sleepY, dt, 22, 9)
        Grounded = true
        zT -= dt
        if zT <= 0 { zT = 1.8; Emit(2, 1) }
    }

    private func EnterSleep()
    {
        State = .sleep
        SetMood(.sleepy, 9999)
        Say = ""; SayT = 0
        if let r = Watcher.TryLive(perchWindow)
        {
            (sleepX, sleepY) = PerchPoint(r)
        }
        else
        {
            let wa = ScreenUtil.WorkArea(X, Y)
            sleepX = Pet.Clamp(X, wa.Left + R * 1.5, wa.Right - R * 1.5)
            sleepY = wa.Bottom - R * 0.9
        }
    }

    private func WakeUp()
    {
        if State != .sleep { return }
        State = .hover
        NewWanderTarget()
        SetMood(.surprised, 0.9)
        Emit(0, 5)
        perchIdleT = 4
    }

    private func DoDrag(_ dt: Double)
    {
        Grounded = false
        Tilt += (Pet.Clamp(-dragVX * 0.016, -26, 26) - Tilt) * min(1, dt * 10)
    }

    private func DoToss(_ dt: Double)
    {
        tossT += dt
        VY += Gravity * dt
        VX *= (1 - 0.32 * dt)
        X += VX * dt; Y += VY * dt
        Spin += spinVel * dt
        spinVel *= (1 - 1.1 * dt)
        Grounded = false

        let wa = ScreenUtil.WorkArea(X, Y)
        var floor = false
        if Y > wa.Bottom - R { Y = wa.Bottom - R; VY = -VY * 0.5; VX *= 0.74; floor = true; if abs(VY) > 260 { Emit(0, 3) } }
        if Y < wa.Top + R { Y = wa.Top + R; VY = abs(VY) * 0.4 }
        if X < wa.Left + R { X = wa.Left + R; VX = abs(VX) * 0.58; Emit(0, 2) }
        if X > wa.Right - R { X = wa.Right - R; VX = -abs(VX) * 0.58; Emit(0, 2) }

        let sp = (VX * VX + VY * VY).squareRoot()
        if floor && sp < 120 { settleT += dt } else { settleT = 0 }

        if settleT > 0.45 || tossT > 7
        {
            SetMood(.dizzy, 1.2)
            State = .hover
            NewWanderTarget()
            Emit(0, 6)
        }
    }

    private func Startle(_ cx: Double, _ cy: Double, _ cursorSpeed: Double)
    {
        if startleCool > 0 { return }
        if State != .hover && State != .perch && State != .dance { return }
        if cursorSpeed < 1500 { return }
        let d = Pet.Dist(cx, cy, X, Y)
        if d > R * 1.7 { return }

        startleCool = 4
        SetMood(.surprised, 1.0)
        Emit(3, 1)
        let dx = X - cx, dy = Y - cy
        let len = max(1, (dx * dx + dy * dy).squareRoot())
        VX += dx / len * 620
        VY += dy / len * 620 - 180
        if State == .perch { LeavePerch(true) }
        else if State == .dance { danceCool = 3; danceOnPerch = false; LeaveDance() }
    }

    private func OnForegroundChanged(_ w: DeskWindow)
    {
        if !cfg.Perch { return }
        if PinnedWindow != 0 { return }      // the user picked his window: alt-tab doesn't move him
        if State == .drag || State == .toss || State == .dance { return }
        if noticeCool > 0 { return }
        noticeCool = 6
        WakeUp()
        SetMood(.curious, 1.5)
        Emit(3, 1)
        if cfg.Chatty && Double.random(in: 0 ..< 1) < 0.18 && !w.AppName.isEmpty
        {
            SayText("ooh, " + w.AppName, 2.6)
        }
        GoPerch(w)
    }

    // ================= face, motion, particles =================

    private func UpdateFace(_ dt: Double, _ cx: Double, _ cy: Double)
    {
        var tlx = 0.0, tly = 0.0
        if State != .sleep
        {
            tlx = Pet.Clamp((cx - X) / 320.0, -1, 1)
            tly = Pet.Clamp((cy - (Y - R * 0.1)) / 320.0, -1, 1)
        }
        LookX += (tlx - LookX) * min(1, dt * 8)
        LookY += (tly - LookY) * min(1, dt * 8)

        if State == .sleep
        {
            Blink = 1
        }
        else
        {
            blinkT -= dt
            if blinkT <= 0 && blinkPhase <= 0 { blinkT = 2.4 + Double.random(in: 0 ..< 4.5); blinkPhase = 0.17 }
            if blinkPhase > 0
            {
                blinkPhase -= dt
                let u = 1 - max(0, blinkPhase) / 0.17
                Blink = sin(Pet.Clamp(u, 0, 1) * Double.pi)
            }
            else { Blink = 0 }
        }

        HoverPop += ((Hovered ? 1.0 : 0.0) - HoverPop) * min(1, dt * 10)
        Bob = State == .dance
            ? -R * 0.28 * DancePulse                                   // hop on the beat
            : sin(Clock * 2.2) * R * (Grounded ? 0.035 : 0.07)

        let sp = (VX * VX + VY * VY).squareRoot()
        var sq = Pet.Clamp((sp - 150) / 2600.0, 0, 0.16)
        if State == .dance { sq = 0.13 * DancePulse }                  // chunky beat squash
        Squash += (sq - Squash) * min(1, dt * 8)

        if State != .drag
        {
            let tt = Pet.Clamp(VX * 0.014, -16, 16)
            Tilt += (tt - Tilt) * min(1, dt * 6)
        }

        // Spin is only for tumbling through the air; otherwise settle back upright.
        if State != .toss { Spin += (0 - Spin) * min(1, dt * 7) }
        if Spin > 3600 || Spin < -3600 { Spin = Spin.truncatingRemainder(dividingBy: 360) }
    }

    private func UpdateParticles(_ dt: Double)
    {
        var i = Parts.count - 1
        while i >= 0
        {
            Parts[i].Life -= dt
            if Parts[i].Life <= 0 { Parts.remove(at: i); i -= 1; continue }
            Parts[i].X += Parts[i].VX * dt
            Parts[i].Y += Parts[i].VY * dt
            switch Parts[i].Kind
            {
            case 0: Parts[i].VY += 260 * dt; Parts[i].VX *= (1 - 1.4 * dt)
            case 1: Parts[i].VY -= 40 * dt; Parts[i].VX = sin(Parts[i].Life * 6 + Parts[i].Rot) * 26
            case 2: Parts[i].VX = 22 + sin(Parts[i].Life * 3) * 10
            default: Parts[i].VY *= (1 - 2.0 * dt)
            }
            Parts[i].Rot += dt * (Parts[i].Kind == 0 ? 200 : 30)
            i -= 1
        }
    }

    public func Emit(_ kind: Int, _ count: Int)
    {
        var n = 0
        while n < count && Parts.count < 70
        {
            n += 1
            var p = Particle()
            p.Kind = kind
            p.Rot = Double.random(in: 0 ..< 360)
            if kind == 0
            {
                let a = Double.random(in: 0 ..< (Double.pi * 2)), sp = 70 + Double.random(in: 0 ..< 150)
                p.X = cos(a) * R * 0.5; p.Y = sin(a) * R * 0.5
                p.VX = cos(a) * sp; p.VY = sin(a) * sp - 60
                p.Life = 0.5 + Double.random(in: 0 ..< 0.45); p.MaxLife = p.Life
                p.Size = R * (0.09 + Double.random(in: 0 ..< 0.09))
            }
            else if kind == 1
            {
                p.X = (Double.random(in: 0 ..< 1) - 0.5) * R * 1.1; p.Y = -R * 0.35
                p.VX = (Double.random(in: 0 ..< 1) - 0.5) * 40; p.VY = -70 - Double.random(in: 0 ..< 70)
                p.Life = 1.0 + Double.random(in: 0 ..< 0.5); p.MaxLife = p.Life
                p.Size = R * (0.15 + Double.random(in: 0 ..< 0.08))
            }
            else if kind == 2
            {
                p.X = R * 0.5; p.Y = -R * 0.55
                p.VX = 24; p.VY = -30
                p.Life = 2.2; p.MaxLife = p.Life
                p.Size = R * 0.3
            }
            else
            {
                p.X = R * 0.05; p.Y = -R * 1.0
                p.VX = 0; p.VY = -70
                p.Life = 0.95; p.MaxLife = p.Life
                p.Size = R * 0.42
            }
            Parts.append(p)
        }
    }

    private func NewWanderTarget()
    {
        let wa = ScreenUtil.WorkArea(X, Y)
        let m = R * 1.6
        wanderX = wa.Left + m + Double.random(in: 0 ..< 1) * max(10, wa.Width - m * 2)
        wanderY = wa.Top + m + Double.random(in: 0 ..< 1) * max(10, wa.Height * 0.72 - m)
        wanderT = 3.5 + Double.random(in: 0 ..< 5.5)
    }

    private func Spring(_ tx: Double, _ ty: Double, _ dt: Double, _ k: Double, _ damp: Double)
    {
        VX += ((tx - X) * k - VX * damp) * dt
        VY += ((ty - Y) * k - VY * damp) * dt
        let sp = (VX * VX + VY * VY).squareRoot()
        if sp > 2600 { VX = VX / sp * 2600; VY = VY / sp * 2600 }
        X += VX * dt
        Y += VY * dt
    }

    private func ClampToVirtual()
    {
        let v = ScreenUtil.Virtual()
        let m = R * 0.35
        if X < v.Left + m { X = v.Left + m; if VX < 0 { VX = 0 } }
        if X > v.Right - m { X = v.Right - m; if VX > 0 { VX = 0 } }
        if Y < v.Top + m { Y = v.Top + m; if VY < 0 { VY = 0 } }
        if Y > v.Bottom - m { Y = v.Bottom - m; if VY > 0 { VY = 0 } }
    }

    // Moving the pet only moves its window, which costs nothing to redraw. This is a hash
    // of everything that actually changes the picture, so a pet that is drifting across
    // the screen without changing pose repaints zero times.
    public func VisualSignature(_ u: Double) -> Int
    {
        var h = 17
        h = h &* 31 &+ MoodIndex(CurrentMood)
        h = h &* 31 &+ (State == .toss ? 1 : 0)
        h = h &* 31 &+ (Grounded ? 1 : 0)
        h = h &* 31 &+ Int(Bob.rounded())
        h = h &* 31 &+ (Blink > 0.55 ? 1 : 0) &+ Int((Blink * 6).rounded())
        h = h &* 31 &+ Int((LookX * 0.55 * u).rounded())
        h = h &* 31 &+ Int((LookY * 0.45 * u).rounded())
        h = h &* 31 &+ (Squash > 0.07 ? 1 : 0)
        h = h &* 31 &+ Int((Spin / 90.0).rounded())
        h = h &* 31 &+ Int((Appear * 24).rounded())
        h = h &* 31 &+ Int((HoverPop * 8).rounded())
        h = h &* 31 &+ Parts.count
        for p in Parts   // 2px steps: fewer repaints, still reads as pixel art
        {
            h = h &* 31 &+ Int((p.X / 2).rounded()) &* 7 &+ Int((p.Y / 2).rounded())
        }
        if SayT > 0 && !Say.isEmpty
        {
            h = h &* 31 &+ Say.hashValue &+ Int((SayT * 4).rounded())
        }
        if Grounded && abs(VX) > 25 { h = h &* 31 &+ Int((Clock * 18).rounded()) }
        h = h &* 31 &+ Int(DanceSwayPx.rounded())
        h = h &* 31 &+ Int((DancePulse * 12).rounded())
        h = h &* 31 &+ (DanceParity ? 1 : 0) &+ DanceMove &* 2
        if GlitchAmt > 0.01 { h = h &* 31 &+ GlitchSeed; h = h &* 31 &+ 1 }
        return h
    }

    private func MoodIndex(_ m: Mood) -> Int
    {
        switch m
        {
        case .neutral: return 0
        case .happy: return 1
        case .curious: return 2
        case .surprised: return 3
        case .sleepy: return 4
        case .dizzy: return 5
        }
    }

    public func SetMood(_ m: Mood, _ secs: Double) { CurrentMood = m; moodT = secs }
    public func SayText(_ s: String, _ secs: Double) { Say = s; SayT = secs }

    private func Tick(_ v: inout Double, _ dt: Double) { if v > 0 { v -= dt } }

    private static func Dist(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double
    {
        let dx = ax - bx, dy = ay - by
        return (dx * dx + dy * dy).squareRoot()
    }

    public static func Clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double
    {
        return v < lo ? lo : (v > hi ? hi : v)
    }
}
