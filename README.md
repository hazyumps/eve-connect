# EVE Connect

A native replacement for the EVE-NG client pack's browser integration. Opens
telnet consoles in **Ghostty**, graphical consoles in **RealVNC Viewer**
(macOS) or **TigerVNC** (Linux), and remote packet captures in **Wireshark**.

Two builds share one parser and one test suite:

| | |
| --- | --- |
| macOS | `EVEConnect` — a menu-bar helper app that registers with LaunchServices |
| Linux | `eve-connect` — a CLI registered as an XDG scheme handler by a desktop entry |

Not affiliated with EVE-NG Ltd. This replaces the client pack's browser
integration; it bundles none of its software.

## Install

There is no signed download yet, so both platforms build from source. A bundle
built on your own machine carries no quarantine flag and needs no Gatekeeper
approval.

macOS 14 or newer, with Xcode command-line tools:

```sh
git clone https://github.com/hazyumps/eve-connect
cd eve-connect
bash scripts/build-app.sh          # prints dist/build-XXXXXX/EVE Connect.app
cp -R "dist/build-XXXXXX/EVE Connect.app" /Applications/
open "/Applications/EVE Connect.app"
```

Then pick **EVE Connect Settings…** from the menu bar, confirm the dependency
checks are green, and press **Make default for EVE links**. That last button is
the cutover — opening the app alone changes nothing.

Linux, with Ghostty, `telnet`, a VNC viewer and Wireshark already installed:

```sh
swift build -c release             # Fedora: sudo dnf install swift-lang, then swift build
install -m755 .build/release/eve-connect ~/.local/bin/eve-connect
eve-connect --init && eve-connect --install
```

## Status

Version 0.2.2: a background menu-bar helper with a custom native app icon.
The app builds and launches on Apple Silicon. Manual link testing confirmed
Ghostty windows/tabs, VNC, and packet capture against a live EVE-NG server.
Fourteen core tests cover URL validation, VNC port translation, command quoting,
the Linux console plan, Ghostty AppleScript compilation, capture data/EOF
delivery, viewer-close cleanup, and SSH failure reporting. Automated capture
tests use local fixture processes. An isolated app copy also verified cold URL
launch without a window, accessory activation policy (no Dock entry), dispatch
after closing settings, reopening settings, and a visible error alert.
Safari/Firefox handoff through the default handlers is not yet verified.

