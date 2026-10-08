import Foundation
import EVECore

/// The macOS app keeps these in UserDefaults behind a settings window. A
/// desktop-launched CLI has no window, so they live in a small config file
/// whose values are either an absolute path or a program name found on PATH.
public struct Configuration: Equatable, Sendable {
    public var terminal: String
    public var telnet: String
    public var vnc: String
    public var wireshark: String
    public var sshUser: String
    public var identityFile: String

    public init(terminal: String = "ghostty", telnet: String = "telnet", vnc: String = "vncviewer",
                wireshark: String = "wireshark", sshUser: String = "root", identityFile: String = "") {
        self.terminal = terminal
        self.telnet = telnet
        self.vnc = vnc
        self.wireshark = wireshark
        self.sshUser = sshUser
        self.identityFile = identityFile
    }

    public static let fileName = "config.toml"

    public static func defaultPath(home: String = NSHomeDirectory(),
                                   environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let base = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.config"
        return base + "/eve-connect/" + fileName
    }

    public func render() -> String {
        """
        # EVE Connect — configuration for the eve-connect command.
        #
        # Each program is either an absolute path or a name found on PATH.
        #
        #   terminal   terminal emulator used for telnet:// console links
        #   telnet     the telnet client the console runs
        #   vnc        viewer for vnc:// links; it is given host::port
        #   wireshark  viewer wired to the SSH packet-capture pipe
        #
        # ssh_user and identity_file apply to capture:// links only. Leave
        # identity_file empty to use ~/.ssh/config and the ssh agent; no
        # password is ever stored.

        terminal      = "\(escaped(terminal))"
        telnet        = "\(escaped(telnet))"
        vnc           = "\(escaped(vnc))"
        wireshark     = "\(escaped(wireshark))"
        ssh_user      = "\(escaped(sshUser))"
        identity_file = "\(escaped(identityFile))"
        """
    }

    /// Values are quoted, so a path that contains a quote or a backslash has to
    /// be escaped for the file to parse back to the same string.
    private func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// A TOML subset: comments, `key = value`, and quoted or bare values.
    /// Unknown keys warn rather than fail, so a newer config still loads.
    public static func parse(_ text: String) throws -> (configuration: Configuration, warnings: [String]) {
        var configuration = Configuration()
        var warnings: [String] = []
        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let separator = line.firstIndex(of: "=") else {
                throw ConnectError("\(fileName) line \(index + 1): expected key = value.")
            }
            let key = line[line.startIndex..<separator].trimmingCharacters(in: .whitespaces)
            let raw = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            let value = try value(of: raw, line: index + 1)
            switch key {
            case "terminal": configuration.terminal = value
            case "telnet": configuration.telnet = value
            case "vnc": configuration.vnc = value
            case "wireshark": configuration.wireshark = value
            case "ssh_user": configuration.sshUser = value
            case "identity_file": configuration.identityFile = value
            default: warnings.append("\(fileName) line \(index + 1): ignoring unknown key '\(key)'.")
            }
        }
        return (configuration, warnings)
    }

    public static func load(path: String) throws -> (configuration: Configuration, warnings: [String], exists: Bool) {
        guard FileManager.default.fileExists(atPath: path) else {
            return (Configuration(), [], false)
        }
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let parsed = try parse(text)
        return (parsed.configuration, parsed.warnings, true)
    }

    public func write(to path: String) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                               withIntermediateDirectories: true)
        try (render() + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static func value(of raw: String, line: Int) throws -> String {
        guard let quote = raw.first, quote == "\"" || quote == "'" else {
            guard let hash = raw.firstIndex(of: "#") else { return raw }
            return String(raw[raw.startIndex..<hash]).trimmingCharacters(in: .whitespaces)
        }
        var result = ""
        var index = raw.index(after: raw.startIndex)
        var closed = false
        while index < raw.endIndex {
            let character = raw[index]
            if character == "\\", quote == "\"", raw.index(after: index) < raw.endIndex {
                let escaped = raw[raw.index(after: index)]
                result.append(escaped == "n" ? "\n" : escaped)
                index = raw.index(after: raw.index(after: index))
                continue
            }
            if character == quote { closed = true; index = raw.index(after: index); break }
            result.append(character)
            index = raw.index(after: index)
        }
        guard closed else { throw ConnectError("\(fileName) line \(line): unterminated value.") }
        let rest = raw[index...].trimmingCharacters(in: .whitespaces)
        guard rest.isEmpty || rest.hasPrefix("#") else {
            throw ConnectError("\(fileName) line \(line): unexpected text after the closing quote.")
        }
        return result
    }
}
