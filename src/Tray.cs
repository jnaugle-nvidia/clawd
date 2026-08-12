using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

namespace Clawd
{
    // Notification-area icon and menu. The icon is drawn at runtime, so there are no image files.
    public class Tray : IDisposable
    {
        const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        const string RunName = "Clawd";

        [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr h);

        readonly Settings cfg;
        readonly Overlay overlay;
        readonly NotifyIcon icon;
        readonly ContextMenuStrip menu;
        IntPtr hIcon = IntPtr.Zero;

        ToolStripMenuItem miFollow, miPerch, miChatty, miThrough, miPause, miStartup;
        ToolStripMenuItem miDance, miGlitch;
        ToolStripMenuItem miSmall, miMedium, miLarge;

        public Tray(Settings cfg, Overlay overlay)
        {
            this.cfg = cfg;
            this.overlay = overlay;

            menu = new ContextMenuStrip();
            menu.ShowImageMargin = false;

            ToolStripMenuItem title = new ToolStripMenuItem("Clawd");
            title.Enabled = false;
            menu.Items.Add(title);
            menu.Items.Add(new ToolStripSeparator());

            Add("Come here", delegate { overlay.Pet.ComeHere(); });
            Add("Say something", delegate { overlay.Pet.Speak(); });
            Add("Dance!", delegate { overlay.Pet.ForceDance(); });
            menu.Items.Add(new ToolStripSeparator());

            miFollow = Add("Follow my cursor", delegate
            {
                cfg.FollowCursor = !cfg.FollowCursor;
                cfg.Save();
            });
            miPerch = Add("Perch on windows", delegate
            {
                cfg.Perch = !cfg.Perch;
                cfg.Save();
            });
            miDance = Add("Dance to music", delegate
            {
                cfg.Dance = !cfg.Dance;
                cfg.Save();
            });
            miGlitch = Add("Hologram glitch", delegate
            {
                cfg.Glitch = !cfg.Glitch;
                cfg.Save();
            });
            miChatty = Add("Chatty", delegate
            {
                cfg.Chatty = !cfg.Chatty;
                cfg.Save();
            });
            miThrough = Add("Click through pet", delegate
            {
                cfg.ClickThrough = !cfg.ClickThrough;
                overlay.ApplyClickThrough();
                cfg.Save();
            });

            ToolStripMenuItem size = new ToolStripMenuItem("Size");
            miSmall = SizeItem(size, "Small", 0.72);
            miMedium = SizeItem(size, "Medium", 1.0);
            miLarge = SizeItem(size, "Large", 1.45);
            menu.Items.Add(size);

            menu.Items.Add(new ToolStripSeparator());
            miPause = Add("Pause", delegate { overlay.SetPaused(!cfg.Paused); });
            miStartup = Add("Start with Windows", delegate { SetStartup(!IsStartupEnabled()); });
            menu.Items.Add(new ToolStripSeparator());
            Add("Quit", delegate { Quit(); });

            menu.Opening += delegate { Refresh(); };

            icon = new NotifyIcon();
            icon.Icon = BuildIcon(32);
            icon.Text = "Clawd";
            icon.Visible = true;
            icon.ContextMenuStrip = menu;
            icon.MouseDoubleClick += delegate(object s, MouseEventArgs e)
            {
                if (e.Button == MouseButtons.Left) overlay.Pet.ComeHere();
            };
        }

        ToolStripMenuItem Add(string text, EventHandler onClick)
        {
            ToolStripMenuItem mi = new ToolStripMenuItem(text);
            mi.Click += onClick;
            menu.Items.Add(mi);
            return mi;
        }

        ToolStripMenuItem SizeItem(ToolStripMenuItem parent, string text, double scale)
        {
            ToolStripMenuItem mi = new ToolStripMenuItem(text);
            mi.Click += delegate
            {
                cfg.Scale = scale;
                overlay.ApplyScale();
                overlay.Pet.Emit(0, 8);
                cfg.Save();
            };
            parent.DropDownItems.Add(mi);
            return mi;
        }

