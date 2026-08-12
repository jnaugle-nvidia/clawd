import Foundation

// Tiny key=value store under ~/Library/Application Support/ClaudePet/settings.ini.
// Same file format as the Windows build, so the two stay readable to each other.
public final class Settings
{
    public var FollowCursor = false
    public var Perch = true
    public var Chatty = true
    public var ClickThrough = false
    public var Paused = false
    public var Dance = true
    public var Glitch = false
    public var Scale = 1.0

    public init() { }

    public static var Dir: URL
    {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("ClaudePet", isDirectory: true)
    }

    private static var FilePath: URL { return Dir.appendingPathComponent("settings.ini") }

    public static func Load() -> Settings
    {
        let s = Settings()
        guard let text = try? String(contentsOf: FilePath, encoding: .utf8) else { return s }

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false)
        {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eq = line.firstIndex(of: "="), line.first != "#" else { continue }

            let k = line[line.startIndex ..< eq].trimmingCharacters(in: .whitespaces).lowercased()
            let v = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if k.isEmpty { continue }

            switch k
            {
            case "followcursor": s.FollowCursor = (v == "1")
            case "perch":        s.Perch = (v == "1")
            case "chatty":       s.Chatty = (v == "1")
            case "clickthrough": s.ClickThrough = (v == "1")
            case "dance":        s.Dance = (v == "1")
            case "glitch":       s.Glitch = (v == "1")
            case "scale":
                if let d = Double(v), d > 0.3 && d < 4.0 { s.Scale = d }
            default: break
            }
        }
        return s
    }

    public func Save()
    {
        let lines =
        [
            "# Claude Pet settings",
            "followcursor=" + (FollowCursor ? "1" : "0"),
            "perch=" + (Perch ? "1" : "0"),
            "chatty=" + (Chatty ? "1" : "0"),
            "clickthrough=" + (ClickThrough ? "1" : "0"),
            "dance=" + (Dance ? "1" : "0"),
            "glitch=" + (Glitch ? "1" : "0"),
            "scale=" + String(format: "%g", Scale)
        ]
        try? FileManager.default.createDirectory(at: Settings.Dir, withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: Settings.FilePath, atomically: true, encoding: .utf8)
    }
}

public enum Log
{
    private static var written = false

    public static func Once(_ message: String)
    {
        if written { return }
        written = true
        try? FileManager.default.createDirectory(at: Settings.Dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
        try? (stamp + "\n" + message).write(
            to: Settings.Dir.appendingPathComponent("error.log"), atomically: true, encoding: .utf8)
    }
}
