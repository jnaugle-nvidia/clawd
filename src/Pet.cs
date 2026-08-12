using System;
using System.Collections.Generic;

namespace Clawd
{
    public enum PetState { Hover, Approach, Perch, Sleep, Drag, Toss, Dance }
    public enum Mood { Neutral, Happy, Curious, Surprised, Sleepy, Dizzy }

    public class Particle
    {
        public double X, Y, VX, VY, Life, MaxLife, Size, Rot;
        public int Kind;   // 0 sparkle, 1 heart, 2 z, 3 exclaim
    }

    // The pet's mind and body. Pure logic in physical screen pixels: no WPF in here.
    public class Pet
    {
        // ---- state the renderer reads ----
        public double X, Y;              // body centre, physical px
        public double VX, VY;
        public double R = 48;            // body radius, physical px
        public PetState State = PetState.Hover;
        public Mood Mood = Mood.Neutral;
        public double Tilt;              // degrees
        public double Squash;            // 0..0.18
        public double Spin;              // burst rotation, degrees
        public double Bob;               // vertical bob, px
        public double LookX, LookY;      // -1..1 gaze direction
        public double Blink;             // 0 open .. 1 shut
        public bool Grounded;            // draw legs + shadow
        public bool Hovered;             // cursor is over the pet
        public double HoverPop;          // eased 0..1 version of Hovered
        public double Appear = 0.0;      // 0..1 spawn animation
        public string Say = "";
        public double SayT;
        public List<Particle> Parts = new List<Particle>();

        // dance, read by the renderer
        public double DancePulse;        // 1 on the beat, decays between beats
        public bool DanceParity;         // flips every beat: which claw / legs are up
        public int DanceMove;            // current move, changes every 8 beats
        public double DanceSwayPx;       // side-to-side body offset

        // hologram glitch, read by the renderer
        public double GlitchAmt;         // 0 or 1: a burst is happening
        public int GlitchSeed;           // reroll = the slices jump

        public WindowWatcher Watcher { get { return watcher; } }
        public double Clock { get { return t; } }
        public MusicMeter Music { get { return music; } }

        // ---- internals ----
        readonly Settings cfg;
        readonly WindowWatcher watcher;
        readonly Random rnd = new Random();

        double t;
        double pollT, moodT, blinkT, blinkPhase, wanderT, walkT, perchTimer, perchIdleT;
        double zT, quipT, noticeCool, startleCool, dash, settleT, tossT, orbitA;
        double wanderX, wanderY, sleepX, sleepY;
        double grabDX, grabDY, dragVX, dragVY;
        double lastCx, lastCy;
        double spinVel;
        IntPtr perchHwnd = IntPtr.Zero;
        double perchFrac = 0.3;

        readonly MusicMeter music = new MusicMeter();
        double forcedDanceT, danceCool, dancePhase, beatTimer;
        double beatInterval = 0.5;
        double danceX, danceY;
        bool danceOnPerch;
        int beatCount;

        double glitchNextT = 2.5, glitchBurstT, glitchSeedT;

        const double SleepAfter = 180.0;   // seconds idle before a nap
        const double Gravity = 1600.0;

        static readonly string[] Quips = new string[]
        {
            "hi :)", "boop", "just vibing", "nice window", "i live here now",
            "don't mind me", "you're doing great", "need a hand?",
            "cosy up here", "*small burst noises*", "still here!", "hello again"
        };

        public Pet(Settings cfg, WindowWatcher watcher)
        {
            this.cfg = cfg;
            this.watcher = watcher;
            watcher.ForegroundChanged += OnForegroundChanged;

            RECT wa = ScreenUtil.WorkArea(0, 0);
            X = wa.Left + wa.Width * 0.62;
            Y = wa.Top + wa.Height * 0.32;
            NewWanderTarget();
            blinkT = 2.0;
            quipT = 40;
            perchIdleT = 6;
            SetMood(Mood.Happy, 2.4);
            Emit(0, 10);
        }

        // ================= public commands =================

        public void ComeHere()
        {
            WakeUp();
            if (State == PetState.Drag) return;
            forcedDanceT = 0;
            danceCool = 4;                 // called mid-dance: sit this one out
            danceOnPerch = false;
            State = PetState.Hover;
            POINT c; Native.GetCursorPos(out c);
            wanderX = c.X;
            wanderY = c.Y - R * 1.5;
            wanderT = 5;
            dash = 1.6;
            perchIdleT = 14;
            SetMood(Mood.Happy, 1.6);
            Emit(0, 6);
        }

