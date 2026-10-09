import Foundation
import EVECore

/// Turns a configured program name or path into an absolute executable path,
/// the way the macOS app resolved the paths typed into its settings window.
public enum ToolLookup {
    public static let fallbackDirectories = [
        "/usr/local/bin", "/usr/bin", "/bin", "/usr/local/sbin", "/usr/sbin", "/sbin", "/opt/homebrew/bin"
    ]

    /// `~` is expanded and a bare name is searched on PATH. A value containing
    /// a slash is treated as a path and used only if it is executable.
    public static func resolve(_ value: String, searchPath: String? = nil,
                               exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        search(value, searchPath: searchPath, accepts: exists)
    }

    /// Presence without the execute bit. Needed where a tool's *permissions* are
    /// the thing being diagnosed — `dumpcap` is mode 750 `root:wireshark`, so an
    /// executable-only lookup reports it as absent on the very machine where its
    /// group gate is the problem.
    public static func locate(_ value: String, searchPath: String? = nil,
                              exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String? {
        search(value, searchPath: searchPath, accepts: exists)
    }

    private static func search(_ value: String, searchPath: String?, accepts: (String) -> Bool) -> String? {
        let expanded = (value as NSString).expandingTildeInPath
        if expanded.contains("/") {
            return accepts(expanded) ? expanded : nil
        }
        let path = searchPath ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
        var directories = path.split(separator: ":").map(String.init)
        directories.append(contentsOf: fallbackDirectories)
        for directory in directories where !directory.isEmpty {
            let candidate = directory + "/" + expanded
            if accepts(candidate) { return candidate }
        }
        return nil
    }
}
