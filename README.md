# EVE Connect

A native macOS replacement for the EVE-NG client pack's browser integration.
Opens telnet consoles in **Ghostty**, graphical consoles in **RealVNC Viewer**,
and remote packet captures in **Wireshark**.

## Status

Version 0.2.2: a background menu-bar helper with a custom native app icon.
The app builds and launches on Apple Silicon. Manual link testing confirmed
Ghostty windows/tabs, VNC, and packet capture on the user's EVE server.
Eleven automated tests cover URL validation, VNC port translation, command quoting,
Ghostty AppleScript compilation, capture data/EOF delivery, viewer-close cleanup,
and SSH failure reporting. Automated capture tests use local fixture processes.
An isolated app copy also verified cold URL launch without a window, accessory
activation policy (no Dock entry), dispatch after closing settings, reopening
settings, and a visible error alert. Safari/Firefox handoff through the default
handlers still needs verification at cutover.

## Requirements

- macOS 14 or newer; Swift 6 / Xcode command-line tools to build.
- Ghostty with the scripting interface shipped in 1.3.1, with
  `macos-applescript` enabled (the default).
- Native telnet executable, normally `/opt/homebrew/bin/telnet` on Apple Silicon.
- RealVNC Viewer. Other VNC clients may use different command-line syntax.
- Wireshark. Both `/Applications/Wireshark.app` and the existing
  `/Applications/Eve Wireshark.app` are detected.
- For captures: working noninteractive SSH authentication, an existing trusted
  host-key entry, and permission to run `tcpdump` on the EVE server.

The viewers and telnet are external dependencies; this app does not bundle them.

## Build and test

```sh
swift test
bash scripts/build-app.sh
```

The build prints the path to a fresh `dist/build-XXXXXX/EVE Connect.app`. Each
build gets a separate directory. Builds target the current machine's architecture.
The local build is **ad-hoc signed**, not Developer ID signed or notarized.
Set `SIGNING_IDENTITY` to a suitable signing identity for Developer ID signing;
notarization/distribution packaging is not implemented yet.

Open that `.app`, then choose **EVE Connect Settings…** from its terminal icon in
the menu bar to see dependency checks, current handlers, and a field for trying
a link. Opening the app does **not** explicitly change default handlers.
The **Make default for EVE links** button is the separate cutover action.

## Background operation

Browser links dispatch directly to the appropriate viewer without showing EVE
Connect's settings or adding a Dock icon. Once registered as the default handler,
macOS launches the helper on demand—even if it was previously quit. There is no
login item or requirement to start it before opening EVE.

Closing settings keeps the helper and capture streams running. The terminal icon
in the menu bar provides **Settings**, **Stop capture streams**, and **Quit**.
Launching the application directly in Finder or reopening it also stays in the
menu bar. Settings open only from **EVE Connect Settings…**, or when an error needs
attention. This also prevents browsers' reopen events from showing settings before
delivering a link. Errors bring up settings and an alert so failures remain visible.

Headless checks neither start viewers nor connect to a server:

```sh
swift run EVEConnect --dry-run 'telnet://eve.example:32769'
swift run EVEConnect --dry-run 'vnc://eve.example:32770'
swift run EVEConnect --dry-run 'capture://eve.example/vunl0_1_0'
```

## How links are handled

| Link | Action |
| --- | --- |
| `telnet://host:port` | Ask Ghostty to create a window/tab running telnet |
| `vnc://host:port` or `vnc://host::port` | Launch RealVNC with `host::port` (absolute TCP port) |
| `capture://host/interface` | Pipe SSH's remote `tcpdump -U -n -i interface -w -` into Wireshark |

Telnet defaults to port 23 and VNC to 5900 when omitted. IPv6 addresses must be
bracketed in the link. Console links may have a trailing slash. Credentials,
queries, fragments, URL escapes, and extra paths are rejected. Capture interfaces
use Linux's 15-character name limit and a restricted character set. Capture links
do not carry SSH credentials or ports; those belong in settings/SSH configuration.

### Ghostty

The first console launch can trigger macOS's Automation permission prompt. Allow
EVE Connect to control Ghostty. The app uses Ghostty's `new surface configuration`
and `new window`/`new tab` commands, not keyboard simulation. A tab preference
falls back to a window when there is no existing window. Failed console commands
leave their terminal visible so the connection error can be read.

EVE console tabs emit OSC 133 prompt/input markers before replacing their launcher
with telnet. This avoids Ghostty's normal running-process close confirmation for
these disposable connections, without changing other tabs or the user's Ghostty
configuration. Ghostty 1.3.1 does not expose `confirm-close-surface` in its
AppleScript surface configuration, so this is a shell-integration workaround.
An explicit global `confirm-close-surface = always`, a remote shell's own OSC 133
markers, a terminal reset, or entering the alternate screen can restore the
confirmation. It applies to newly opened EVE consoles, not existing tabs.

### Packet captures

The default SSH user is `root`, matching the old pack. The identity field is blank
by default to use SSH configuration and the agent. To reuse the old pack's existing
identity, select its existing path (`~/.ssh/eve`) in that field; the app does not
copy keys or create new credentials. Per-host identities and SSH ports can be
configured through `~/.ssh/config`. The settings window currently has one global
SSH user; per-server user profiles are a later enhancement.

Capture uses batch mode and strict host-key checking. Authentication and host
trust must be established separately; no password prompt or automatic key upload
is hidden behind a browser click. Errors appear in the app.

Each capture has independent processes and pipes. Closing its Wireshark process
ends SSH. **Stop capture streams** and quitting EVE Connect stop SSH but leave
Wireshark windows open for saving. A session remains listed while its viewer is
open. Pressing Stop inside Wireshark alone is not an app-level lifecycle signal;
use EVE Connect's stop button to explicitly stop its SSH stream.

## Manual acceptance before cutover

1. From the app's link field, connect to a running EVE node using its actual console
   port. Verify interactive input, control keys, Ghostty initially closed/open,
   multiple consoles, and both window/tab modes.
2. Open a VNC node and verify the exact EVE TCP port is used.
3. Start a capture on a real interface. Verify packets arrive, two simultaneous
   captures work, SSH failures are visible, and closing a viewer ends its SSH
   process. Verify stopping a stream leaves captured packets available for saving.
4. After approval, place the app at a stable location in `/Applications`, choose
   **Make default for EVE links**, and click console/VNC/capture links from both
   Safari and Firefox. Firefox may retain its own per-protocol application choice;
   update that browser choice if it still opens the old app.

Existing defaults observed before development: telnet → iTerm; VNC/capture →
Eve Client. Keep the old apps during verification. Automated handler rollback,
an installer, automatic updates, and notarization are not part of this build.

## Source layout

- `Sources/EVECore`: URL parsing, launch plans, capture process lifecycle.
- `Sources/EVEConnect`: AppKit URL delivery, SwiftUI settings, application launchers.
- `Tests/EVECoreTests`: validation and local subprocess integration tests.
- `Resources`: bundle metadata and Automation entitlement.
- `scripts/build-app.sh`: release build, bundle assembly, local signing verification.
- `scripts/render-icon.swift`: original terminal/network vector artwork, rendered
  at every macOS icon size during the build; also emits `icon-preview.png`.
