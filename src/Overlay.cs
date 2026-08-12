using System;
using System.Diagnostics;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

namespace Clawd
{
    // The element the pet is painted onto. Draws in physical pixels.
    public class PetVisual : FrameworkElement
    {
        public Pet Target;
        public double Dpi = 1.0;
        public double CX, CY;   // pet centre inside the window, physical px

        protected override void OnRender(DrawingContext dc)
        {
            if (Target == null) return;
            dc.PushTransform(new ScaleTransform(1.0 / Dpi, 1.0 / Dpi));
            dc.PushTransform(new TranslateTransform(CX, CY));
            Character.Draw(dc, Target);
            dc.Pop();
            dc.Pop();
        }
    }

    public class Overlay : Window
    {
        public Pet Pet { get { return pet; } }
        public Action MenuRequested;

        readonly Settings cfg;
        readonly PetVisual visual = new PetVisual();
        readonly Pet pet;
        readonly Stopwatch clock = new Stopwatch();

        double dpi = 1.0;
        double lastT;
        double topmostT;
        int winW, winH;      // physical px
        IntPtr hwnd = IntPtr.Zero;

        bool dragging;
        double downX, downY, downTime;
        int lastSig = int.MinValue;
        int lastPosX = int.MinValue, lastPosY = int.MinValue;
        System.Windows.Threading.DispatcherTimer timer;
        bool trimmed;

        const int WM_MOUSEACTIVATE = 0x0021;
        const int MA_NOACTIVATE = 3;

        public Overlay(Settings cfg, WindowWatcher watcher)
        {
            this.cfg = cfg;
            pet = new Pet(cfg, watcher);

            WindowStyle = WindowStyle.None;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            ShowInTaskbar = false;
            Topmost = true;
            ResizeMode = ResizeMode.NoResize;
            SnapsToDevicePixels = true;
            Focusable = false;
            Title = "ClawdOverlay";
            Left = -4000; Top = -4000;   // off-screen until the first frame places it

            visual.Target = pet;
            // Pixel art: no antialiasing. Hard edges, and abutting rectangles meet without
            // the faint seam that half-covered edge pixels leave behind.
            RenderOptions.SetEdgeMode(visual, EdgeMode.Aliased);
            Content = visual;

            MouseLeftButtonDown += OnDown;
            MouseMove += OnMove;
            MouseLeftButtonUp += OnUp;
            MouseRightButtonUp += OnRight;
            MouseLeave += delegate { pet.Hovered = false; };

            clock.Start();
            // Deliberately not CompositionTarget.Rendering: subscribing to it holds WPF's
            // render loop open every frame forever. A timer lets the window sit idle, and
            // the pet only causes work when it moves or its pose changes.
            timer = new System.Windows.Threading.DispatcherTimer(System.Windows.Threading.DispatcherPriority.Send);
            timer.Interval = TimeSpan.FromMilliseconds(25);
            timer.Tick += OnFrame;
            timer.Start();
        }

        protected override void OnSourceInitialized(EventArgs e)
        {
            base.OnSourceInitialized(e);
            HwndSource src = (HwndSource)PresentationSource.FromVisual(this);
            hwnd = src.Handle;
            src.AddHook(Hook);

            if (src.CompositionTarget != null)
            {
                double m = src.CompositionTarget.TransformToDevice.M11;
                if (m > 0.1) dpi = m;
            }

            int ex = Native.GetWindowLong(hwnd, Native.GWL_EXSTYLE);
            ex |= Native.WS_EX_NOACTIVATE | Native.WS_EX_TOOLWINDOW;
            Native.SetWindowLong(hwnd, Native.GWL_EXSTYLE, ex);

            ApplyScale();
            ApplyClickThrough();
        }

        IntPtr Hook(IntPtr h, int msg, IntPtr w, IntPtr l, ref bool handled)
        {
            if (msg == WM_MOUSEACTIVATE)
            {
                handled = true;                    // never steal focus from the app underneath
                return new IntPtr(MA_NOACTIVATE);
            }
            return IntPtr.Zero;
        }

        // ---- sizing ----

        public void ApplyScale()
        {
            pet.R = 44.0 * dpi * cfg.Scale;   // R/5 is the pixel unit; the crab is ~12 units wide
            winW = (int)Math.Round(Math.Max(300 * dpi, pet.R * 5.4));
            winH = (int)Math.Round(Math.Max(280 * dpi, pet.R * 5.2));
            visual.Dpi = dpi;
            visual.CX = winW / 2.0;
            visual.CY = winH * 0.62;
            Width = winW / dpi;
            Height = winH / dpi;
            lastSig = int.MinValue;   // force a repaint at the new size
        }

        public void ApplyClickThrough()
        {
            if (hwnd == IntPtr.Zero) return;
            int ex = Native.GetWindowLong(hwnd, Native.GWL_EXSTYLE);
            if (cfg.ClickThrough) ex |= Native.WS_EX_TRANSPARENT;
            else ex &= ~Native.WS_EX_TRANSPARENT;
            Native.SetWindowLong(hwnd, Native.GWL_EXSTYLE, ex);
        }

