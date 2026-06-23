# Overview

## Goal

Replace the memory-heavy Electron MuteMe app with a lightweight native Swift menu-bar utility. The Electron app consumes hundreds of MB; this app targets ~10–20 MB.

## What it does

- Reads capacitive touch events from the MuteMe button via IOKit (HID).
- On a tap, posts `Cmd+Shift+A` to toggle Zoom mute/unmute globally.
- Shows a menu-bar icon reflecting mute state.
- Includes a built-in verbose debug log to verify HID byte values from your specific firmware.

## Target device (confirmed)

| Field          | Value              |
|----------------|--------------------|
| iManufacturer  | muteme.com         |
| iProduct       | MuteMe             |
| iSerialNumber  | 100225             |
| idVendor       | 0x3603             |
| idProduct      | 0x0001             |
| bcdDevice      | 25.07              |
| Batch          | 009+ (Original)    |

Additional VID/PID pairs for older/mini batches are matched as fallbacks (see `01-hid-protocol.md`).

## Key decisions

| Decision | Choice | Reason |
|---|---|---|
| Language | Swift | Native, low memory, no runtime dependency, best IOKit integration |
| HID access | IOKit IOHIDManager (not hidapi) | hidapi seizes device exclusively and blocks IOKit; IOKit allows proper macOS integration |
| Keystroke injection | CGEvent | Native, no external dependency |
| App structure | NSStatusItem menu-bar app, LSUIElement=true | No Dock icon, minimal footprint |
| Build system | Swift Package Manager | No Xcode GUI required, reproducible from source |
| LED control | Stubbed, not implemented | Documented for future phase |

## macOS Permissions required

1. **Input Monitoring** — required to open and read the HID device. Prompted via `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` on first launch.
2. **Accessibility** — required to post synthetic keystrokes via `CGEvent`. Prompted via `AXIsProcessTrustedWithOptions` on first launch.

Both can be managed in **System Settings → Privacy & Security**.

## Out of scope (future)

- LED color and effect control (protocol documented, stub in place).
- Push-to-talk mode.
- Launch at login (`SMAppService`).
- Code signing / notarization for third-party distribution.