        public void PetIt()
        {
            WakeUp();
            SetMood(Mood.Happy, 2.2);
            Emit(1, 5);
            VY -= 380;
            if (State == PetState.Perch) perchTimer = Math.Max(perchTimer, 8);
        }

        public void Speak()
        {
            WakeUp();
            string line = Quips[rnd.Next(Quips.Length)];
            DeskWindow fg = watcher.Find(watcher.Foreground);
            if (fg != null && fg.AppName.Length > 0 && rnd.NextDouble() < 0.35)
                line = "ooh, " + fg.AppName;
            SayText(line, 3.0);
            SetMood(Mood.Happy, 1.8);
        }

        public void BeginDrag(double cx, double cy)
        {
            WakeUp();
            State = PetState.Drag;
            grabDX = X - cx;
            grabDY = Y - cy;
            dragVX = dragVY = 0;
            SetMood(Mood.Surprised, 0.7);
        }

        public void DragTo(double cx, double cy, double dt)
        {
            if (State != PetState.Drag) return;
            double nx = cx + grabDX, ny = cy + grabDY;
            if (dt > 0.0001)
            {
                double ivx = (nx - X) / dt, ivy = (ny - Y) / dt;
                dragVX += (ivx - dragVX) * 0.35;
                dragVY += (ivy - dragVY) * 0.35;
            }
            X = nx; Y = ny;
        }

        public void EndDrag(bool wasClick)
        {
            if (State != PetState.Drag) return;
            if (wasClick)
            {
                State = PetState.Hover;
                NewWanderTarget();
                PetIt();
                return;
            }
            State = PetState.Toss;
            VX = Clamp(dragVX, -2600, 2600);
            VY = Clamp(dragVY, -2600, 2600);
            spinVel = Clamp(VX * 0.45, -700, 700);
            tossT = 0; settleT = 0;
            double sp = Math.Sqrt(VX * VX + VY * VY);
            if (sp > 700) { SetMood(Mood.Surprised, 1.0); Emit(3, 1); }
        }

        // ================= main loop =================

        public void Update(double dt)
        {
            if (dt > 0.1) dt = 0.1;   // survive a stall without teleporting
            t += dt;
            Appear = Math.Min(1.0, Appear + dt * 2.2);

            POINT c; Native.GetCursorPos(out c);
            double cx = c.X, cy = c.Y;
            double cursorSpeed = Dist(cx, cy, lastCx, lastCy) / Math.Max(dt, 0.001);
            lastCx = cx; lastCy = cy;

            pollT -= dt;
            if (pollT <= 0) { pollT = 0.3; watcher.Poll(); }

            Tick(ref moodT, dt); Tick(ref noticeCool, dt); Tick(ref startleCool, dt);
            Tick(ref dash, dt); Tick(ref SayT, dt); Tick(ref perchIdleT, dt);
            Tick(ref forcedDanceT, dt); Tick(ref danceCool, dt);
            if (moodT <= 0) Mood = (State == PetState.Sleep) ? Mood.Sleepy : Mood.Neutral;

            if (cfg.Dance || forcedDanceT > 0) music.Poll(dt);
            bool wantDance = (cfg.Dance && music.MusicActive) || forcedDanceT > 0;

            double idle = Native.IdleSeconds();
            if (State != PetState.Drag && State != PetState.Toss)
            {
                if (idle > SleepAfter && State != PetState.Sleep && !wantDance) EnterSleep();
                else if (idle < 1.0 && State == PetState.Sleep) WakeUp();
            }

            Startle(cx, cy, cursorSpeed);

            if (State == PetState.Dance)
            {
                if (!wantDance) LeaveDance();
            }
            else if (wantDance && danceCool <= 0 &&
                     (State == PetState.Hover || State == PetState.Approach ||
                      State == PetState.Perch || State == PetState.Sleep))
            {
                EnterDance();
            }

            switch (State)
            {
                case PetState.Hover: DoHover(dt, cx, cy); break;
                case PetState.Approach: DoApproach(dt); break;
                case PetState.Perch: DoPerch(dt); break;
                case PetState.Sleep: DoSleep(dt); break;
                case PetState.Drag: DoDrag(dt); break;
                case PetState.Toss: DoToss(dt); break;
                case PetState.Dance: DoDance(dt); break;
            }

            UpdateGlitch(dt);

            ClampToVirtual();
            UpdateFace(dt, cx, cy);
            UpdateParticles(dt);

            if (cfg.Chatty)
            {
                quipT -= dt;
                if (quipT <= 0)
                {
                    quipT = 240 + rnd.NextDouble() * 320;
                    if (State == PetState.Hover || State == PetState.Perch) Speak();
                }
            }
        }