        public void SetPaused(bool paused)
        {
            cfg.Paused = paused;
            if (paused) Hide();
            else { Show(); pet.SetMood(Mood.Happy, 1.4); pet.Emit(0, 6); }
        }

        // ---- frame loop ----

        void OnFrame(object sender, EventArgs e)
        {
            if (cfg.Paused) return;
            double now = clock.Elapsed.TotalSeconds;
            double dt = now - lastT;
            if (dt <= 0) return;
            lastT = now;
            if (dt > 0.25) dt = 0.25;

            // WPF's startup allocations never come back on their own; this is a tray app
            // that will sit here all day, so hand the pages back once things have settled.
            if (!trimmed && now > 6)
            {
                trimmed = true;
                Native.Trim();
            }

            try
            {
                if (dragging)
                {
                    POINT c;
                    Native.GetCursorPos(out c);
                    pet.DragTo(c.X, c.Y, dt);
                }

                pet.Update(dt);
                Reposition();

                int sig = pet.VisualSignature(pet.R / 5.0);
                if (sig != lastSig)
                {
                    lastSig = sig;
                    visual.InvalidateVisual();
                }

                topmostT -= dt;
                if (topmostT <= 0)
                {
                    topmostT = 2.0;
                    if (hwnd != IntPtr.Zero)
                        Native.SetWindowPos(hwnd, Native.HWND_TOPMOST, 0, 0, 0, 0,
                            Native.SWP_NOMOVE | Native.SWP_NOSIZE | Native.SWP_NOACTIVATE);

                    // Opt-in diagnostics: create %APPDATA%\Clawd\debug.on to get a
                    // once-a-second status line in status.txt. Delete it to stop.
                    try
                    {
                        string dir = Settings.Dir;
                        if (System.IO.File.Exists(System.IO.Path.Combine(dir, "debug.on")))
                        {
                            MusicMeter m = pet.Music;
                            System.IO.File.WriteAllText(System.IO.Path.Combine(dir, "status.txt"),
                                "state=" + pet.State +
                                " meter=" + m.MeterState +
                                " active=" + m.MusicActive +
                                " env=" + m.Env.ToString("0.000") +
                                " avg=" + m.Avg.ToString("0.000") +
                                " beatIv=" + m.BeatInterval.ToString("0.00") +
                                " glitch=" + pet.GlitchAmt.ToString("0.0") +
                                " pos=" + (int)pet.X + "," + (int)pet.Y);
                        }
                    }
                    catch { }
                }
            }
            catch (Exception ex)
            {
                Log.Once(ex);
            }
        }

        void Reposition()
        {
            if (hwnd == IntPtr.Zero) return;
            int x = (int)Math.Round(pet.X - visual.CX);
            int y = (int)Math.Round(pet.Y - visual.CY);
            if (x == lastPosX && y == lastPosY) return;
            lastPosX = x; lastPosY = y;
            Native.SetWindowPos(hwnd, IntPtr.Zero, x, y, 0, 0,
                Native.SWP_NOSIZE | Native.SWP_NOZORDER | Native.SWP_NOACTIVATE);
        }

        // ---- input ----

        // The crab is a box, not a disc: claws out to +-6.5 units, legs down to 5.5.
        bool OverPet(double sx, double sy)
        {
            double u = pet.R / 5.0;
            double dx = sx - pet.X, dy = sy - (pet.Y + pet.Bob);
            return dx >= -6.6 * u && dx <= 6.6 * u && dy >= -4.6 * u && dy <= 5.6 * u;
        }

        void OnDown(object s, MouseButtonEventArgs e)
        {
            POINT c;
            Native.GetCursorPos(out c);
            if (!OverPet(c.X, c.Y)) return;

            dragging = true;
            downX = c.X; downY = c.Y;
            downTime = clock.Elapsed.TotalSeconds;
            pet.BeginDrag(c.X, c.Y);
            CaptureMouse();
            e.Handled = true;
        }

        void OnMove(object s, MouseEventArgs e)
        {
            POINT c;
            Native.GetCursorPos(out c);
            pet.Hovered = OverPet(c.X, c.Y);
        }

        void OnUp(object s, MouseButtonEventArgs e)
        {
            if (!dragging) return;
            dragging = false;
            ReleaseMouseCapture();

            POINT c;
            Native.GetCursorPos(out c);
            double moved = Math.Sqrt((c.X - downX) * (c.X - downX) + (c.Y - downY) * (c.Y - downY));
            double held = clock.Elapsed.TotalSeconds - downTime;
            pet.EndDrag(moved < 6 && held < 0.45);
            e.Handled = true;
        }

        void OnRight(object s, MouseButtonEventArgs e)
        {
            POINT c;
            Native.GetCursorPos(out c);
            if (!OverPet(c.X, c.Y)) return;
            if (MenuRequested != null) MenuRequested();
            e.Handled = true;
        }
    }

    public static class Log
    {
        static bool written;

        public static void Once(Exception ex)
        {
            if (written) return;
            written = true;
            try
            {
                System.IO.Directory.CreateDirectory(Settings.Dir);
                System.IO.File.WriteAllText(
                    System.IO.Path.Combine(Settings.Dir, "error.log"),
                    DateTime.Now.ToString("u") + Environment.NewLine + ex.ToString());
            }
            catch { }
        }
    }
}
