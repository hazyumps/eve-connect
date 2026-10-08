import Foundation

public enum LaunchPlan {
    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func consoleCommand(connection: Connection, telnet: String) throws -> String {
        guard connection.kind == .telnet, let port = connection.port else { throw ConnectError("A telnet connection is required.") }
        // Ghostty 1.3's AppleScript API has no per-surface confirm-close option.
        // OSC 133 marks this disposable console as prompt/input, suppressing
        // the default busy-process warning for this surface only. This is a
        // shell-integration workaround, not a change to Ghostty's global config.
        // Use an explicit shell: Ghostty's macOS launcher prepends `exec -l`,
        // which would exit at the first printf in a bare compound command.
        let wrapper = #"printf '\033]133;A\007\033]133;B\007'; exec "$@""#
        return ["/bin/sh", "-c", wrapper, "eve-console", telnet, connection.host, String(port)]
            .map(shellQuote).joined(separator: " ")
    }

    public static func ghosttyScript(connection: Connection, telnet: String, preferTab: Bool) throws -> String {
        // Ghostty's command property uses shell parsing. Quote each argument,
        // then separately encode the resulting command as an AppleScript string.
        let command = try consoleCommand(connection: connection, telnet: telnet)
        let literal = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application id "com.mitchellh.ghostty"
            set config to new surface configuration
            set command of config to "\(literal)"
            set wait after command of config to true
            if \(preferTab ? "true" : "false") and (count of windows) > 0 then
                new tab in front window with configuration config
            else
                new window with configuration config
            end if
            activate
        end tell
        """
    }

    public static func captureArguments(connection: Connection, user: String, identityFile: String) throws -> [String] {
        guard connection.kind == .capture, let interface = connection.interface else { throw ConnectError("A capture connection is required.") }
        guard user.range(of: #"^[a-zA-Z_][a-zA-Z0-9_-]*$"#, options: .regularExpression) != nil,
              !user.contains("\n") else { throw ConnectError("Invalid SSH user.") }
        var arguments = ["-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=2"]
        if !identityFile.isEmpty { arguments += ["-i", (identityFile as NSString).expandingTildeInPath] }
        // SSH always passes the remote command to a shell, even with local argv.
        arguments += ["\(user)@\(connection.host)", "exec tcpdump -U -n -i \(shellQuote(interface)) -w -"]
        return arguments
    }
}
