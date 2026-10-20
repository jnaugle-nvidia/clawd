using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;

namespace Clawd
{
    public enum ClaudeHookStatus { NotConnected, Connected, Outdated }

    // Adds Clawd's hooks to %USERPROFILE%\.claude\settings.json, or takes them out again.
    // Everything else in that file is left alone, and a copy is kept next to it before
    // every change.
    public static class ClaudeHooks
    {
        // The events Clawd acts on. Each runs this exe with --hook.
        static readonly string[] Events =
        {
            "UserPromptSubmit", "PreToolUse", "PostToolUseFailure", "PreCompact",
            "Stop", "Notification", "SessionEnd"
        };

        // Claude Code reads CLAUDE_CONFIG_DIR in place of ~/.claude when it is set.
        static string SettingsPath
        {
            get
            {
                string dir = Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR");
                if (!string.IsNullOrEmpty(dir)) return Path.Combine(dir, "settings.json");
                return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                                    ".claude", "settings.json");
            }
        }

        static string ExePath
        {
            get { return System.Diagnostics.Process.GetCurrentProcess().MainModule.FileName; }
        }

        public static ClaudeHookStatus CurrentStatus()
        {
            Dictionary<string, object> s;
            try { s = Load(); } catch { return ClaudeHookStatus.NotConnected; }
            Dictionary<string, object> hooks = Get(s, "hooks") as Dictionary<string, object>;
            if (hooks == null) return ClaudeHookStatus.NotConnected;

            int found = 0, current = 0;
            foreach (string ev in Events)
            {
                foreach (Dictionary<string, object> h in Handlers(Get(hooks, ev)))
                {
                    if (!IsOurs(h)) continue;
                    found++;
                    if (string.Equals(Get(h, "command") as string, ExePath, StringComparison.OrdinalIgnoreCase))
                    {
                        current++;
                        break;
                    }
                }
            }
            if (found == 0) return ClaudeHookStatus.NotConnected;
            return current == Events.Length ? ClaudeHookStatus.Connected : ClaudeHookStatus.Outdated;
        }

        // Returns null on success, or what went wrong.
        public static string Connect() { return Rewrite(true); }
        public static string Disconnect() { return Rewrite(false); }

