using System;
using System.Runtime.InteropServices;
using System.Text;

namespace Clawd
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
        public int Width { get { return Right - Left; } }
        public int Height { get { return Bottom - Top; } }
        public bool Valid { get { return Right > Left && Bottom > Top; } }
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO
    {
        public uint cbSize;
        public uint dwTime;
    }

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    // Thin Win32 layer. Everything here works in physical screen pixels.
    public static class Native
    {
        public const int GWL_EXSTYLE = -20;
        public const int WS_EX_TOOLWINDOW = 0x00000080;
        public const int WS_EX_NOACTIVATE = 0x08000000;
        public const int WS_EX_TRANSPARENT = 0x00000020;

        public const uint SWP_NOSIZE = 0x0001;
        public const uint SWP_NOMOVE = 0x0002;
        public const uint SWP_NOZORDER = 0x0004;
        public const uint SWP_NOACTIVATE = 0x0010;
        public const uint SWP_SHOWWINDOW = 0x0040;
        public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);

        public const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;
        public const int DWMWA_CLOAKED = 14;

        [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
        [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
        [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
        [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder s, int max);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder s, int max);
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
        [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LASTINPUTINFO p);
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [DllImport("kernel32.dll")] public static extern uint GetTickCount();
        [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hWnd, int attr, out RECT val, int size);
        [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hWnd, int attr, out int val, int size);

        // Seconds since the user last touched keyboard or mouse.
        public static double IdleSeconds()
        {
            LASTINPUTINFO li = new LASTINPUTINFO();
            li.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
            if (!GetLastInputInfo(ref li)) return 0;
            return unchecked(GetTickCount() - li.dwTime) / 1000.0;
        }

        // Visible bounds of a window, excluding the invisible resize border.
        public static bool TryFrameBounds(IntPtr h, out RECT r)
        {
            r = new RECT();
            int size = Marshal.SizeOf(typeof(RECT));
            if (DwmGetWindowAttribute(h, DWMWA_EXTENDED_FRAME_BOUNDS, out r, size) == 0 && r.Valid)
                return true;
            return GetWindowRect(h, out r) && r.Valid;
        }

        public static bool IsCloaked(IntPtr h)
        {
            int cloaked;
            if (DwmGetWindowAttribute(h, DWMWA_CLOAKED, out cloaked, 4) == 0)
                return cloaked != 0;
            return false;
        }

        public static string TextOf(IntPtr h)
        {
            int len = GetWindowTextLength(h);
            if (len <= 0) return "";
            StringBuilder sb = new StringBuilder(len + 2);
            GetWindowText(h, sb, sb.Capacity);
            return sb.ToString();
        }

        [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
        [DllImport("kernel32.dll")] static extern bool SetProcessWorkingSetSize(IntPtr h, IntPtr min, IntPtr max);

        // Ask Windows to page out what startup allocated. It comes back on demand.
        public static void Trim()
        {
            try
            {
                GC.Collect();
                GC.WaitForPendingFinalizers();
                SetProcessWorkingSetSize(GetCurrentProcess(), new IntPtr(-1), new IntPtr(-1));
            }
            catch { }
        }

        public static string ClassOf(IntPtr h)
        {
            StringBuilder sb = new StringBuilder(160);
            GetClassName(h, sb, sb.Capacity);
            return sb.ToString();
        }
    }

    public static class ScreenUtil
    {
        public static RECT WorkArea(double x, double y)
        {
            System.Drawing.Rectangle w = System.Windows.Forms.Screen
                .FromPoint(new System.Drawing.Point((int)x, (int)y)).WorkingArea;
            RECT r = new RECT();
            r.Left = w.Left; r.Top = w.Top; r.Right = w.Right; r.Bottom = w.Bottom;
            return r;
        }

        public static RECT Virtual()
        {
            System.Drawing.Rectangle v = System.Windows.Forms.SystemInformation.VirtualScreen;
            RECT r = new RECT();
            r.Left = v.Left; r.Top = v.Top; r.Right = v.Right; r.Bottom = v.Bottom;
            return r;
        }
    }
}
