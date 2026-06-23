# Setup and Permissions Guide

## Build requirements

| Requirement | Check | Install if missing |
|---|---|---|
| Xcode Command Line Tools | `xcode-select -p` | `xcode-select --install` |
| Swift 5.9+ | `swift --version` | Included with CLT |

Your confirmed environment: Swift 6.3.2, macOS 26.5.1, arm64. No additional tools needed.

## Building

```bash
# From the workspace root
swift build

# Run directly (for development — TCC permissions won't be sticky)
swift run
```

## Running with stable TCC permissions

macOS TCC (Transparency Consent and Control) ties permission grants to an app's
**code identity**, not just its path. This has an important consequence:

- An **unsigned** app gets a new identity on most rebuilds (and sometimes every
  launch on macOS 14+/26). Permissions are lost constantly — the Privacy panes
  show the app as `✗`, and you get re-prompted on every launch.
- An **ad-hoc signed** app (`codesign -s -`) is keyed to the binary's content
  hash, which still changes on every rebuild — so grants persist between launches
  of the same build, but not across rebuilds.
- An app signed with a **stable named certificate** keeps the same identity
  across rebuilds, so you grant permissions once and they persist.

### One-time: create a stable signing certificate (recommended)

```bash
./scripts/create-signing-cert.sh   # asks for your admin password once
```

This creates a self-signed "MuteMe Self-Signed" code-signing certificate in your
keychain. After this, `make-app.sh` automatically signs with it.

To remove and recreate the certificate (e.g. if it became invalid), use the
`--force` flag — this deletes any existing "MuteMe Self-Signed" cert from both the
login and System keychains before creating a fresh one:

```bash
./scripts/create-signing-cert.sh --force
```

> After recreating the certificate the app's code identity changes, so you'll
> need to re-grant Accessibility (remove the old `MuteMeBar` entry first).

### Build and run

```bash
./scripts/make-app.sh        # signs with the stable cert if present, else ad-hoc
open ./build/MuteMeBar.app
```

On first run, two permission dialogs appear (or add the app manually beforehand):

1. **Input Monitoring** — declared so the Privacy pane lists the app. Note: the
   MuteMe is a vendor-defined HID and can actually be read without this grant, so
   the button may work even while this shows `✗`.
2. **Accessibility** — REQUIRED for two things: posting the `Cmd+Shift+A`
   keystroke to Zoom, AND reading Zoom's menu bar to detect mute state. If this
   is not granted, mute detection always reports "Not in meeting".

> If you previously ran an unsigned/ad-hoc build, remove any stale `MuteMeBar`
> entries from both Privacy panes (select and click `−`) before re-granting to
> the newly signed app, to avoid duplicate/confusing entries.

## Granting permissions manually

If the dialogs don't appear (e.g., you denied them previously):

1. Open **System Settings → Privacy & Security → Input Monitoring**.
2. Click `+` and add `MuteMeBar.app` (or the binary path if running from `swift run`).
3. Repeat for **Privacy & Security → Accessibility**.
4. Quit and relaunch the app.

> **Important:** If you move or rename the `.app` bundle, macOS treats it as a new binary and will prompt for permissions again. Always use `./scripts/make-app.sh` to rebuild to the same path.

## Zoom global shortcut setup (required)

The app posts `Cmd+Shift+A` to toggle Zoom mute. By default, this shortcut only works while Zoom is the frontmost app. To make it work globally:

1. Open **Zoom** → click your profile picture → **Settings**.
2. Click **Keyboard Shortcuts**.
3. Find **Mute/Unmute My Audio** (`Cmd+Shift+A`).
4. Check **Enable Global Shortcut** next to it.
5. Click outside to save.

Without this, pressing the MuteMe button will only mute Zoom if Zoom's window is already focused.

## App menu items

The menu-bar icon opens a menu with:

| Item | Description |
|------|-------------|
| Muted / Unmuted / Not in meeting | Zoom's actual mute state (read-only) |
| Verbose Logging | Toggle to enable/disable HID debug output to Console.app |
| Copy Debug Log | Copies recent HID events to clipboard |
| Launch at Login | Toggle starting the app automatically at login (via `SMAppService`) |
| Input Monitoring: ✓/✗ | Permission status; click to open System Settings if denied |
| Accessibility: ✓/✗ | Permission status; click to open System Settings if denied |
| Quit | Quit the app |

> **Launch at Login** uses macOS's `SMAppService` and only works on a signed
> `.app` bundle launched from a fixed location (i.e. after `make-app.sh`), not via
> `swift run`. The toggle's checkmark reflects the current registration state.

## Viewing debug output

When verbose logging is on, HID events are sent to `os_log` and appear in **Console.app**. Filter by the process name `MuteMeBar` to see only MuteMe events.

Example output:
```
[MuteMe] Connected: VID=0x3603 PID=0x0001
[MuteMe] 0x04 → startTouch
[MuteMe] 0x01 → touching
[MuteMe] 0x02 → endTouch
[MuteMe] 0x00 → clear
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| No menu-bar icon appears | App crashed or failed to start | Run from terminal with `swift run` and check output |
| Button press does nothing | Input Monitoring not granted | Check menu for permission status |
| Zoom doesn't mute | Accessibility not granted, or Zoom global shortcut not enabled | Grant Accessibility + check Zoom settings |
| "Device not found" in log | Wrong VID/PID, or another app has the device open exclusively | Close other MuteMe software; check `inspect-hid` |
| Permissions prompt doesn't appear | Binary path changed (after rebuild) | Rebuild to same path with `make-app.sh` or add manually in System Settings |
