import Foundation

// Adds Clawd's hooks to ~/.claude/settings.json, or takes them out again. Everything else
// in that file is left alone, and a copy is kept next to it before every change.
public enum ClaudeHooks
{
    public enum Status { case notConnected, connected, outdated }

    // The events Clawd acts on. Each runs this binary with --hook.
    static let Events =
    [
        "UserPromptSubmit", "PreToolUse", "PostToolUseFailure", "PreCompact",
        "Stop", "Notification", "SessionEnd"
    ]

    // Claude Code reads CLAUDE_CONFIG_DIR in place of ~/.claude when it is set.
    static var SettingsURL: URL
    {
        if let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty
        {
            return URL(fileURLWithPath: dir).appendingPathComponent("settings.json")
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json")
    }

    static var ExePath: String
    {
        return Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]
    }

    public static func CurrentStatus() -> Status
    {
        guard let s = try? Load(), let hooks = s["hooks"] as? [String: Any] else { return .notConnected }
        var found = 0, current = 0
        for ev in Events
        {
            for h in Handlers(hooks[ev]) where IsOurs(h)
            {
                found += 1
                if h["command"] as? String == ExePath { current += 1; break }
            }
        }
        if found == 0 { return .notConnected }
        return current == Events.count ? .connected : .outdated
    }

    // Returns nil on success, or what went wrong.
    public static func Connect() -> String? { return Rewrite(add: true) }
    public static func Disconnect() -> String? { return Rewrite(add: false) }

    private static func Rewrite(add: Bool) -> String?
    {
        var s: [String: Any]
        do { s = try Load() }
        catch { return "Couldn't read \(SettingsURL.path): it isn't valid JSON, so Clawd left it alone." }

        var hooks = s["hooks"] as? [String: Any] ?? [:]

        // Out with every old Clawd hook first, whichever copy of Clawd wrote it.
        for (ev, value) in hooks
        {
            guard let groups = value as? [[String: Any]] else { continue }
            var kept: [[String: Any]] = []
            for var g in groups
            {
                let hs = (g["hooks"] as? [[String: Any]] ?? []).filter { !IsOurs($0) }
                if hs.isEmpty { continue }
                g["hooks"] = hs
                kept.append(g)
            }
            hooks[ev] = kept.isEmpty ? nil : kept
        }

        if add
        {
            let mine: [String: Any] = ["type": "command", "command": ExePath, "args": ["--hook"], "timeout": 5]
            for ev in Events
            {
                var groups = hooks[ev] as? [[String: Any]] ?? []
                groups.append(["hooks": [mine]])
                hooks[ev] = groups
            }
        }

        s["hooks"] = hooks.isEmpty ? nil : hooks

        do
        {
            let dir = SettingsURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: SettingsURL.path)
            {
                let backup = dir.appendingPathComponent("settings.json.clawd-backup")
                try? FileManager.default.removeItem(at: backup)
                try FileManager.default.copyItem(at: SettingsURL, to: backup)
            }
            let out = try JSONSerialization.data(
                withJSONObject: s, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try out.write(to: SettingsURL, options: .atomic)
        }
        catch { return "Couldn't write \(SettingsURL.path): \(error.localizedDescription)" }
        return nil
    }

    // A missing file is an empty one; a file that isn't a JSON object is an error.
    private static func Load() throws -> [String: Any]
    {
        guard let data = try? Data(contentsOf: SettingsURL), !data.isEmpty else { return [:] }
        guard let s = try JSONSerialization.jsonObject(with: data) as? [String: Any] else
        {
            throw NSError(domain: "Clawd", code: 1)
        }
        return s
    }

    private static func Handlers(_ value: Any?) -> [[String: Any]]
    {
        let groups = value as? [[String: Any]] ?? []
        return groups.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
    }

    // Ours: any Clawd binary run with --hook, or the hand-written hooks from before there
    // was a menu item for this.
    private static func IsOurs(_ h: [String: Any]) -> Bool
    {
        let cmd = h["command"] as? String ?? ""
        if cmd.contains("Clawd/claude-needs-you") { return true }
        let args = h["args"] as? [String] ?? []
        let name = (cmd as NSString).lastPathComponent
        return args.contains("--hook") && (name == "Clawd" || name == "Clawd.exe")
    }
}