The Linux CLI carries the same URL parser, launch plans, and capture pipeline;
thirty-four further tests cover its configuration file, desktop entry and
scheme registration, program lookup, and subprocess handling. It replaces the
macOS shell with an XDG desktop entry for scheme registration,
`ghostty +new-window` for consoles, a config file instead of a settings window,
and `notify-send` for failures. See [Linux](#linux-eve-connect) below.

## Requirements

macOS:

- macOS 14 or newer; Swift 6 / Xcode command-line tools to build.
- Ghostty with the scripting interface shipped in 1.3.1, with
  `macos-applescript` enabled (the default).
- Native telnet executable, normally `/opt/homebrew/bin/telnet` on Apple Silicon.
- RealVNC Viewer. Other VNC clients may use different command-line syntax.
- Wireshark. Both `/Applications/Wireshark.app` and the existing
  `/Applications/Eve Wireshark.app` are detected.
- For captures: working noninteractive SSH authentication, an existing trusted
  host-key entry, and permission to run `tcpdump` on the EVE server.

Linux:

- Ghostty 1.3.1 or newer with the GTK build, which is what provides the
  `+new-window` action.
- `telnet`, a VNC viewer, and Wireshark from the distribution. On Fedora 44:
  `sudo dnf install telnet wireshark tigervnc`. The Swift toolchain is packaged
  there too — `sudo dnf install swift-lang`, currently 6.3.2.
- Membership of the `wireshark` group on Fedora. `dumpcap` is mode 750
  `root:wireshark`, and Wireshark uses it even for a capture read from stdin, so
  without the group a capture window opens empty:
  `sudo usermod -aG wireshark $USER`, then log out and back in. `--check`
  reports this, and a capture link stops before opening a viewer at all.
- The same capture prerequisites: noninteractive SSH authentication, a trusted
  host key, and `tcpdump` on the EVE server.

The viewers and telnet are external dependencies; this app does not bundle them.

### macOS permissions on first run

Two prompts, both one-time and both expected:

- **Automation** — the first console link asks permission to control Ghostty.
  Refusing it leaves every console link failing until you re-enable EVE Connect
  under System Settings → Privacy & Security → Automation.
- **Local Network** — on macOS 26 and newer, the first link to a private-range
  EVE server (10.x, 192.168.x, 172.16–31.x) asks for local network access. A
  denied prompt shows up as an instant connection failure to an address you can
  ping from a shell, which is TCC rather than networking.

## Build and test

```sh
swift test
bash scripts/build-app.sh
```

On Linux there is no `.app` to assemble:

```sh
swift build -c release
install -m755 .build/release/eve-connect ~/.local/bin/eve-connect
```

The build prints the path to a fresh `dist/build-XXXXXX/EVE Connect.app`. Each
build gets a separate directory. Builds target the current machine's architecture.

The bundle is **ad-hoc signed** — no Developer ID, no notarization. That is
enough for a build made on your own machine, which never carries a quarantine
flag, and not enough for a download. Gatekeeper assesses anything marked
`com.apple.quarantine`, and an ad-hoc bundle fails that assessment: the same
`.app`, zipped and downloaded, will not launch until its user allows it under
System Settings → Privacy & Security. Control-click → Open stopped bypassing
that as of macOS Sequoia. `SIGNING_IDENTITY` selects a signing identity at build
time; a notarized release pipeline does not exist yet.

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

### Ghostty (macOS)

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

### Packet captures (macOS)

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

## Linux (`eve-connect`)

The same three link types, aimed at the desktop instead of LaunchServices.
`eve-connect <link>` parses the URL and starts the right viewer. There is no menu
bar and no settings window: configuration is a file, and failures are a desktop
notification plus a line on stderr.

```sh
eve-connect --init      # write ~/.config/eve-connect/config.toml
eve-connect --check     # resolved programs, and what handles each scheme now
eve-connect --install   # write the desktop entry and become the handler
eve-connect --dry-run 'capture://eve.example.com/vunl0_1_0'
```

`--install` writes `~/.local/share/applications/eve-connect.desktop`, whose
`MimeType` claims `x-scheme-handler/telnet`, `…vnc` and `…capture`, and then runs
`update-desktop-database` plus `xdg-mime default` for each scheme. That is the
LaunchServices job: Firefox hands an unknown scheme to `xdg-open`/GIO, which
resolves it through `~/.config/mimeapps.list`. No GNOME components are involved,
so this works as well under Hyprland as under Workstation.

`vncviewer` from TigerVNC is the default VNC target. RealVNC publishes no
Fedora viewer package — its combined VNC Connect RPM wants Wayland disabled,
which is a poor fit on a Wayland desktop — and both viewers take the same
`host::port` absolute-port form.

Differences from the macOS build, all deliberate:

| | macOS | Linux |
| --- | --- | --- |
| Console | Ghostty AppleScript, window or tab | `ghostty +new-window -e …`, always a window |
| VNC | one window per link, RealVNC | one window per link, TigerVNC; a repeat on the same node takes over unless `vnc_shared` |
| Failed console | `wait after command` keeps the surface | the wrapper prints the exit status and waits for Enter |
| Close confirmation | OSC 133 workaround (Ghostty 1.3.1 has no per-surface option) | unnecessary when `confirm-close-surface = false` |
| Settings | menu-bar window | `config.toml`, `--check` |
| Stop captures | menu item | each capture is its own process; close Wireshark, or stop the `eve-connect` child |
| Errors | alert and settings window | `notify-send`, plus `~/.local/state/eve-connect/capture.log` for a detached capture |

A bare `ghostty -e` cannot replace the AppleScript path: any command-line
argument turns `gtk-single-instance` off, so it would start a second Ghostty
instead of a window in the one already running. `+new-window` hands the command
to the running instance over D-Bus and forwards only `--working-directory`,
`--command` and `--title`, which is why `wait-after-command` is not available
there and the wrapper holds a failed console open instead.

Three platform notes worth knowing before blaming the app. Consoles always open
as new **windows**: Ghostty 1.3.1's CLI has `+new-window` and no `+new-tab`, so
the macOS "prefer tab" preference has no Linux equivalent — move a surface into
a tab with Ghostty's own keybind if you want one. Fedora's capture gate is real:
`dumpcap` is mode 750 `root:wireshark`, Wireshark uses it even for a stdin
capture, and without the `wireshark` group the capture comes back empty — so
`--check` reports it and a capture link refuses to open a viewer rather than
showing an empty one. And the VNC and Wireshark viewers need an X display:
launched from a desktop entry they inherit the session's `DISPLAY`, but running
`eve-connect` from a bare TTY leaves them unable to open a window.

A capture link detaches. The process the desktop entry started re-runs itself
with `--capture-session` and exits immediately, so the browser is never held
open for the life of the capture and the SSH-to-Wireshark pipe outlives it.

Config keys, all optional: `terminal`, `telnet`, `vnc`, `wireshark`, `ssh_user`
and `identity_file`, each a `PATH` name or an absolute path, plus `vnc_shared`
(true or false, default false). `--config <path>` overrides the file location,
and `EVE_CONNECT_CONFIG` does the same from the environment.

A VNC server drops its other connections unless the client asks to share, so a
second viewer on the *same* node takes the session over. That is the useful
default — reconnecting to a node you left open gets your session back — and
`vnc_shared = true` keeps both windows instead (TigerVNC's `-Shared`, passed
through to whichever viewer is configured). Different nodes are separate
sessions and never interact.

## Switching over from the client pack (macOS)

1. From the app's link field, connect to a running EVE node using its actual console
   port. Verify interactive input, control keys, Ghostty initially closed/open,
   multiple consoles, and both window/tab modes.
2. Open a VNC node and verify the exact EVE TCP port is used.
3. Start a capture on a real interface. Verify packets arrive, two simultaneous
   captures work, SSH failures are visible, and closing a viewer ends its SSH
   process. Verify stopping a stream leaves captured packets available for saving.
4. Move the app to a stable location such as `/Applications`, choose **Make
   default for EVE links**, and click console/VNC/capture links from Safari and
   Firefox. Firefox may retain its own per-protocol application choice; update it
   if it still opens the old app.

The client pack's own apps can stay installed while you verify this: nothing here
removes them, and switching back is the same handler control that switched over.
Automated handler rollback, an installer, automatic updates, and notarization are
not part of this build.

## Source layout

- `Sources/EVECore`: URL parsing, launch plans for both platforms, capture
  process lifecycle. Foundation only, so it builds on macOS and Linux.
- `Sources/EVECLI`: the headless client — config file, desktop entry and scheme
  registration, viewer launching, notifications.
- `Sources/EVEConnectCLI`: `main.swift` for the `eve-connect` command.
- `Sources/EVEConnect`: AppKit URL delivery, SwiftUI settings, application
  launchers. macOS only; declared in `Package.swift` behind `#if os(macOS)`.
- `Tests/EVECoreTests`, `Tests/EVECLITests`: validation and local subprocess
  integration tests. The AppleScript compile check is macOS-only.
- `Resources`: bundle metadata and Automation entitlement.
- `scripts/build-app.sh`: release build, bundle assembly, local signing verification.
- `scripts/render-icon.swift`: original terminal/network vector artwork, rendered
  at every macOS icon size during the build; also emits `icon-preview.png`.
- `docs/linux-port-research.md`: the sources behind the Linux decisions —
  Ghostty's `+new-window`, XDG scheme registration, Foundation on Linux, and
  what is packaged for Fedora — kept so the next port does not repeat it.
- `.github/workflows/ci.yml`: `swift build` and `swift test` on macOS and Linux,
  plus a bundle assembly on macOS so the AppleScript compile check runs.

## License

MIT — see [LICENSE](LICENSE).