        // ================= behaviours =================

        void DoHover(double dt, double cx, double cy)
        {
            Grounded = false;

            if (cfg.FollowCursor && dash <= 0)
            {
                orbitA += dt * 0.8;
                double rad = R * 2.3;
                Spring(cx + Math.Cos(orbitA) * rad, cy - R * 1.4 + Math.Sin(orbitA) * rad * 0.45, dt, 20, 8);
            }
            else
            {
                wanderT -= dt;
                if (wanderT <= 0 || Dist(X, Y, wanderX, wanderY) < R * 0.7) NewWanderTarget();
                if (dash > 0) Spring(wanderX, wanderY, dt, 24, 8.6);
                else Spring(wanderX, wanderY, dt, 9, 5.6);
            }

            if (cfg.Perch && perchIdleT <= 0 && dash <= 0)
            {
                DeskWindow w = watcher.PickInteresting(rnd);
                perchIdleT = 22 + rnd.NextDouble() * 26;
                if (w != null) GoPerch(w);
            }
        }

        void DoApproach(double dt)
        {
            RECT r;
            if (!watcher.TryLive(perchHwnd, out r)) { LeavePerch(true); return; }
            double tx, ty;
            PerchPoint(r, out tx, out ty);
            Spring(tx, ty, dt, 17, 7.4);
            Grounded = false;
            if (Dist(X, Y, tx, ty) < R * 0.5)
            {
                State = PetState.Perch;
                walkT = 2.5 + rnd.NextDouble() * 4;
                Emit(0, 4);
            }
        }

        void DoPerch(double dt)
        {
            RECT r;
            if (!watcher.TryLive(perchHwnd, out r)) { LeavePerch(true); return; }

            walkT -= dt;
            if (walkT <= 0)
            {
                walkT = 3 + rnd.NextDouble() * 6;
                perchFrac = Clamp(perchFrac + (rnd.NextDouble() - 0.5) * 0.34, 0.03, 0.97);
            }

            double tx, ty;
            PerchPoint(r, out tx, out ty);
            Spring(tx, ty, dt, 44, 11);
            Grounded = true;

            perchTimer -= dt;
            if (perchTimer <= 0) LeavePerch(false);
        }

        // Sit on the window's top edge; on a maximised window sit on the title bar itself.
        void PerchPoint(RECT r, out double tx, out double ty)
        {
            double margin = R * 0.95;
            double usable = Math.Max(r.Width - margin * 2, 8);
            tx = r.Left + margin + perchFrac * usable;
            ty = r.Top - R * 0.56;
            RECT wa = ScreenUtil.WorkArea(tx, Math.Max(ty, r.Top + 4));
            if (ty - R * 0.8 < wa.Top) ty = r.Top + R * 0.62;
        }

        void GoPerch(DeskWindow w)
        {
            perchHwnd = w.Hwnd;
            perchFrac = 0.1 + rnd.NextDouble() * 0.55;
            perchTimer = 16 + rnd.NextDouble() * 28;
            State = PetState.Approach;
        }

        void LeavePerch(bool startled)
        {
            perchHwnd = IntPtr.Zero;
            State = PetState.Hover;
            Grounded = false;
            NewWanderTarget();
            perchIdleT = 10 + rnd.NextDouble() * 20;
            if (startled) { SetMood(Mood.Surprised, 0.8); VY -= 220; }
        }

        // ---- dance ----

        public void ForceDance()
        {
            WakeUp();
            forcedDanceT = 12;
            danceCool = 0;
        }

