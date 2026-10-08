# Porting EVE Connect's URL handler to Fedora — research notes

Target: Fedora 44 Workstation + Hyprland/DankMaterialShell, Ghostty 1.3.1, /usr/bin/ghostty. App: macOS helper registering `telnet://host:port`, `vnc://host::port`, `capture://host/iface`.

**Labels** — **V** = read from upstream source or the live box · **D** = stated in vendor/project docs · **I** = my reasoning from V/D, not stated by a source · **U** = unverified, no source found.

---

## 0. Headline corrections to the brief

1. **Ghostty 1.3.1 upstream *does* ship `+new-window` on Linux.** **V** in the `v1.3.1` tag: `src/cli/ghostty.zig` L70 (enum) and L149 (`runMain`), with the GTK implementation in `src/apprt/gtk/ipc/new_window.zig` — [ghostty.zig@v1.3.1](https://raw.githubusercontent.com/ghostty-org/ghostty/v1.3.1/src/cli/ghostty.zig), [ipc/new_window.zig@v1.3.1](https://raw.githubusercontent.com/ghostty-org/ghostty/v1.3.1/src/apprt/gtk/ipc/new_window.zig). **D** for Linux + Hyprland at [ghostty.org/docs/linux/systemd](https://ghostty.org/docs/linux/systemd). The observed action list is missing **three** actions v1.3.1 defines (`+crash-report`, `+boo`, `+new-window`), so it was probably not `ghostty +help` on a stock 1.3.1 build. **One-command test:** `ghostty +new-window --help; echo "exit=$?"` → `exit=0` means it exists. `+new-tab` is genuinely newer: absent from the v1.3.1 enum.
2. **Fedora's Ghostty is a COPR build, not a Fedora package.** `ghostty` has no Fedora package ([Bodhi: 0 updates](https://bodhi.fedoraproject.org/updates/?packages=ghostty)); newest is `scottames/ghostty` ghostty-1.3.1-**4** for f43/f44 ([COPR API](https://copr.fedorainfracloud.org/api_3/build/list/?ownername=scottames&projectname=ghostty&limit=3)). The installed `1.3.1-1.fc44` is an older build of the same upstream tag.
3. **Fedora 44 ships Swift.** `swift-lang 6.3.2-3.fc44` in `updates` — this changes the plan (§6).

---

## 1. Registering a handler for a custom scheme (Hyprland, non-GNOME)

**Mechanism — V.** GLib lowercases the scheme, builds `x-scheme-handler/<scheme>`, and resolves it as an ordinary default app: `gio/gdesktopappinfo.c`, `g_desktop_app_info_get_default_for_uri_scheme()` — `content_type = g_strdup_printf ("x-scheme-handler/%s", scheme_down);` then `g_app_info_get_default_for_type (content_type, FALSE)` ([source](https://gitlab.gnome.org/GNOME/glib/-/raw/main/gio/gdesktopappinfo.c) ~L4799–4811); [API docs](https://docs.gtk.org/gio/iface.AppInfo.html). This is GIO + XDG files only — **no GNOME Shell dependency**, so Hyprland works the same way (**I** from the code path).

`~/.local/share/applications/eve-connect.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=EVE Connect
Exec=/usr/local/bin/eve-connect %u
MimeType=x-scheme-handler/telnet;x-scheme-handler/vnc;x-scheme-handler=capture;
NoDisplay=true
Terminal=false
StartupNotify=false
```

Keys from the [Desktop Entry Spec 1.5](http://specifications.freedesktop.org/desktop-entry-spec/latest/) (**V** in the spec's DocBook source):
- `Type`, `Name`, `Exec` are the required trio. `%u` = "A single URL"; **at most one** `%u` per command
  line, and field codes must not sit inside a quoted argument (§7). Use `%u`, not `%U`.
- `MimeType` = "The MIME type(s) supported by this application" — list all three schemes in one key.
- `NoDisplay=true` = "this application exists, but don't display it in the menus… useful to e.g.
  **associate this application with MIME types**, so that it gets launched from a file manager (or
  other apps), without having a menu entry." **So a NoDisplay entry works fine as a scheme handler.**
- `Terminal` means "runs in a terminal window" → `false`. `StartupNotify` is optional → `false` is honest.
- No polkit/portal permission is involved on this path (**I**).

Registration (**D**, and **V** against the xdg-utils source):

```sh
update-desktop-database ~/.local/share/applications      # rebuild mimeinfo.cache for that dir
xdg-mime default eve-connect.desktop x-scheme-handler/telnet
xdg-mime default eve-connect.desktop x-scheme-handler/vnc
xdg-mime default eve-connect.desktop x-scheme-handler/capture
```

- **Yes, `[Default Applications]` in `~/.config/mimeapps.list` is required** — and `xdg-mime default`
  writes it: `make_default_generic()` sets `default_file="$(get_xdg_config_home)/mimeapps.list"` and
  inserts `mimetype=application` under `[Default Applications]`
  ([xdg-mime.in](https://gitlab.freedesktop.org/xdg/xdg-utils/-/raw/master/scripts/xdg-mime.in) ~L318–370).
  Hand-editing is equivalent:
  ```ini
  [Default Applications]
  x-scheme-handler/telnet=eve-connect.desktop;
  ```
- `xdg-mime` runs `update-mime-database`, **not** `update-desktop-database` (**V**: only the former
  appears in xdg-mime.in) — run the latter yourself after installing the `.desktop`.
- `xdg-desktop-portal` is not needed for `gio`/browser handoff by default (**I**), but is in the loop
  if the browser routes through the portal's `OpenURI` (gotcha below).

Queries to debug with:

```sh
xdg-mime query default x-scheme-handler/telnet
gio mime x-scheme-handler/telnet
gio open 'telnet://host:port'          # exercises the browser's path
gtk-launch eve-connect.desktop '%u'    # sanity-check the Exec line alone
```

**Gotchas, most likely first**
- **Stale `mimeinfo.cache` masking a valid association** — current (2026-09) GLib bug:
  `get_recommended_for_type()`/`get_all_for_type()` return **empty** when a same-ID `.desktop` exists
  in a higher-priority dir whose cache wasn't regenerated, so xdg-desktop-portal's app chooser shows
  "no apps installed that can open this" **while `gio open` and `xdg-mime query default` still work**
  (they use `get_default_for_type`, which bypasses masking). Fix: re-run `update-desktop-database`
  in the user dir — [GNOME/glib#4057](https://gitlab.gnome.org/GNOME/glib/-/work_items/4057).
- Legacy `~/.local/share/applications/mimeapps.list` or a system
  `/usr/share/applications/mimeapps.list` can shadow the user preference — xdg-mime searches several
  `mimeapps.list` files in priority order (**V**, `check_mimeapps_list`).
- Browsers cache the resolved handler; restart Firefox/Chrome after changing the desktop file (**I**).

---

## 2. Do browsers hand `telnet://` to the desktop entry?

**Firefox on Linux — V.** `uriloader/exthandler/unix/nsMIMEInfoUnix.cpp`, `nsMIMEInfoUnix::LaunchDefaultWithFile()` gets `nsIGIOService` then calls `giovfs->GetAppForMimeType(mSchemeOrType, getter_AddRefs(app))` and `app->LaunchWithURI(uri, nullptr)` ([source](https://raw.githubusercontent.com/mozilla-firefox/firefox/main/uriloader/exthandler/unix/nsMIMEInfoUnix.cpp)) — i.e. **Firefox asks GIO for the scheme's default app**, which is exactly the §1 lookup. Firefox prompts for unhandled external protocols, stores the per-protocol answer in `handlers.json`, and the relevant pref is `network.protocol-handler.external.<scheme>` (referenced at `modules/libpref/init/StaticPrefList.yaml` L15604, which documents the transient-user-gesture rule for external protocols). **A stale `handlers.json` choice overrides the system default** — the browser-side twin of macOS's stale association.

**Is `telnet://` already claimed?** I found **no** Fedora package claiming `x-scheme-handler/telnet`, and the telnet client is not installed by default (parent-verified: `telnet-0.17-96.fc44` available in the `fedora` repo). Marked **U** in both directions — no source asserts a claimant, and none asserts there is none. Decisive check on the box: `xdg-mime query default x-scheme-handler/telnet` and `gio mime x-scheme-handler/telnet`.

**Chrome/Chromium on Linux — partly V.** `chrome/browser/shell_integration_linux.cc`: `GetDirectLaunchMimeTypeHandler()` returns `base::StrCat({"x-scheme-handler/", scheme, ";"})` (L333); `GetApplicationNameForScheme()` resolves the scheme's desktop file and falls back to the literal string `u"xdg-open"` when nothing is registered (L846); `x-scheme-handler/*` is explicitly treated as *protocol* handler rather than file handler (comment L788–794) ([source](https://raw.githubusercontent.com/chromium/chromium/main/chrome/browser/shell_integration_linux.cc)). So Chromium also goes through the XDG scheme MIME type. **Difference in practice:** Firefox delegates to GIO and honours `handlers.json`; Chromium resolves the desktop file itself, applies its own external-protocol prompt/allow-list, and falls back to `xdg-open`. Whether Chromium hard-refuses `telnet://` on Linux is **U**.

---

## 3. Ghostty on Linux: the CLI surface that matters

**`+new-window` works on Linux (GTK) and is the direct replacement for the macOS AppleScript path — V.** In `v1.3.1`: "Available since: 1.2.0"; doc comment says **"Only supported on GTK"** (so the *unsupported* platform is macOS) and **"On GTK, D-Bus activation must be properly configured. Ghostty does not need to be running for this to open a new window"** ([new_window.zig@v1.3.1](https://raw.githubusercontent.com/ghostty-org/ghostty/v1.3.1/src/cli/new_window.zig)). **D** on the website, with `bind = SUPER, return, exec, ghostty +new-window` for Hyprland.

```sh
ghostty +new-window                                   # new window in the running instance
ghostty +new-window -e /usr/bin/telnet host port      # new window running a specific argv
ghostty +new-window --title="eve:host" -e telnet host port
```

**`-e` semantics: argv, not shell-split — V.** `Config.parseManuallyHook` consumes **everything after `-e` as argv** into `initial-command` as a `.direct` command — no shell, no quote parsing, no further flag parsing ([Config.zig@v1.3.1](https://raw.githubusercontent.com/ghostty-org/ghostty/v1.3.1/src/config/Config.zig) ~L4674–4721). `Command.parseCLI` has two shapes: bare string → `.shell` (shell-expanded); `direct:a b c` → `.direct` (naive space split, no quote handling) ([command.zig](https://raw.githubusercontent.com/ghostty-org/ghostty/v1.3.1/src/config/command.zig)). So `ghostty -e telnet eve.example 32769` execs `telnet` with that argv — the current macOS behaviour. `+help` confirms: "A special command line argument `-e <command>`… `ghostty -e top` will run the `top` command". `--command=<string>` is the modern spelling of config key `command` (applies to *all* new surfaces); `-e` equals `initial-command` for the first surface only.

**`--wait-after-command` — V.** `@"wait-after-command": bool = false` (Config.zig L1355: "keep the terminal open after the command exits… primarily useful for scripts or debugging"), and `+help` says "All configuration keys are available as command line options". **Order matters:** put config flags *before* `-e` (`ghostty --wait-after-command=true -e telnet host port`), because everything after `-e` becomes the command. In `+new-window` only `--working-directory`, `--command`, `--shell-integration` and `--title` are forwarded to the first surface (**V**, source doc comment) — `--wait-after-command` is **not** in that set.

**`gtk-single-instance` — V, and `-e` defeats it.** Default `.default` = `detect`, which resolves to `.true` **unless `TERM_PROGRAM` is set or any CLI argument exists**, in which case it is forced `.false` ("Single instance mode inherits the configuration from when it was launched, so we must disable single instance to load the new configuration" — Config.zig ~L3536–3565, ~L4613–4625). `-e` additionally forces `gtk-single-instance = .false`, `quit-after-last-window-closed = true`, delay `null`.

Consequences for the port:
- `ghostty -e telnet host port` → **a separate Ghostty process per console**; new window, but not the
  running instance, and it exits with telnet. Works with or without Ghostty already running.
- `ghostty +new-window -e telnet host port` → **new window inside the running instance**, or D-Bus
  activation starts Ghostty if none is running. That is the AppleScript behaviour, and the one to port.
- **D-Bus interface (V)**: bus name `com.mitchellh.ghostty`, object path `/com/mitchellh/ghostty`, GTK
  application actions. Source-documented equivalents:
  ```
  gdbus call --session --dest com.mitchellh.ghostty --object-path /com/mitchellh/ghostty \
    --method org.gtk.Actions.Activate new-window [] []
  gdbus call --session --dest com.mitchellh.ghostty --object-path /com/mitchellh/ghostty \
    --method org.gtk.Actions.Activate new-window-command '[<@as ["-e" "echo" "hello"]>]' []
  ```
  Release build → `com.mitchellh.ghostty`; debug → `…-debug`; `--class=` overrides. Service files:
  `$PREFIX/share/dbus-1/services/com.mitchellh.ghostty.service`,
  `$PREFIX/{share,lib}/systemd/user/app-com.mitchellh.ghostty.service` (**D**).

---

## 4. RealVNC Viewer on Fedora

**Packaging.** No Fedora package for RealVNC. Fedora ships **TigerVNC 1.16.2-4.fc44** instead ([mdapi f44](https://mdapi.fedoraproject.org/f44/pkg/tigervnc)), providing `application(vncviewer.desktop)`. RealVNC ships a **combined VNC Connect (Server + Viewer) RPM** — **V** live: `https://downloads.realvnc.com/download/file/vnc.files/VNC-Server-Latest-Linux-x64.rpm` → HTTP 200, `application/x-redhat-package-manager`; documented install is `sudo yum install -y VNC.rpm` ([Scripting Deployment on Linux](https://help.realvnc.com/hc/en-us/articles/360002253818-Scripting-Deployment-and-Start-up-on-Linux)). A viewer-only RPM/DEB at `.../viewer.files/VNC-Viewer-Latest-Linux-x64.rpm` returns **404** (**V**) — no standalone download found; no Flatpak/Snap/AppImage found in any reachable source (**U**). The advertised Linux flow is a **GUI installer**, and it wants **Wayland disabled**: "If prompted, ensure you choose to accept when asked to disable Wayland, this is needed for RealVNC Connect to function correctly" ([Getting started on Linux](https://help.realvnc.com/hc/en-us/articles/360003474572)). On a Hyprland/Wayland-only session that is a **real risk** for the VNC leg.

**`host::port` (absolute port) — D.** RealVNC: "You may also need to qualify the address with a port number… for example `192.168.5.236:80` for port 5980 or **`192.168.5.236::80` for port 80**" — single colon = display number, **double colon = absolute port** ([All About Direct Connections](https://help.realvnc.com/hc/en-us/articles/360002249797-All-About-Direct-Connections)). The Linux man page agrees: `vncviewer [OPTION...] [HOST][:DISPLAY]` / `[HOST][::PORT]`, and `vncviewer snoopy:2` → port 5902 ([vncviewer man page](https://help.realvnc.com/hc/en-us/articles/360002310477-vncviewer-man-page)). Binary is `vncviewer`; options may be `-<Parameter>=<value>` or a `.vnc` file. **`vncviewer host::32770` is the direct port of the macOS call.**

**URI scheme.** RealVNC registers `com.realvnc.vncviewer.connect://<hostname|ip[:port]>` — **not `vnc://`** — and "the *standalone* RealVNC Viewer won't install the URI handler" ([Can I launch RealVNC Viewer from URIs?](https://help.realvnc.com/hc/en-us/articles/6449870411037-Can-I-launch-RealVNC-Viewer-from-a-link-on-a-web-page-or-program-using-URIs)). Do not rely on `vnc://` reaching RealVNC here; EVE Connect's own handler must invoke the binary.

**TigerVNC fallback.** `vncviewer [options] [host][::port]` is in the TigerVNC synopsis ([tigervnc.org/doc/vncviewer.html](https://tigervnc.org/doc/vncviewer.html)); TigerVNC is in Fedora 44 and is X11-based. Whether Fedora's `vncviewer.desktop` declares `x-scheme-handler/vnc` is **U**.

---

## 5. Wireshark reading a live capture from a pipe

**D**, Wireshark **4.6.9** — the same version as Fedora 44 `updates` ([wireshark(1)](https://www.wireshark.org/docs/man-pages/wireshark.html)):
- `-i|--interface <capture interface>|-`: "Pipe names should be either the name of a FIFO (named pipe)
  or "-" to read data from the standard input." Data must be pcap/pcapng in the capturing host's
  endianness. `tcpdump -U -n -i IFACE -w -` emits little-endian pcap — correct.
- `-k` starts the session immediately; `-i -` alone does not.
- **`-r` is the wrong tool here**: "It's not possible to use named pipes or stdin here, unlike TShark!
  To capture from a pipe or from stdin use **-i -**". So `wireshark -r /dev/stdin` is a dead end, and
  `-i /dev/stdin` is unnecessary — `-i -` is the supported form.
- `-p|--no-promiscuous-mode` **is valid** on 4.6.x (long form documented). A no-op for a pipe, harmless.
- `--temp-dir`, `-X stdin_descr:<description>` exist; `dumpcap(1)` documents the same `-i -` pipe form.

So the one-liner is unchanged from macOS: `ssh host 'tcpdump -U -n -i IFACE -w -' | wireshark -k -i -` (`-U` packet-buffers tcpdump's stdout — without it the GUI can stall on a full buffer). `tshark -i -` also works and is the better choice inside a headless helper.

**Privileges — partly U.** Fedora's convention is `usermod -aG wireshark <user>` so `dumpcap` can open interfaces, with `cap_net_raw,cap_net_admin` on `dumpcap`. My reading: **a pipe needs no capture capability**, because no interface is opened — `dumpcap` only reads stdin — so the `wireshark` group should not be required and no polkit rule is involved (**I**; the Wireshark CapturePrivileges wiki page did not render for me). Verify as a user *not* in the group: `ssh host 'tcpdump -U -n -i IFACE -w -' | wireshark -k -i -`, then `getcap /usr/bin/dumpcap`.

---

## 6. Swift on Fedora 44, and what cannot compile

**Toolchain — three routes:**
1. **Fedora package (best fit).** `swift-lang 6.3.2-3.fc44` (`updates`), depends on `swift-lang-runtime`, gcc, glibc-devel, lld, python3; provides `libswiftCore`, `libFoundation*`, `libFoundationEssentials`, `libFoundationNetworking`, `libFoundationXML`, `libdispatch`, `libswiftDispatch`, `libswift_Concurrency`, `libPackageDescription` (SwiftPM) and `libTestingMacros` (swift-testing). **556 MB RPM / 3.05 GB installed** ([mdapi f44](https://mdapi.fedoraproject.org/f44/pkg/swift-lang)) — **V**.
2. **swiftly**, swift.org's official installer; current release **Swift 6.4.0** — **D**: `curl -O https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz && tar zxf swiftly-$(uname -m).tar.gz && ./swiftly init --quiet-shell-followup && . "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"` ([swift.org/install/linux](https://www.swift.org/install/linux/), [swiftly](https://www.swift.org/install/linux/swiftly)).
3. **Tarball** — the dep list covers Debian 12 / Ubuntu 18–24 / **Red Hat UBI 9** but **not Fedora** ([Linux Installation via Tarball](https://www.swift.org/install/linux/tarball/)); UBI-9's `yum install gcc-c++ libcurl-devel libedit-devel libuuid-devel libxml2-devel ncurses-devel python3-devel sqlite-devel unzip zip rsync` is the nearest Fedora recipe. Static Linux SDK 6.4.0 exists for cross-compilation.

Recommendation: the Fedora `swift-lang` package for a CLI helper (Foundation + dispatch + Swift Testing already present), or swiftly if 6.4.0 specifically is needed. **The `.app` bundle, `Info.plist` registration, LSUIElement/accessory activation policy and `NSApplicationDelegate`-based URL delivery all have no Linux counterpart** — the port replaces them with a `.desktop` file + argv (§1).

**What cannot compile on Linux (D + I).** swift.org scopes the cross-platform set explicitly: "Foundation, libdispatch, and XCTest. In addition there is Swift Testing" ([Swift Core Libraries](https://www.swift.org/documentation/core-libraries/)). **AppKit, SwiftUI, NSApplication, NSAppleScript/AppleScript (`osascript`), ServiceManagement and `.app` bundles are Apple-platform-only with no Linux implementation** — none appears in the cross-platform set, none is among Fedora's `swift-lang` shared libraries (checked above: no AppKit/SwiftUI `.so`), and `osascript` does not exist on Linux (**I** from absence of any provider — safe for these frameworks). Portable: `Foundation` (`URL`, `URLComponents`, `FileHandle`, `Process`, `Pipe`, `FileManager`, `JSONDecoder`), `Dispatch`, Swift concurrency, SwiftPM (`swift build/run/test`), XCTest, Swift Testing.

**Foundation differences that matter (V from source):**
- Swift 6 unifies Foundation across platforms — "Swift 6 unifies the implementation of key Foundation
  API across all platforms… Foundation's modern, portable Swift implementation"
  ([same page](https://www.swift.org/documentation/core-libraries/)). `FoundationEssentials` is the slim subset.
- `URL`/`URLComponents` exist on Linux, but `URLComponents` validates per RFC 3986 and will not
  round-trip `vnc://host::port` cleanly (empty port + stray text). **Keep EVECore's strict parser**
  rather than switching to `URLComponents`. Precise Darwin-vs-Linux `URLComponents` quirks are **U** —
  I found no current tracking issue.

**Runtime behaviour (B) — V from source, since the capture pipeline depends on it:**
- `FileHandle.readabilityHandler` — **implemented on Linux**, backed by
  `DispatchSource.makeReadSource(fileDescriptor:queue:)`, inside `#if canImport(Dispatch)`
  ([FileHandle.swift](https://raw.githubusercontent.com/swiftlang/swift-corelibs-foundation/main/Sources/Foundation/FileHandle.swift)
  L99–198, L128–158). It fires **only if a dispatch main queue is serviced** → a plain CLI binary needs
  `dispatchMain()` (or `RunLoop.main.run()`); otherwise the process exits first (**I**, consistent with the impl).
- `Process.terminationHandler` — **implemented on Linux without the main run loop.** The child is reaped
  by `waitpid()` on a manager thread with its own `RunLoop` (`Process.setup()` spawns
  `Thread { managerThreadRunLoop = RunLoop.current … }`); `terminateRunLoop()` then invokes the handler
  on a fresh `Thread { handler(self) }`
  ([Process.swift](https://raw.githubusercontent.com/swiftlang/swift-corelibs-foundation/main/Sources/Foundation/Process.swift)
  L237–259, L1195–1220).
- `Process.terminate()` — **implemented**: `kill(processIdentifier, SIGTERM)` (non-Windows branch, ~L1065);
  `interrupt()` sends SIGINT.
- `standardInput`/`standardOutput` accept **`Pipe` or `FileHandle`**; launch builds a dup2/close table
  (`adddup2[STDIN_FILENO] = pipe.fileHandleForReading.fileDescriptor`, or `handle.fileDescriptor`), so
  wiring **ssh stdout → wireshark stdin** through one `Pipe` is supported (~L536–600, ~L820–900).
- `@MainActor` + `Task {}` in a plain Linux CLI: **needs `dispatchMain()`** to service the main actor's
  executor (**I**; confirm with a two-line program on the box).

---

## 7. The Linux equivalent of "default handler, launched on demand, no resident process"

**It is the same model, exactly.** A `.desktop` with `MimeType=x-scheme-handler/<scheme>;` + `Exec=… %u` plus a `[Default Applications]` entry *is* LaunchServices: GIO resolves the scheme to your program and spawns it per URL. Nothing resident, no login item, no daemon — directly analogous to the macOS helper launching from a cold quit state. **The Swift helper can stay a short-lived CLI process**, which is the biggest simplification in the port.

When a background process is genuinely needed (keeping SSH capture streams alive across handler runs):

1. **D-Bus activation** — ship `~/.local/share/dbus-1/services/<bus.Name>.service` pointing at your binary and have the desktop file's `Exec` hand the URL to the running instance. The Desktop Entry Spec has this: the launcher calls `Activate` (no URIs), `Open` (array of URIs, UTF-8) or `ActivateAction` at a path derived from the well-known name, and the desktop file must be named like the bus name (`org.example.FooViewer.desktop`) — [Desktop Entry Spec §8](http://specifications.freedesktop.org/desktop-entry-spec/latest/).
2. **systemd user service** — `~/.config/systemd/user/<name>.service`, `systemctl --user enable --now <name>`, logs via `journalctl --user -u <name>`. Ghostty ships exactly this pair and documents both (**D**) — [ghostty.org/docs/linux/systemd](https://ghostty.org/docs/linux/systemd) — including `quit-after-last-window-closed = true` with `quit-after-last-window-closed-delay = 5m` to reclaim memory. Worth copying: exit N minutes after the last viewer closes.
3. **Socket input** — Wireshark also accepts `-i TCP@<host>:<port>` (`-k -i TCP@…`), so a small persistent broker can stream pcap over a socket instead of stdin (**D**, wireshark(1)). Costs a resident process but decouples capture lifetime from the GUI — the cleanest answer if "stop captures" must survive a Wireshark restart.

---

## Open items

- Whether the on-box Ghostty 1.3.1-1.fc44 actually rejects `+new-window` (source and docs say it works)
  → `ghostty +new-window --help; echo $?`.
- Whether `x-scheme-handler/telnet` has a pre-existing claimant on this install.
- Whether Chromium hard-refuses `telnet://` on Linux.
- Whether a standalone RealVNC *Viewer* RPM/Flatpak exists (only the combined Connect RPM verified).
- Whether the `wireshark` group is needed for `-i -` pipes.
- Darwin-vs-Linux `URLComponents` differences for `host::port` (keep EVECore's parser).
- RealVNC's Wayland requirement vs a Hyprland-only Fedora 44 session.