        static string Rewrite(bool add)
        {
            Dictionary<string, object> s;
            try { s = Load(); }
            catch { return "Couldn't read " + SettingsPath + ": it isn't valid JSON, so Clawd left it alone."; }

            Dictionary<string, object> hooks = Get(s, "hooks") as Dictionary<string, object>;
            if (hooks == null) hooks = new Dictionary<string, object>();

            // Out with every old Clawd hook first, whichever copy of Clawd wrote it.
            foreach (string ev in new List<string>(hooks.Keys))
            {
                object[] groups = hooks[ev] as object[];
                if (groups == null) continue;
                List<object> kept = new List<object>();
                foreach (object go in groups)
                {
                    Dictionary<string, object> g = go as Dictionary<string, object>;
                    if (g == null) { kept.Add(go); continue; }
                    List<object> hs = new List<object>();
                    object[] list = Get(g, "hooks") as object[];
                    if (list != null)
                        foreach (object h in list)
                            if (!(h is Dictionary<string, object>) || !IsOurs((Dictionary<string, object>)h)) hs.Add(h);
                    if (hs.Count == 0) continue;
                    g["hooks"] = hs.ToArray();
                    kept.Add(g);
                }
                if (kept.Count == 0) hooks.Remove(ev);
                else hooks[ev] = kept.ToArray();
            }

            if (add)
            {
                foreach (string ev in Events)
                {
                    Dictionary<string, object> mine = new Dictionary<string, object>();
                    mine["type"] = "command";
                    mine["command"] = ExePath;
                    mine["args"] = new object[] { "--hook" };
                    mine["timeout"] = 5;
                    Dictionary<string, object> group = new Dictionary<string, object>();
                    group["hooks"] = new object[] { mine };

                    List<object> groups = new List<object>();
                    object[] old = Get(hooks, ev) as object[];
                    if (old != null) groups.AddRange(old);
                    groups.Add(group);
                    hooks[ev] = groups.ToArray();
                }
            }

            if (hooks.Count == 0) s.Remove("hooks");
            else s["hooks"] = hooks;

            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(SettingsPath));
                if (File.Exists(SettingsPath)) File.Copy(SettingsPath, SettingsPath + ".clawd-backup", true);
                StringBuilder sb = new StringBuilder();
                Write(sb, s, 0);
                sb.Append('\n');
                File.WriteAllText(SettingsPath, sb.ToString(), new UTF8Encoding(false));
            }
            catch (Exception ex) { return "Couldn't write " + SettingsPath + ": " + ex.Message; }
            return null;
        }

        // A missing file is an empty one; a file that isn't a JSON object is an error.
        static Dictionary<string, object> Load()
        {
            if (!File.Exists(SettingsPath)) return new Dictionary<string, object>();
            string text = File.ReadAllText(SettingsPath);
            if (text.Trim().Length == 0) return new Dictionary<string, object>();
            JavaScriptSerializer js = new JavaScriptSerializer();
            js.MaxJsonLength = int.MaxValue;
            Dictionary<string, object> s = js.DeserializeObject(text) as Dictionary<string, object>;
            if (s == null) throw new FormatException("not a JSON object");
            return s;
        }

        static IEnumerable<Dictionary<string, object>> Handlers(object value)
        {
            object[] groups = value as object[];
            if (groups == null) yield break;
            foreach (object g in groups)
            {
                object[] hs = Get(g as Dictionary<string, object>, "hooks") as object[];
                if (hs == null) continue;
                foreach (object h in hs)
                    if (h is Dictionary<string, object>) yield return (Dictionary<string, object>)h;
            }
        }

        // Ours: any Clawd binary run with --hook, or the hand-written hooks from before there
        // was a menu item for this.
        static bool IsOurs(Dictionary<string, object> h)
        {
            string cmd = Get(h, "command") as string ?? "";
            if (cmd.Contains("Clawd/claude-needs-you") || cmd.Contains("Clawd\\claude-needs-you")) return true;
            object[] args = Get(h, "args") as object[];
            if (args == null || Array.IndexOf(args, "--hook") < 0) return false;
            string name = cmd.Replace('\\', '/');
            name = name.Substring(name.LastIndexOf('/') + 1);
            return name == "Clawd" || name.Equals("Clawd.exe", StringComparison.OrdinalIgnoreCase);
        }

        static object Get(Dictionary<string, object> d, string key)
        {
            object v;
            return d != null && d.TryGetValue(key, out v) ? v : null;
        }

        // ---- a small pretty-printer: JavaScriptSerializer only writes one long line ----

        static void Write(StringBuilder sb, object v, int depth)
        {
            string pad = new string(' ', (depth + 1) * 2), end = new string(' ', depth * 2);
            if (v == null) sb.Append("null");
            else if (v is string) Quote(sb, (string)v);
            else if (v is bool) sb.Append((bool)v ? "true" : "false");
            else if (v is IDictionary<string, object>)
            {
                IDictionary<string, object> d = (IDictionary<string, object>)v;
                if (d.Count == 0) { sb.Append("{}"); return; }
                sb.Append("{\n");
                int i = 0;
                foreach (KeyValuePair<string, object> kv in d)
                {
                    sb.Append(pad);
                    Quote(sb, kv.Key);
                    sb.Append(": ");
                    Write(sb, kv.Value, depth + 1);
                    sb.Append(++i < d.Count ? ",\n" : "\n");
                }
                sb.Append(end).Append('}');
            }
            else if (v is IList)
            {
                IList l = (IList)v;
                if (l.Count == 0) { sb.Append("[]"); return; }
                sb.Append("[\n");
                for (int i = 0; i < l.Count; i++)
                {
                    sb.Append(pad);
                    Write(sb, l[i], depth + 1);
                    sb.Append(i + 1 < l.Count ? ",\n" : "\n");
                }
                sb.Append(end).Append(']');
            }
            else sb.Append(Convert.ToString(v, CultureInfo.InvariantCulture));
        }

        static void Quote(StringBuilder sb, string s)
        {
            sb.Append('"');
            foreach (char c in s)
            {
                switch (c)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    default:
                        if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4"));
                        else sb.Append(c);
                        break;
                }
            }
            sb.Append('"');
        }
    }
}
