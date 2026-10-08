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

    /// Linux has no Ghostty scripting interface. `ghostty +new-window` forwards
    /// only --working-directory, --command and --title to the running instance,
    /// so `wait-after-command` is not available on that path. This wrapper holds
    /// a failed console open long enough to read the reason; a clean exit closes
    /// the window immediately, which is nicer than the macOS behaviour.
    public static let linuxConsoleWrapper = """
    "$@"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf '\\n[eve-connect] console command exited %s.\\n' "$status"
        printf 'Press Enter to close this window. '
        read -r _
    fi
    exit "$status"
    """

    /// Everything after `-e` is argv, not a shell string, so no quoting is
    /// needed. A bare `ghostty -e` would start a second Ghostty rather than hand
    /// off to the running one: any command-line argument forces
    /// gtk-single-instance off (its default is `detect`).
    public static func linuxConsoleArguments(connection: Connection, terminal: String, telnet: String,
                                            shell: String = "/bin/sh") throws -> [String] {
        guard connection.kind == .telnet, let port = connection.port else { throw ConnectError("A telnet connection is required.") }
        return [terminal, "+new-window", "-e", shell, "-c", linuxConsoleWrapper,
                "eve-console", telnet, connection.host, String(port)]
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
