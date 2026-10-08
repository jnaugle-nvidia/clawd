using System;
using System.IO;

namespace Clawd
{
    // "Claude needs you": watches one small file that Claude Code's hooks write to whenever
    // Claude finishes a turn (Stop hook) or is waiting on you (Notification hook).
    //
    //   %APPDATA%\Clawd\claude-needs-you
    //
    // Its contents are a single word, "done" or "input". Only the modification time matters
    // for triggering; the word picks what he says.
    public class ClaudeWatch
    {
        public static string FilePath { get { return Path.Combine(Settings.Dir, "claude-needs-you"); } }

        DateTime lastStamp;
        double pollT;

        public ClaudeWatch()
        {
            lastStamp = Stamp();   // anything written before launch is old news
        }

        // Returns the word from the file when it has been written since the last check.
        public string Poll(double dt)
        {
            pollT -= dt;
            if (pollT > 0) return null;
            pollT = 0.5;

            DateTime stamp = Stamp();
            if (stamp <= lastStamp) return null;
            lastStamp = stamp;

            try { return File.ReadAllText(FilePath).Trim().ToLowerInvariant(); }
            catch { return ""; }
        }

        static DateTime Stamp()
        {
            try { return File.Exists(FilePath) ? File.GetLastWriteTimeUtc(FilePath) : DateTime.MinValue; }
            catch { return DateTime.MinValue; }
        }
    }
}