        void EnterDance()
        {
            WakeUp();
            danceOnPerch = State == PetState.Perch && perchHwnd != IntPtr.Zero;
            if (!danceOnPerch)
            {
                RECT wa = ScreenUtil.WorkArea(X, Y);
                danceX = Clamp(X, wa.Left + R * 2, wa.Right - R * 2);
                danceY = wa.Bottom - R * 1.12;
            }
            State = PetState.Dance;
            dancePhase = 0; beatTimer = 0.05; beatCount = 0;
            DanceMove = 0; DancePulse = 0;
            SetMood(Mood.Happy, 2.0);
            Emit(0, 5);
            if (cfg.Chatty && rnd.NextDouble() < 0.5) SayText("♪ let's go", 2.2);
        }

        void LeaveDance()
        {
            RECT r;
            DancePulse = 0; DanceSwayPx = 0;
            if (danceCool < 1.0) danceCool = 1.0;
            if (danceOnPerch && watcher.TryLive(perchHwnd, out r))
            {
                State = PetState.Perch;
                walkT = 2;
                if (perchTimer < 8) perchTimer = 8;
            }
            else
            {
                State = PetState.Hover;
                NewWanderTarget();
            }
            danceOnPerch = false;
        }

        void DoDance(double dt)
        {
            Grounded = true;
            double tx = danceX, ty = danceY;
            if (danceOnPerch)
            {
                RECT r;
                if (watcher.TryLive(perchHwnd, out r)) PerchPoint(r, out tx, out ty);
                else
                {
                    danceOnPerch = false;
                    RECT wa = ScreenUtil.WorkArea(X, Y);
                    danceX = Clamp(X, wa.Left + R * 2, wa.Right - R * 2);
                    danceY = wa.Bottom - R * 1.12;
                    tx = danceX; ty = danceY;
                }
            }
            Spring(tx, ty, dt, 30, 9);

            // Sway crosses the body once per beat, alternating sides; beats resync it.
            dancePhase += dt / Math.Max(0.25, beatInterval);
            double amp = R * (DanceMove == 2 ? 0.30 : 0.20);
            DanceSwayPx = Math.Sin(Math.Min(dancePhase, 1.0) * Math.PI) * amp * (DanceParity ? 1 : -1);
            DancePulse -= DancePulse * Math.Min(1, dt * 5);

            bool beat;
            if (music.MusicActive)
            {
                beat = music.BeatNow;                          // real beats from the speakers
                if (music.BeatInterval > 0.2) beatInterval = music.BeatInterval;
            }
            else
            {
                beatTimer -= dt;                               // forced dance, no music: 128 bpm
                beat = beatTimer <= 0;
                if (beat) { beatTimer += 0.469; beatInterval = 0.469; }
            }
            if (beat) OnDanceBeat();
        }

        void OnDanceBeat()
        {
            DancePulse = 1;
            DanceParity = !DanceParity;
            dancePhase = 0;
            beatCount++;
            if (beatCount % 8 == 0) DanceMove = (DanceMove + 1) % 3;
            if (beatCount % 16 == 0) Spin = rnd.NextDouble() < 0.5 ? 360 : -360;   // a quarter-turn twirl
            if (cfg.Chatty && rnd.NextDouble() < 0.04) SayText("♪", 1.3);
        }

        // ---- hologram glitch ----

        void UpdateGlitch(double dt)
        {
            if (!cfg.Glitch) { GlitchAmt = 0; return; }

            if (glitchBurstT > 0)
            {
                glitchBurstT -= dt;
                glitchSeedT -= dt;
                if (glitchSeedT <= 0)
                {
                    glitchSeedT = 0.05 + rnd.NextDouble() * 0.05;   // slices jump every few frames
                    GlitchSeed = rnd.Next(1, 1 << 30);
                }
                GlitchAmt = glitchBurstT > 0 ? 1 : 0;
            }
            else
            {
                GlitchAmt = 0;
                glitchNextT -= dt;
                if (glitchNextT <= 0)
                {
                    // mostly short flickers, occasionally a long bad-signal fit
                    glitchBurstT = 0.10 + rnd.NextDouble() * (rnd.NextDouble() < 0.25 ? 0.5 : 0.22);
                    glitchNextT = 2.0 + rnd.NextDouble() * 6.0;
                    GlitchSeed = rnd.Next(1, 1 << 30);
                    glitchSeedT = 0.06;
                }
            }
        }

