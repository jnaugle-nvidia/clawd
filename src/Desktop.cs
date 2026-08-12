using System;
using System.Collections.Generic;
using System.Diagnostics;

namespace Clawd
{
    public class DeskWindow
    {
        public IntPtr Hwnd;
        public RECT R;
        public string Title;
        public string Cls;

        // Friendly app name out of a window title:
        // "Program.cs - Toolz - Visual Studio Code" => "Visual Studio Code"
        public string AppName
        {
            get
            {
                if (string.IsNullOrEmpty(Title)) return "";
                string[] seps = new string[] { " - ", " — ", " | " };
                string[] parts = Title.Split(seps, StringSplitOptions.RemoveEmptyEntries);
                string last = parts.Length > 0 ? parts[parts.Length - 1].Trim() : Title.Trim();
                if (last.Length > 24) last = last.Substring(0, 23).TrimEnd() + "…";
                return last;
            }
        }
    }

    // Keeps a live picture of the visible top-level windows on the desktop.
    public class WindowWatcher
    {
        public List<DeskWindow> Windows = new List<DeskWindow>();
        public IntPtr Foreground = IntPtr.Zero;

        public event Action<DeskWindow> ForegroundChanged;

        readonly uint ownPid;
        readonly EnumWindowsProc callback;
        List<DeskWindow> scratch = new List<DeskWindow>();

        static readonly string[] SkipClasses = new string[]
        {
            "Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd",
            "NotifyIconOverflowWindow", "Windows.UI.Core.CoreWindow",
            "TaskListThumbnailWnd", "ForegroundStaging", "XamlExplorerHostIslandWindow"
        };

        public WindowWatcher()
        {
            ownPid = (uint)Process.GetCurrentProcess().Id;
            callback = new EnumWindowsProc(OnWindow);
        }

        bool OnWindow(IntPtr h, IntPtr l)
        {
            if (!Native.IsWindowVisible(h) || Native.IsIconic(h)) return true;
            if (Native.GetWindowTextLength(h) == 0) return true;

            uint pid;
            Native.GetWindowThreadProcessId(h, out pid);
            if (pid == ownPid) return true;

            string cls = Native.ClassOf(h);
            for (int i = 0; i < SkipClasses.Length; i++)
                if (cls == SkipClasses[i]) return true;

            if (Native.IsCloaked(h)) return true;

            RECT r;
            if (!Native.TryFrameBounds(h, out r)) return true;
            if (r.Width < 220 || r.Height < 140) return true;

            RECT v = ScreenUtil.Virtual();
            if (r.Right < v.Left || r.Left > v.Right || r.Bottom < v.Top || r.Top > v.Bottom) return true;

            DeskWindow w = new DeskWindow();
            w.Hwnd = h; w.R = r; w.Cls = cls; w.Title = Native.TextOf(h);
            scratch.Add(w);
            return true;
        }

        // Rescan. Cheap enough to call a few times a second.
        public void Poll()
        {
            scratch = new List<DeskWindow>();
            try { Native.EnumWindows(callback, IntPtr.Zero); }
            catch { }
            Windows = scratch;

            IntPtr fg = Native.GetForegroundWindow();
            if (fg != Foreground)
            {
                Foreground = fg;
                DeskWindow dw = Find(fg);
                if (dw != null && ForegroundChanged != null) ForegroundChanged(dw);
            }
        }

        public DeskWindow Find(IntPtr h)
        {
            for (int i = 0; i < Windows.Count; i++)
                if (Windows[i].Hwnd == h) return Windows[i];
            return null;
        }

        // Fresh bounds straight from the OS, so a perched pet rides along as the window moves.
        public bool TryLive(IntPtr h, out RECT r)
        {
            r = new RECT();
            if (h == IntPtr.Zero) return false;
            if (!Native.IsWindow(h) || !Native.IsWindowVisible(h) || Native.IsIconic(h)) return false;
            if (Native.IsCloaked(h)) return false;
            return Native.TryFrameBounds(h, out r);
        }

        // A window worth visiting: usually the active one, sometimes another.
        public DeskWindow PickInteresting(Random rnd)
        {
            if (Windows.Count == 0) return null;
            DeskWindow fg = Find(Foreground);
            if (fg != null && rnd.NextDouble() < 0.65) return fg;
            return Windows[rnd.Next(Windows.Count)];
        }
    }
}
