# MuteMe Bar

A lightweight native Swift menu-bar app for macOS that reads touch events from a MuteMe button and toggles Zoom mute — no Electron, no heavy runtime.

**Memory footprint:** ~10–20 MB (vs hundreds of MB for the official Electron app).

## Features

- Tap the MuteMe button to toggle Zoom mute (sends the `Cmd+Shift+A` global shortcut).
- Menu-bar icon reflects Zoom's **actual** mute state (read via the Accessibility API), even if you mute from inside Zoom or the host mutes you.
- **LED control**: off when not in a meeting, green when unmuted, red when muted.
- Fast feedback: pressing the button updates the icon/LED within ~150 ms.
- Built-in verbose HID logging for debugging.
- Optional **Launch at Login**.

## Requirements

- macOS 13 Ventura or later (arm64 or x86_64)
- Xcode Command Line Tools: `xcode-select --install` (you likely have this already — verify with `swift --version`)
- A MuteMe button (any generation)

## Quick start

```bash
# 1. One-time: create a stable code-signing certificate so macOS permissions
#    persist across rebuilds (asks for your admin password once).
./scripts/create-signing-cert.sh

# 2. Build and assemble the signed .app bundle at a stable path
./scripts/make-app.sh

# 3. Launch it
open ./build/MuteMeBar.app
```

On first launch, two macOS permission dialogs will appear. Grant both:

- **Accessibility** — REQUIRED. Posts the keyboard shortcut to Zoom AND reads Zoom's mute state.
- **Input Monitoring** — listed for completeness; the MuteMe is a vendor HID and usually works even without this.

Then [enable Zoom's global shortcut](#zoom-setup).

> **Why the certificate?** macOS ties Privacy permissions to an app's code
> identity. An unsigned (or ad-hoc signed) app gets a new identity on every
> rebuild, so permissions reset constantly. Signing with the stable self-signed
> certificate created in step 1 keeps the identity constant, so you grant
> permissions once. See [docs/03-setup-and-permissions.md](docs/03-setup-and-permissions.md).

## Zoom setup (required)

The app sends `Cmd+Shift+A` to Zoom. For this to work when Zoom isn't the focused app:

1. Open **Zoom** → click your profile picture → **Settings**
2. Click **Keyboard Shortcuts**
3. Find **Mute/Unmute My Audio** (`Cmd+Shift+A`)
4. Check **Enable Global Shortcut** ✓

## Code signing

The build is signed so macOS Privacy permissions persist. Two scripts manage this:

```bash
# One-time: create the stable self-signed signing certificate (admin password once)
./scripts/create-signing-cert.sh

# Force-recreate the certificate (removes the old one first)
./scripts/create-signing-cert.sh --force
```

`make-app.sh` automatically signs with this certificate if it exists, otherwise it
falls back to ad-hoc signing (which works but loses permissions on each rebuild).

## Rebuilding

Always use the script — it outputs to the same path and signs with the stable identity:

```bash
./scripts/make-app.sh           # release (default)
./scripts/make-app.sh --debug   # debug build
```

Running `swift run` directly is fine for quick iteration, but it won't have the
stable signed identity, so permissions and Launch at Login won't work reliably.

## Permissions troubleshooting

If the app's menu bar icon shows `Accessibility: ✗` (and mute detection always says "Not in meeting"):

1. Make sure you ran `./scripts/create-signing-cert.sh` and rebuilt with `./scripts/make-app.sh`
2. Open **System Settings → Privacy & Security → Accessibility**
3. Remove any stale `MuteMeBar` entries (`−`), then re-add `MuteMeBar.app` from `./build/`
4. Quit and reopen the app

## Menu items

| Item | Description |
|------|-------------|
| Status: Muted / Unmuted / Not in meeting | Zoom's actual mute state |
| Verbose Logging | Toggle live HID event logging (view in Console.app, filter by "MuteMeBar") |
| Copy Debug Log | Copy last 200 HID events to clipboard |
| Launch at Login | Toggle starting MuteMe Bar automatically at login |
| Input Monitoring: ✓/✗ | Permission status — click ✗ to open System Settings |
| Accessibility: ✓/✗ | Permission status — click ✗ to open System Settings |
| Quit MuteMe Bar | Quit |

## Debug / verify your device

Enable **Verbose Logging** from the menu, then press the button. You should see in Console.app:

```
[MuteMe] Connected: MuteMe VID=0x3603 PID=0x0001
[MuteMe] 0x04 → startTouch
[MuteMe] 0x01 → touching
[MuteMe] 0x02 → endTouch
[MuteMe] 0x00 → clear
```

Use **Copy Debug Log** to paste this into a text file for reference.

## Project structure

```
MyMuteMe/
  docs/
    00-overview.md             Goals, decisions, target device
    01-hid-protocol.md         VID/PID table, touch + LED byte maps
    02-architecture.md         Module layout, data flow
    03-setup-and-permissions.md  Build, TCC, Zoom global shortcut
    04-roadmap.md              Phases including future LED control
  Package.swift
  Sources/MuteMeBar/
    main.swift                 Entry point
    AppDelegate.swift          NSStatusItem, menu, Launch at Login
    MuteMeDevice.swift         IOKit HID layer, touch decoding, LED output
    KeySender.swift            CGEvent Cmd+Shift+A injection
    MuteController.swift       Event wiring, LED sync
    ZoomStatePoller.swift      Reads Zoom mute state via Accessibility API
    PermissionsManager.swift   TCC Input Monitoring + Accessibility
    Info.plist                 LSUIElement=true, bundle ID
  scripts/
    create-signing-cert.sh     Creates the stable code-signing certificate
    make-app.sh                Builds, signs, and assembles .app at stable path
```

## Future work

See `docs/04-roadmap.md` for the full roadmap. Highlights:

- **Push-to-talk mode** — unmute on touch start, remute on touch end
- **Multi-app support** — Teams, Google Meet shortcuts
- **LED effects** — dim/pulse modes (protocol documented in `docs/01-hid-protocol.md`)

## Supported devices

| Device | VID | PID |
|--------|-----|-----|
| MuteMe Original Batch 009+ *(your device)* | 0x3603 | 0x0001 |
| MuteMe Mini USB-C | 0x3603 | 0x0002 |
| MuteMe Mini USB-A | 0x3603 | 0x0003 |
| MuteMe Mini Generic | 0x3603 | 0x0004 |
| MuteMe Original Batch 001-008 | 0x20a0 | 0x42da |
| MuteMe Mini Batch 001-008 | 0x20a0 | 0x42db |
| MuteMe Prototype | 0x16c0 | 0x27db |

## License

[MIT](LICENSE) © Cameron Banta

## Disclaimer

This is an unofficial, independent project. It is not affiliated with, endorsed
by, or associated with MuteMe or Zoom. "MuteMe" and "Zoom" are trademarks of
their respective owners.