        void DoSleep(double dt)
        {
            Spring(sleepX, sleepY, dt, 22, 9);
            Grounded = true;
            zT -= dt;
            if (zT <= 0) { zT = 1.8; Emit(2, 1); }
        }

        void EnterSleep()
        {
            State = PetState.Sleep;
            SetMood(Mood.Sleepy, 9999);
            Say = ""; SayT = 0;
            RECT r;
            if (watcher.TryLive(perchHwnd, out r))
            {
                PerchPoint(r, out sleepX, out sleepY);
            }
            else
            {
                RECT wa = ScreenUtil.WorkArea(X, Y);
                sleepX = Clamp(X, wa.Left + R * 1.5, wa.Right - R * 1.5);
                sleepY = wa.Bottom - R * 0.9;
            }
        }

        void WakeUp()
        {
            if (State != PetState.Sleep) return;
            State = PetState.Hover;
            NewWanderTarget();
            SetMood(Mood.Surprised, 0.9);
            Emit(0, 5);
            perchIdleT = 4;
        }

        void DoDrag(double dt)
        {
            Grounded = false;
            Tilt += (Clamp(-dragVX * 0.016, -26, 26) - Tilt) * Math.Min(1, dt * 10);
        }

        void DoToss(double dt)
        {
            tossT += dt;
            VY += Gravity * dt;
            VX *= (1 - 0.32 * dt);
            X += VX * dt; Y += VY * dt;
            Spin += spinVel * dt;
            spinVel *= (1 - 1.1 * dt);
            Grounded = false;

            RECT wa = ScreenUtil.WorkArea(X, Y);
            bool floor = false;
            if (Y > wa.Bottom - R) { Y = wa.Bottom - R; VY = -VY * 0.5; VX *= 0.74; floor = true; if (Math.Abs(VY) > 260) Emit(0, 3); }
            if (Y < wa.Top + R) { Y = wa.Top + R; VY = Math.Abs(VY) * 0.4; }
            if (X < wa.Left + R) { X = wa.Left + R; VX = Math.Abs(VX) * 0.58; Emit(0, 2); }
            if (X > wa.Right - R) { X = wa.Right - R; VX = -Math.Abs(VX) * 0.58; Emit(0, 2); }

            double sp = Math.Sqrt(VX * VX + VY * VY);
            if (floor && sp < 120) settleT += dt; else settleT = 0;

            if (settleT > 0.45 || tossT > 7)
            {
                SetMood(Mood.Dizzy, 1.2);
                State = PetState.Hover;
                NewWanderTarget();
                Emit(0, 6);
            }
        }

        void Startle(double cx, double cy, double cursorSpeed)
        {
            if (startleCool > 0) return;
            if (State != PetState.Hover && State != PetState.Perch && State != PetState.Dance) return;
            if (cursorSpeed < 1500) return;
            double d = Dist(cx, cy, X, Y);
            if (d > R * 1.7) return;

            startleCool = 4;
            SetMood(Mood.Surprised, 1.0);
            Emit(3, 1);
            double dx = X - cx, dy = Y - cy, len = Math.Max(1, Math.Sqrt(dx * dx + dy * dy));
            VX += dx / len * 620;
            VY += dy / len * 620 - 180;
            if (State == PetState.Perch) LeavePerch(true);
            else if (State == PetState.Dance) { danceCool = 3; danceOnPerch = false; LeaveDance(); }
        }

        void OnForegroundChanged(DeskWindow w)
        {
            if (!cfg.Perch) return;
            if (State == PetState.Drag || State == PetState.Toss || State == PetState.Dance) return;
            if (noticeCool > 0) return;
            noticeCool = 6;
            WakeUp();
            SetMood(Mood.Curious, 1.5);
            Emit(3, 1);
            if (cfg.Chatty && rnd.NextDouble() < 0.18 && w.AppName.Length > 0)
                SayText("ooh, " + w.AppName, 2.6);
            GoPerch(w);
        }

        // ================= face, motion, particles =================

