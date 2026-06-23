# Roadmap

## Phase 1 — Core (current)

Goal: replace the Electron app with a native menu-bar utility that reliably toggles Zoom mute.

- [x] HID touch event reading via IOKit
- [x] Zoom mute toggle via `CGEvent` (`Cmd+Shift+A`)
- [x] Menu-bar icon with mute state
- [x] Input Monitoring + Accessibility permission management
- [x] Built-in verbose debug log for HID byte verification
- [x] `.app` bundle script for stable TCC permissions

## Phase 2 — Zoom state detection (done)

- [x] Read Zoom's actual mute state via the Accessibility API (`ZoomStatePoller`)
- [x] 3-state model: muted / unmuted / not-in-meeting
- [x] Icon syncs to real state even when muted from inside Zoom or by the host
- [x] Fast-feedback poll burst after a button press (~150 ms)

## Phase 3 — LED Control (done)

- [x] Implement `IOHIDDeviceSetReport` in `setLED(byte:)`
- [x] Drive LED from Zoom state: off (not in meeting), green (unmuted), red (muted)
- [x] Sync LED on device connect/reconnect
- [ ] LED effect options in the menu (dim mode, pulse on connect) — future

## Phase 4 — Code signing (done)

- [x] Stable self-signed certificate (`create-signing-cert.sh`) so TCC permissions persist across rebuilds
- [x] `make-app.sh` signs with the stable identity (ad-hoc fallback)

## Phase 5 — Polish

- [x] Launch at login via `SMAppService` (macOS 13+)
- [ ] Customizable hotkey (instead of hardcoded `Cmd+Shift+A`)
- [ ] Support for other conferencing apps (Teams: `Cmd+Shift+M`, Meet: `Cmd+D`)
- [ ] Push-to-talk mode (unmute on `startTouch`, remute on `endTouch`)
- [ ] Automatic reconnect when button is unplugged and replugged
- [ ] Notarization for distribution to other machines

## Known limitations / technical debt

| Item | Notes |
|------|-------|
| Zoom detection is menu-scraping | Relies on Zoom's "Meeting" menu containing "Mute audio". Would break if Zoom renames the menu item. |
| No auto-reconnect | If the button is unplugged, the app must be restarted to reconnect (IOKit device-removed callback can be added to fix this). |
| `swift run` vs `.app` | Running via `swift run` lacks the stable signed identity, so permissions and Launch at Login won't work reliably. Use `make-app.sh`. |
