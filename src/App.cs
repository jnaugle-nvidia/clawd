using System;
using System.Threading;
using System.Windows;

namespace Clawd
{
    public class App
    {
        [STAThread]
        public static void Main()
        {
            // Claude Code runs this same exe as its hook: record the event and leave at once,
            // before any window, mutex or tray icon exists.
            if (Array.IndexOf(Environment.GetCommandLineArgs(), "--hook") > 0) { ClaudeWatch.RunHook(); return; }

            bool created;
            using (Mutex mtx = new Mutex(true, "Clawd.SingleInstance.v1", out created))
            {
                if (!created) return;   // already running

                Native.SetProcessDPIAware();
                System.Windows.Forms.Application.EnableVisualStyles();

                Settings cfg = Settings.Load();
                WindowWatcher watcher = new WindowWatcher();
                watcher.Poll();

                Application app = new Application();
                app.ShutdownMode = ShutdownMode.OnExplicitShutdown;

                Overlay overlay = new Overlay(cfg, watcher);
                Tray tray = new Tray(cfg, overlay);
                overlay.MenuRequested = tray.ShowMenu;

                overlay.Show();
                overlay.Pet.SayText("hi :)", 3.2);

                try { app.Run(); }
                finally { tray.Dispose(); }

                GC.KeepAlive(mtx);
            }
        }
    }
}
