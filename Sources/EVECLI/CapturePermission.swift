import Foundation

/// Wireshark on Fedora routes even a stdin capture through `dumpcap`, and that
/// binary ships as mode 750 `root:wireshark`. An account outside the
/// `wireshark` group therefore gets a permission dialog and an empty capture
/// window, which reads as eve-connect failing. This turns that into a plain
/// sentence with the fix in it.
public enum CapturePermission {
    public static let remedy = "run: sudo usermod -aG wireshark $USER  (then log out and back in)"

    /// What the capture path can expect, and whether it is blocked. A machine
    /// with no dumpcap on PATH — macOS, where Wireshark bundles it inside the
    /// app — has no such gate to check.
    public static func status(
        dumpcap: String? = ToolLookup.locate("dumpcap"),
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> (text: String, blocked: Bool) {
        guard let dumpcap else { return ("no dumpcap on PATH; no group gate to check", false) }
        if isExecutable(dumpcap) { return ("\(dumpcap) is executable by this account", false) }
        return ("\(dumpcap) is not executable by this account, so Wireshark would capture nothing. Fix: \(remedy)", true)
    }
}
