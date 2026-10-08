using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;

namespace Clawd
{
    // Tiny key=value store under %APPDATA%\Clawd\settings.ini
    public class Settings
    {
        public bool FollowCursor;
        public bool Perch;
        public bool Chatty;
        public bool ClickThrough;
        public bool Paused;
        public bool Dance;
        public bool Glitch;
        public bool ClaudeAlert;
        public double Scale;

        public Settings()
        {
            FollowCursor = false;
            Perch = true;
            Chatty = true;
            ClickThrough = false;
            Paused = false;
            Dance = true;
            Glitch = false;
            ClaudeAlert = true;
            Scale = 1.0;
        }

        public static string Dir
        {
            get
            {
                return Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Clawd");
            }
        }

        static string FilePath { get { return Path.Combine(Dir, "settings.ini"); } }

        public static Settings Load()
        {
            Settings s = new Settings();
            try
            {
                if (!File.Exists(FilePath)) return s;
                foreach (string raw in File.ReadAllLines(FilePath))
                {
                    string line = raw.Trim();
                    int eq = line.IndexOf('=');
                    if (line.Length == 0 || line[0] == '#' || eq <= 0) continue;
                    string k = line.Substring(0, eq).Trim().ToLowerInvariant();
                    string v = line.Substring(eq + 1).Trim();
                    switch (k)
                    {
                        case "followcursor": s.FollowCursor = (v == "1"); break;
                        case "perch": s.Perch = (v == "1"); break;
                        case "chatty": s.Chatty = (v == "1"); break;
                        case "clickthrough": s.ClickThrough = (v == "1"); break;
                        case "dance": s.Dance = (v == "1"); break;
                        case "glitch": s.Glitch = (v == "1"); break;
                        case "claudealert": s.ClaudeAlert = (v == "1"); break;
                        case "scale":
                            double d;
                            if (double.TryParse(v, NumberStyles.Float, CultureInfo.InvariantCulture, out d)
                                && d > 0.3 && d < 4.0)
                                s.Scale = d;
                            break;
                    }
                }
            }
            catch { }
            return s;
        }

        public void Save()
        {
            try
            {
                Directory.CreateDirectory(Dir);
                List<string> l = new List<string>();
                l.Add("# Clawd settings");
                l.Add("followcursor=" + (FollowCursor ? "1" : "0"));
                l.Add("perch=" + (Perch ? "1" : "0"));
                l.Add("chatty=" + (Chatty ? "1" : "0"));
                l.Add("clickthrough=" + (ClickThrough ? "1" : "0"));
                l.Add("dance=" + (Dance ? "1" : "0"));
                l.Add("glitch=" + (Glitch ? "1" : "0"));
                l.Add("claudealert=" + (ClaudeAlert ? "1" : "0"));
                l.Add("scale=" + Scale.ToString("0.##", CultureInfo.InvariantCulture));
                File.WriteAllLines(FilePath, l.ToArray());
            }
            catch { }
        }
    }
}
