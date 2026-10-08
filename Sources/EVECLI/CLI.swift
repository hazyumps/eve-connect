import Foundation
import EVECore

/// The `eve-connect` command. The macOS app puts the same operations behind a
/// settings window; here they are arguments, and the desktop entry runs the
/// bare `<link>` form.
public enum CLI {
    public static let version = "0.3.0"

    public enum Command: Equatable, Sendable {
        case open, dryRun, captureSession, check, install, initialize
    }

    public struct Parsed: Equatable, Sendable {
        public var command: Command = .open
        public var link: String?
        public var configPath: String?
        public var help = false
        public var showVersion = false
    }

    @MainActor
    public static func run(arguments: [String]) async -> Int32 {
        let program = arguments.first ?? "eve-connect"
        let parsed: Parsed
        do {
            parsed = try parse(arguments: arguments)
        } catch {
            fail(error.localizedDescription)
            print(usage(program: program))
            return 2
        }
        if parsed.help { print(usage(program: program)); return 0 }
        if parsed.showVersion { print("eve-connect \(version)"); return 0 }

        let configPath = parsed.configPath
            ?? ProcessInfo.processInfo.environment["EVE_CONNECT_CONFIG"]
            ?? Configuration.defaultPath()
        let configuration: Configuration
        do {
            let loaded = try Configuration.load(path: configPath)
            for warning in loaded.warnings { fail(warning) }
            configuration = loaded.configuration
        } catch {
            fail(error.localizedDescription)
            return 1
        }

        switch parsed.command {
        case .check:
            let result = check(configuration: configuration, configPath: configPath)
            print(result.text)
            guard result.missing.isEmpty else {
                fail("Not found: \(result.missing.joined(separator: ", ")). Install them, or edit \(configPath).")
                return 1
            }
            return 0

        case .initialize:
            do {
                if FileManager.default.fileExists(atPath: configPath) {
                    print("\(configPath) already exists; left as it is.")
                } else {
                    try configuration.write(to: configPath)
                    print("Wrote \(configPath).")
                }
                return 0
            } catch {
                fail(error.localizedDescription)
                return 1
            }

        case .install:
            guard let executable = absoluteExecutable(arguments.first) else {
                fail("Run eve-connect from an absolute path, or put it on PATH, before installing.")
                return 1
            }
            do {
                let installer = SchemeInstaller(executablePath: executable)
                try installer.install()
                print("Installed \(installer.entryPath)")
                for scheme in SchemeInstaller.schemes {
                    print("  x-scheme-handler/\(scheme) -> \(SchemeInstaller.handler(for: scheme) ?? "not set")")
                }
                return 0
            } catch {
                fail(error.localizedDescription)
                return 1
            }

        case .dryRun:
            guard let link = parsed.link else { return usageError("A link is required.", program: program) }
            do {
                print(try plan(link, configuration: configuration))
                return 0
            } catch {
                fail(error.localizedDescription)
                return 1
            }

        case .open:
            guard let link = parsed.link else { return usageError("A link is required.", program: program) }
            let headless = headless(configuration: configuration, configPath: configPath, program: arguments.first)
            do {
                try headless.open(link)
                return 0
            } catch {
                fail(error.localizedDescription)
                Headless(configuration: configuration, configPath: configPath, executablePath: headless.executablePath).notifier
                    .error(error.localizedDescription)
                return 1
            }

        case .captureSession:
            guard let link = parsed.link else { return usageError("A capture link is required.", program: program) }
            do {
                try await headless(configuration: configuration, configPath: configPath, program: arguments.first)
                    .runCaptureSession(link)
                return 0
            } catch {
                headless(configuration: configuration, configPath: configPath, program: arguments.first)
                    .notifier.error(error.localizedDescription)
                fail(error.localizedDescription)
                return 1
            }
        }
    }

    public static func parse(arguments: [String]) throws -> Parsed {
        var parsed = Parsed()
        var rest = Array(arguments.dropFirst())
        while !rest.isEmpty {
            let argument = rest.removeFirst()
            switch argument {
            case "--help", "-h": parsed.help = true
            case "--version": parsed.showVersion = true
            case "--check": parsed.command = .check
            case "--install": parsed.command = .install
            case "--init": parsed.command = .initialize
            case "--dry-run": parsed.command = .dryRun
            case "--capture-session": parsed.command = .captureSession
            case "--config":
                guard let value = rest.first else { throw ConnectError("--config needs a path.") }
                parsed.configPath = value
                rest.removeFirst()
            default:
                guard !argument.hasPrefix("-") else { throw ConnectError("Unknown option '\(argument)'.") }
                guard parsed.link == nil else { throw ConnectError("Unexpected extra argument '\(argument)'.") }
                parsed.link = argument
            }
        }
        return parsed
    }