        void UpdateFace(double dt, double cx, double cy)
        {
            double tlx = 0, tly = 0;
            if (State != PetState.Sleep)
            {
                tlx = Clamp((cx - X) / 320.0, -1, 1);
                tly = Clamp((cy - (Y - R * 0.1)) / 320.0, -1, 1);
            }
            LookX += (tlx - LookX) * Math.Min(1, dt * 8);
            LookY += (tly - LookY) * Math.Min(1, dt * 8);

            if (State == PetState.Sleep)
            {
                Blink = 1;
            }
            else
            {
                blinkT -= dt;
                if (blinkT <= 0 && blinkPhase <= 0) { blinkT = 2.4 + rnd.NextDouble() * 4.5; blinkPhase = 0.17; }
                if (blinkPhase > 0)
                {
                    blinkPhase -= dt;
                    double u = 1 - Math.Max(0, blinkPhase) / 0.17;
                    Blink = Math.Sin(Clamp(u, 0, 1) * Math.PI);
                }
                else Blink = 0;
            }

            HoverPop += ((Hovered ? 1.0 : 0.0) - HoverPop) * Math.Min(1, dt * 10);
            Bob = State == PetState.Dance
                ? -R * 0.28 * DancePulse                                   // hop on the beat
                : Math.Sin(t * 2.2) * R * (Grounded ? 0.035 : 0.07);

            double sp = Math.Sqrt(VX * VX + VY * VY);
            double sq = Clamp((sp - 150) / 2600.0, 0, 0.16);
            if (State == PetState.Dance) sq = 0.13 * DancePulse;           // chunky beat squash
            Squash += (sq - Squash) * Math.Min(1, dt * 8);

            if (State != PetState.Drag)
            {
                double tt = Clamp(VX * 0.014, -16, 16);
                Tilt += (tt - Tilt) * Math.Min(1, dt * 6);
            }

            // Spin is only for tumbling through the air; otherwise settle back upright.
            if (State != PetState.Toss) Spin += (0 - Spin) * Math.Min(1, dt * 7);
            if (Spin > 3600 || Spin < -3600) Spin = Spin % 360;
        }

        void UpdateParticles(double dt)
        {
            for (int i = Parts.Count - 1; i >= 0; i--)
            {
                Particle p = Parts[i];
                p.Life -= dt;
                if (p.Life <= 0) { Parts.RemoveAt(i); continue; }
                p.X += p.VX * dt;
                p.Y += p.VY * dt;
                if (p.Kind == 0) { p.VY += 260 * dt; p.VX *= (1 - 1.4 * dt); }
                if (p.Kind == 1) { p.VY -= 40 * dt; p.VX = Math.Sin(p.Life * 6 + p.Rot) * 26; }
                if (p.Kind == 2) { p.VX = 22 + Math.Sin(p.Life * 3) * 10; }
                if (p.Kind == 3) { p.VY *= (1 - 2.0 * dt); }
                p.Rot += dt * (p.Kind == 0 ? 200 : 30);
            }
        }

        public void Emit(int kind, int count)
        {
            for (int i = 0; i < count && Parts.Count < 70; i++)
            {
                Particle p = new Particle();
                p.Kind = kind;
                p.Rot = rnd.NextDouble() * 360;
                if (kind == 0)
                {
                    double a = rnd.NextDouble() * Math.PI * 2, sp = 70 + rnd.NextDouble() * 150;
                    p.X = Math.Cos(a) * R * 0.5; p.Y = Math.Sin(a) * R * 0.5;
                    p.VX = Math.Cos(a) * sp; p.VY = Math.Sin(a) * sp - 60;
                    p.MaxLife = p.Life = 0.5 + rnd.NextDouble() * 0.45;
                    p.Size = R * (0.09 + rnd.NextDouble() * 0.09);
                }
                else if (kind == 1)
                {
                    p.X = (rnd.NextDouble() - 0.5) * R * 1.1; p.Y = -R * 0.35;
                    p.VX = (rnd.NextDouble() - 0.5) * 40; p.VY = -70 - rnd.NextDouble() * 70;
                    p.MaxLife = p.Life = 1.0 + rnd.NextDouble() * 0.5;
                    p.Size = R * (0.15 + rnd.NextDouble() * 0.08);
                }
                else if (kind == 2)
                {
                    p.X = R * 0.5; p.Y = -R * 0.55;
                    p.VX = 24; p.VY = -30;
                    p.MaxLife = p.Life = 2.2;
                    p.Size = R * 0.3;
                }
                else
                {
                    p.X = R * 0.05; p.Y = -R * 1.0;
                    p.VX = 0; p.VY = -70;
                    p.MaxLife = p.Life = 0.95;
                    p.Size = R * 0.42;
                }
                Parts.Add(p);
            }
        }

