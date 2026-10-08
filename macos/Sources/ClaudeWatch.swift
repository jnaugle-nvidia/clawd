import Foundation

// "Claude needs you": watches one small file that Claude Code's hooks write to whenever
// Claude finishes a turn (Stop hook) or is waiting on you (Notification hook). Reading
// another app's notifications would need a permission; a file we own needs none.
//
//   ~/Library/Application Support/Clawd/claude-needs-you
//
// Its contents are a single word, "done" or "input". Only the modification time matters
// for triggering; the word picks what he says.
public final class ClaudeWatch
{
    public static var FilePath: URL { return Settings.Dir.appendingPathComponent("claude-needs-you") }

    private var lastStamp: Date?
    private var pollT = 0.0

    public init()
    {
        lastStamp = ClaudeWatch.Stamp()   // anything written before launch is old news
    }

    // Returns the word from the file when it has been written since the last check.
    public func Poll(_ dt: Double) -> String?
    {
        pollT -= dt
        if pollT > 0 { return nil }
        pollT = 0.5

        guard let stamp = ClaudeWatch.Stamp() else { return nil }
        if let last = lastStamp, stamp <= last { return nil }
        lastStamp = stamp

        let text = (try? String(contentsOf: ClaudeWatch.FilePath, encoding: .utf8)) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func Stamp() -> Date?
    {
        let a = try? FileManager.default.attributesOfItem(atPath: FilePath.path)
        return a?[.modificationDate] as? Date
    }
}