        void Refresh()
        {
            miFollow.Checked = cfg.FollowCursor;
            miPerch.Checked = cfg.Perch;
            miDance.Checked = cfg.Dance;
            miGlitch.Checked = cfg.Glitch;
            miChatty.Checked = cfg.Chatty;
            miThrough.Checked = cfg.ClickThrough;
            miPause.Checked = cfg.Paused;
            miStartup.Checked = IsStartupEnabled();
            miSmall.Checked = cfg.Scale < 0.85;
            miMedium.Checked = cfg.Scale >= 0.85 && cfg.Scale < 1.2;
            miLarge.Checked = cfg.Scale >= 1.2;
        }

        public void ShowMenu()
        {
            Refresh();
            menu.Show(Control.MousePosition);
        }

        // ---- start with Windows ----

        static string ExePath
        {
            get { return System.Reflection.Assembly.GetExecutingAssembly().Location; }
        }

        public static bool IsStartupEnabled()
        {
            try
            {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(RunKey, false))
                {
                    if (k == null) return false;
                    object v = k.GetValue(RunName);
                    return v != null;
                }
            }
            catch { return false; }
        }

        void SetStartup(bool on)
        {
            try
            {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(RunKey, true))
                {
                    if (k == null) return;
                    if (on) k.SetValue(RunName, "\"" + ExePath + "\"");
                    else k.DeleteValue(RunName, false);
                }
            }
            catch { }
        }

        // ---- runtime-drawn icon ----

        public Icon BuildIcon(int size)
        {
            Bitmap bmp = new Bitmap(size, size, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.None;      // pixel art: no antialiasing
                g.PixelOffsetMode = PixelOffsetMode.Half;
                g.Clear(Color.Transparent);

                float u = size / 12.6f;
                float cx = size / 2f;
                float cy = size / 2f - 0.5f * u;           // sprite spans -4..+5 units

                using (SolidBrush coral = new SolidBrush(Color.FromArgb(0xD9, 0x77, 0x57)))
                    foreach (RectangleF r in CrabRects(u))
                        g.FillRectangle(coral, Snap(cx + r.X), Snap(cy + r.Y),
                                        Snap(r.Width), Snap(r.Height));

                float e = Math.Max(1f, Snap(u * 1.7));
                using (SolidBrush ink = new SolidBrush(Color.FromArgb(0x18, 0x14, 0x12)))
                {
                    g.FillRectangle(ink, Snap(cx - 2.6f * u - e / 2), Snap(cy - 2.05f * u - e / 2), e, e);
                    g.FillRectangle(ink, Snap(cx + 2.6f * u - e / 2), Snap(cy - 2.05f * u - e / 2), e, e);
                }
            }

            IntPtr h = bmp.GetHicon();
            hIcon = h;
            Icon ic = Icon.FromHandle(h);
            bmp.Dispose();
            return ic;
        }

        static float Snap(double v) { return (float)Math.Round(v); }

        // Clawd's silhouette on the unit grid, matching Character.BuildParts.
        public static RectangleF[] CrabRects(float u)
        {
            System.Collections.Generic.List<RectangleF> l = new System.Collections.Generic.List<RectangleF>();
            l.Add(new RectangleF(-5 * u, -4 * u, 10 * u, 7 * u));     // body
            l.Add(new RectangleF(-6 * u, -2 * u, 1 * u, 2 * u));      // left claw
            l.Add(new RectangleF(5 * u, -2 * u, 1 * u, 2 * u));       // right claw
            float[] lx = new float[] { -5f, -2.25f, 0.5f, 3.25f };
            for (int i = 0; i < 4; i++)
                l.Add(new RectangleF(lx[i] * u, 3 * u, 1.75f * u, 2 * u));
            l.Add(new RectangleF(-0.5f * u, 3 * u, 1 * u, 1 * u));    // shallow middle notch
            return l.ToArray();
        }

        void Quit()
        {
            Dispose();
            System.Windows.Application.Current.Shutdown();
        }

        public void Dispose()
        {
            try
            {
                icon.Visible = false;
                icon.Dispose();
                menu.Dispose();
                if (hIcon != IntPtr.Zero) { DestroyIcon(hIcon); hIcon = IntPtr.Zero; }
            }
            catch { }
        }
    }
}
