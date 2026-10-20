import Foundation

// What Claude Code is doing, as told by its hooks. Claude Code runs Clawd's own binary
// with --hook on every event; that copy writes one line here and exits at once:
//
//   ~/Library/Application Support/Clawd/claude-activity
//
// The line is tab-separated: event, tool, detail, session. The running Clawd polls the
// file's modification time. Reading another app's notifications would need a
// permission; a file we own needs none.
public struct ClaudeEvent
{
    public var Event = "", Tool = "", Detail = "", Session = ""
}

public final class ClaudeWatch
{
    public static var FilePath: URL { return Settings.Dir.appendingPathComponent("claude-activity") }

    private var lastStamp: Date?
    private var pollT = 0.0

    public init()
    {
        lastStamp = ClaudeWatch.Stamp()   // anything written before launch is old news
    }

    // Returns the newest event when the file has been written since the last check.
    public func Poll(_ dt: Double) -> ClaudeEvent?
    {
        pollT -= dt
        if pollT > 0 { return nil }
        pollT = 0.2

        guard let stamp = ClaudeWatch.Stamp() else { return nil }
        if let last = lastStamp, stamp <= last { return nil }
        lastStamp = stamp

        guard let text = try? String(contentsOf: ClaudeWatch.FilePath, encoding: .utf8) else { return nil }
        let f = text.trimmingCharacters(in: .newlines).components(separatedBy: "\t")
        var e = ClaudeEvent()
        if f.count > 0 { e.Event = f[0] }
        if f.count > 1 { e.Tool = f[1] }
        if f.count > 2 { e.Detail = f[2] }
        if f.count > 3 { e.Session = f[3] }
        return e.Event.isEmpty ? nil : e
    }

    private static func Stamp() -> Date?
    {
        let a = try? FileManager.default.attributesOfItem(atPath: FilePath.path)
        return a?[.modificationDate] as? Date
    }

    // ---- the hook side: runs in a short-lived copy of Clawd, never the pet itself ----

    public static func RunHook()
    {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let e = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        let event = e["hook_event_name"] as? String ?? ""
        if event.isEmpty { return }
        let tool = e["tool_name"] as? String ?? ""
        let detail = DetailOf(e["tool_input"] as? [String: Any] ?? [:])
        let session = e["session_id"] as? String ?? ""

        let line = [event, tool, detail, session]
            .map { $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
            .joined(separator: "\t")
        try? FileManager.default.createDirectory(at: Settings.Dir, withIntermediateDirectories: true)
        try? line.write(to: FilePath, atomically: true, encoding: .utf8)
    }

    // The one thing worth saying about a tool call: a file name, a search, a host, a command.
    private static func DetailOf(_ i: [String: Any]) -> String
    {
        if let f = (i["file_path"] ?? i["notebook_path"] ?? i["path"]) as? String
        {
            return (f as NSString).lastPathComponent
        }
        if let s = i["pattern"] as? String { return s }
        if let s = i["query"] as? String { return s }
        if let s = i["url"] as? String { return URL(string: s)?.host ?? s }
        if let s = i["command"] as? String { return s }
        if let s = i["description"] as? String { return s }
        return ""
    }
}