    /// What a link would launch, without launching it. Same purpose as the
    /// macOS app's `--dry-run`, which exercises the parser and launch plans
    /// without touching a viewer or the network.
    public static func plan(_ raw: String, configuration: Configuration) throws -> String {
        let connection = try Connection(raw)
        switch connection.kind {
        case .telnet:
            let terminal = ToolLookup.resolve(configuration.terminal) ?? configuration.terminal
            let telnet = ToolLookup.resolve(configuration.telnet) ?? configuration.telnet
            let arguments = try LaunchPlan.linuxConsoleArguments(connection: connection, terminal: terminal, telnet: telnet)
            return "console \(connection.displayName) in a new \(terminal) window\n"
                + arguments.map(LaunchPlan.shellQuote).joined(separator: " ")
        case .vnc:
            let viewer = ToolLookup.resolve(configuration.vnc) ?? configuration.vnc
            let arguments = [viewer, connection.vncTarget]
            return "vnc \(connection.displayName) in \(viewer)\n"
                + arguments.map(LaunchPlan.shellQuote).joined(separator: " ")
        case .capture:
            let wireshark = ToolLookup.resolve(configuration.wireshark) ?? configuration.wireshark
            let ssh = try LaunchPlan.captureArguments(connection: connection, user: configuration.sshUser,
                                                      identityFile: configuration.identityFile)
            let viewer = [wireshark, "-k", "-i", "-", "--no-promiscuous-mode"]
            return "capture \(connection.displayName)\n"
                + (["ssh"] + ssh).map(LaunchPlan.shellQuote).joined(separator: " ")
                + " | " + viewer.map(LaunchPlan.shellQuote).joined(separator: " ")
        }
    }

    /// The dependency checks and handler list the macOS settings window showed.
    public static func check(configuration: Configuration, configPath: String) -> (text: String, missing: [String]) {
        let exists = FileManager.default.fileExists(atPath: configPath)
        var lines = ["eve-connect \(version)",
                     row("config", exists ? configPath : "\(configPath) (not there yet — defaults in use)")]
        var missing: [String] = []
        let programs = [("terminal", configuration.terminal), ("telnet", configuration.telnet),
                        ("vnc", configuration.vnc), ("wireshark", configuration.wireshark)]
        for (key, value) in programs {
            if let resolved = ToolLookup.resolve(value) {
                lines.append(row(key, "\(resolved)  (\(value))"))
            } else {
                lines.append(row(key, "NOT FOUND  (\(value))"))
                missing.append(key)
            }
        }
        lines.append(row("ssh user", configuration.sshUser))
        lines.append(row("identity", configuration.identityFile.isEmpty
                         ? "(none — ~/.ssh/config and the agent are used)"
                         : configuration.identityFile))
        for scheme in SchemeInstaller.schemes {
            let handler = SchemeInstaller.handler(for: scheme) ?? "none registered"
            lines.append(row("handler \(scheme)", "x-scheme-handler/\(scheme) -> \(handler)"))
        }
        return (lines.joined(separator: "\n"), missing)
    }

    public static func usage(program: String) -> String {
        let name = (program as NSString).lastPathComponent
        return """
        \(name) — open EVE-NG links on this machine

        Usage:
          \(name) <link>              open a console, VNC, or capture link
          \(name) --check             resolved programs and current link handlers
          \(name) --install           register \(SchemeInstaller.desktopFileName) for EVE links
          \(name) --init              write a default config file
          \(name) --dry-run <link>    print the launch plan without starting anything

        Options:
          --config <path>             use another config file
          -h, --help                  this text
          --version                   version

        Links:
          telnet://host:port          console in a new terminal window
          vnc://host::port            viewer; host::port is an absolute TCP port
          capture://host/interface    SSH tcpdump piped into Wireshark
        """
    }

    @MainActor
    private static func headless(configuration: Configuration, configPath: String, program: String?) -> Headless {
        Headless(configuration: configuration, configPath: configPath,
                 executablePath: absoluteExecutable(program) ?? program ?? "eve-connect")
    }

    /// The desktop entry needs a path, and `--capture-session` re-runs this
    /// program, so a name alone is not good enough.
    static func absoluteExecutable(_ argument: String?) -> String? {
        guard let argument, !argument.isEmpty else { return nil }
        let expanded = (argument as NSString).expandingTildeInPath
        guard expanded.contains("/") else { return ToolLookup.resolve(expanded) }
        let path = URL(fileURLWithPath: expanded).standardizedFileURL.path
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    private static func row(_ label: String, _ value: String) -> String {
        let padded = label.count >= 15 ? label : label + String(repeating: " ", count: 15 - label.count)
        return "  \(padded) \(value)"
    }

    private static func usageError(_ message: String, program: String) -> Int32 {
        fail(message)
        print(usage(program: program))
        return 2
    }

    private static func fail(_ message: String) {
        FileHandle.standardError.write(Data(("eve-connect: " + message + "\n").utf8))
    }
}
