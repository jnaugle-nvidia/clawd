using System;
using System.Collections.Generic;
using System.IO;
using System.Web.Script.Serialization;

namespace Clawd
{
    // What Claude Code is doing, as told by its hooks. Claude Code runs Clawd's own exe
    // with --hook on every event; that copy writes one line here and exits at once:
    //
    //   %APPDATA%\Clawd\claude-activity
    //
    // The line is tab-separated: event, tool, detail, session. The running Clawd polls the
    // file's modification time.
    public class ClaudeEvent
    {
        public string Event = "", Tool = "", Detail = "", Session = "";
    }

    public class ClaudeWatch
    {
        public static string FilePath { get { return Path.Combine(Settings.Dir, "claude-activity"); } }

        DateTime lastStamp;
        double pollT;

        public ClaudeWatch()
        {
            lastStamp = Stamp();   // anything written before launch is old news
        }

        // Returns the newest event when the file has been written since the last check.
        public ClaudeEvent Poll(double dt)
        {
            pollT -= dt;
            if (pollT > 0) return null;
            pollT = 0.2;

            DateTime stamp = Stamp();
            if (stamp <= lastStamp) return null;
            lastStamp = stamp;

            string text;
            try { text = File.ReadAllText(FilePath); }
            catch { return null; }
            string[] f = text.TrimEnd('\r', '\n').Split('\t');
            ClaudeEvent e = new ClaudeEvent();
            if (f.Length > 0) e.Event = f[0];
            if (f.Length > 1) e.Tool = f[1];
            if (f.Length > 2) e.Detail = f[2];
            if (f.Length > 3) e.Session = f[3];
            return e.Event.Length == 0 ? null : e;
        }

        static DateTime Stamp()
        {
            try { return File.Exists(FilePath) ? File.GetLastWriteTimeUtc(FilePath) : DateTime.MinValue; }
            catch { return DateTime.MinValue; }
        }

        // ---- the hook side: runs in a short-lived copy of Clawd, never the pet itself ----

        public static void RunHook()
        {
            Dictionary<string, object> e = null;
            try { e = new JavaScriptSerializer().DeserializeObject(Console.In.ReadToEnd()) as Dictionary<string, object>; }
            catch { }
            if (e == null) return;

            string ev = Str(e, "hook_event_name");
            if (ev.Length == 0) return;
            object input;
            e.TryGetValue("tool_input", out input);

            string[] fields = { ev, Str(e, "tool_name"), DetailOf(input as Dictionary<string, object>), Str(e, "session_id") };
            for (int i = 0; i < fields.Length; i++) fields[i] = fields[i].Replace('\t', ' ').Replace('\r', ' ').Replace('\n', ' ');

            try
            {
                Directory.CreateDirectory(Settings.Dir);
                string tmp = FilePath + "." + System.Diagnostics.Process.GetCurrentProcess().Id + ".tmp";   // hooks can overlap
                File.WriteAllText(tmp, string.Join("\t", fields));
                if (File.Exists(FilePath)) File.Replace(tmp, FilePath, null);
                else File.Move(tmp, FilePath);
            }
            catch { }
        }

        // The one thing worth saying about a tool call: a file name, a search, a host, a command.
        static string DetailOf(Dictionary<string, object> i)
        {
            if (i == null) return "";
            foreach (string k in new[] { "file_path", "notebook_path", "path" })
            {
                string f = Str(i, k);
                if (f.Length > 0) return Path.GetFileName(f.TrimEnd('/', '\\'));
            }
            foreach (string k in new[] { "pattern", "query" })
            {
                string s = Str(i, k);
                if (s.Length > 0) return s;
            }
            string url = Str(i, "url");
            if (url.Length > 0)
            {
                Uri u;
                return Uri.TryCreate(url, UriKind.Absolute, out u) ? u.Host : url;
            }
            string cmd = Str(i, "command");
            if (cmd.Length > 0) return cmd;
            return Str(i, "description");
        }

        static string Str(Dictionary<string, object> d, string key)
        {
            object v;
            return d.TryGetValue(key, out v) && v is string ? (string)v : "";
        }
    }
}
