import Foundation
import EVECore

/// The macOS app registers itself with LaunchServices from its Info.plist and
/// offers a "Make default for EVE links" button. On Linux the equivalent is a
/// desktop entry whose MimeType claims the `x-scheme-handler/<scheme>` types,
/// plus the `xdg-mime default` record that names it.
public struct SchemeInstaller: Sendable {
    public static let schemes = ["telnet", "vnc", "capture"]
    public static let desktopFileName = "eve-connect.desktop"

    public let executablePath: String
    public let applicationsDirectory: String

    public init(executablePath: String,
                applicationsDirectory: String = SchemeInstaller.defaultApplicationsDirectory()) {
        self.executablePath = executablePath
        self.applicationsDirectory = applicationsDirectory
    }

    public static func defaultApplicationsDirectory(
        home: String = NSHomeDirectory(),
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let base = environment["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.local/share"
        return base + "/applications"
    }

    public var entryPath: String { applicationsDirectory + "/" + Self.desktopFileName }

    public var entryContents: String {
        """
        [Desktop Entry]
        Type=Application
        Name=EVE Connect
        Comment=Open EVE-NG console, VNC and packet-capture links
        Exec=\(execField) %u
        Terminal=false
        NoDisplay=true
        StartupNotify=false
        Icon=utilities-terminal
        Categories=Network;
        MimeType=\(Self.schemes.map { "x-scheme-handler/\($0)" }.joined(separator: ";"));
        """
    }

    /// The commands registration runs, in order. Kept as data so the exact
    /// command line can be asserted without touching the real desktop.
    public var commands: [(tool: String, arguments: [String])] {
        [("update-desktop-database", [applicationsDirectory])]
            + Self.schemes.map { ("xdg-mime", ["default", Self.desktopFileName, "x-scheme-handler/\($0)"]) }
    }

    public func install() throws {
        try FileManager.default.createDirectory(atPath: applicationsDirectory, withIntermediateDirectories: true)
        try (entryContents + "\n").write(toFile: entryPath, atomically: true, encoding: .utf8)
        for command in commands {
            guard let tool = ToolLookup.resolve(command.tool) else {
                throw ConnectError("\(command.tool) was not found. Install xdg-utils and desktop-file-utils, then run --install again.")
            }
            let result = try Command.run(tool, command.arguments)
            guard result.status == 0 else {
                throw ConnectError("\(tool) \(command.arguments.joined(separator: " ")) exited \(result.status).\n\(result.output)")
            }
        }
    }

    /// Which desktop entry currently handles a scheme, or nil when none does.
    /// `xdg-mime` prints an empty line rather than failing when nothing is set.
    public static func handler(for scheme: String) -> String? {
        guard let xdgMime = ToolLookup.resolve("xdg-mime") else { return nil }
        guard let result = try? Command.run(xdgMime, ["query", "default", "x-scheme-handler/\(scheme)"]),
              result.status == 0, !result.output.isEmpty else { return nil }
        return result.output
    }

    /// The desktop entry spec requires quoting certain characters in Exec.
    private var execField: String {
        let reserved = Set(" \t\"'\\><~|&;$*?#()`")
        guard executablePath.contains(where: { reserved.contains($0) }) else { return executablePath }
        var escaped = ""
        for character in executablePath {
            if character == "\\" || character == "\"" || character == "`" || character == "$" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return "\"\(escaped)\""
    }
}