        void NewWanderTarget()
        {
            RECT wa = ScreenUtil.WorkArea(X, Y);
            double m = R * 1.6;
            wanderX = wa.Left + m + rnd.NextDouble() * Math.Max(10, wa.Width - m * 2);
            wanderY = wa.Top + m + rnd.NextDouble() * Math.Max(10, wa.Height * 0.72 - m);
            wanderT = 3.5 + rnd.NextDouble() * 5.5;
        }

        void Spring(double tx, double ty, double dt, double k, double damp)
        {
            VX += ((tx - X) * k - VX * damp) * dt;
            VY += ((ty - Y) * k - VY * damp) * dt;
            double sp = Math.Sqrt(VX * VX + VY * VY);
            if (sp > 2600) { VX = VX / sp * 2600; VY = VY / sp * 2600; }
            X += VX * dt;
            Y += VY * dt;
        }

        void ClampToVirtual()
        {
            RECT v = ScreenUtil.Virtual();
            double m = R * 0.35;
            if (X < v.Left + m) { X = v.Left + m; if (VX < 0) VX = 0; }
            if (X > v.Right - m) { X = v.Right - m; if (VX > 0) VX = 0; }
            if (Y < v.Top + m) { Y = v.Top + m; if (VY < 0) VY = 0; }
            if (Y > v.Bottom - m) { Y = v.Bottom - m; if (VY > 0) VY = 0; }
        }

        // Moving the pet only moves its window, which costs nothing to redraw. This is a
        // hash of everything that actually changes the picture, so a pet that is drifting
        // across the screen without changing pose repaints zero times.
        public int VisualSignature(double u)
        {
            unchecked
            {
                int h = 17;
                h = h * 31 + (int)Mood;
                h = h * 31 + (State == PetState.Toss ? 1 : 0);
                h = h * 31 + (Grounded ? 1 : 0);
                h = h * 31 + (int)Math.Round(Bob);
                h = h * 31 + (Blink > 0.55 ? 1 : 0) + (int)Math.Round(Blink * 6);
                h = h * 31 + (int)Math.Round(LookX * 0.55 * u);
                h = h * 31 + (int)Math.Round(LookY * 0.45 * u);
                h = h * 31 + (Squash > 0.07 ? 1 : 0);
                h = h * 31 + (int)Math.Round(Spin / 90.0);
                h = h * 31 + (int)Math.Round(Appear * 24);
                h = h * 31 + (int)Math.Round(HoverPop * 8);
                h = h * 31 + Parts.Count;
                for (int i = 0; i < Parts.Count; i++)   // 2px steps: fewer repaints, still reads as pixel art
                    h = h * 31 + (int)Math.Round(Parts[i].X / 2) * 7 + (int)Math.Round(Parts[i].Y / 2);
                if (SayT > 0 && Say.Length > 0)
                    h = h * 31 + Say.GetHashCode() + (int)Math.Round(SayT * 4);
                if (Grounded && Math.Abs(VX) > 25) h = h * 31 + (int)Math.Round(t * 18);
                h = h * 31 + (int)Math.Round(DanceSwayPx);
                h = h * 31 + (int)Math.Round(DancePulse * 12);
                h = h * 31 + (DanceParity ? 1 : 0) + DanceMove * 2;
                if (GlitchAmt > 0.01) { h = h * 31 + GlitchSeed; h = h * 31 + 1; }
                return h;
            }
        }

        public void SetMood(Mood m, double secs) { Mood = m; moodT = secs; }
        public void SayText(string s, double secs) { Say = s; SayT = secs; }

        static void Tick(ref double v, double dt) { if (v > 0) v -= dt; }
        static double Dist(double ax, double ay, double bx, double by)
        {
            double dx = ax - bx, dy = ay - by;
            return Math.Sqrt(dx * dx + dy * dy);
        }
        public static double Clamp(double v, double lo, double hi)
        {
            return v < lo ? lo : (v > hi ? hi : v);
        }
    }
}
