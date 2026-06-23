# Architecture

## Module overview

```
MuteMe button (USB HID)
       │ input reports (bytes)
       ▼
┌─────────────────────────────────────────────────┐
│  MuteMeDevice                                   │
│  - IOHIDManager: enumerate + match VID/PID list │
│  - IOHIDDevice: open, register input callback   │
│  - Decode byte → TouchEvent enum               │
│  - setLED(byte:) output report (red/green/off)  │
│  - onConnected closure (LED sync on connect)    │
│  - Verbose log closure                          │
└────────────────┬────────────────────────────────┘
                 │ TouchEvent (.startTouch / .touching / .endTouch / .clear / .unknown)
                 ▼
┌─────────────────────────────────────────────────┐
│  MuteController                                 │
│  - Subscribes to MuteMeDevice events            │
│  - Triggers toggle on .startTouch edge only     │
│  - Owns ZoomStatePoller; state is authoritative │
│  - Drives LED + icon from ZoomMuteState         │
│  - Calls KeySender on toggle, then pollBurst()  │
└───┬─────────────────┬──────────────────┬─────────┘
    │                 │                  │
    ▼                 ▼                  ▼
┌──────────┐  ┌────────────────┐  ┌──────────────────────────┐
│KeySender │  │ ZoomStatePoller│  │  AppDelegate / StatusItem │
│CGEvent   │  │ AXUIElement    │  │  NSMenu with:             │
│Cmd+Shift │  │ walk of Zoom's │  │  - Mute state item        │
│+A → Zoom │  │ Meeting menu → │  │  - Verbose log toggle     │
└──────────┘  │ ZoomMuteState  │  │  - Copy debug log         │
              │ (1 s + burst)  │  │  - Launch at Login        │
              └────────────────┘  │  - Permissions status     │
                                  │  - Quit                   │
                                  └──────────────────────────┘
         ▲
┌────────────────────────┐
│  PermissionsManager    │
│  - Input Monitoring    │
│    IOHIDRequestAccess  │
│  - Accessibility       │
│    AXIsProcessTrusted  │
│  - Returns status enum │
└────────────────────────┘
```

## Data flow: tap → Zoom mute

1. User touches MuteMe button.
2. HID firmware sends `0x04` at byte index 3 of an 8-byte input report.
3. `IOHIDDeviceRegisterInputReportCallback` fires on the main run loop.
4. `MuteMeDevice` decodes `0x04` → `TouchEvent.startTouch`, calls `onEvent` closure.
5. `MuteController.onEvent(.startTouch)` fires and calls `KeySender.toggleZoomMute()`.
6. `KeySender` posts `CGEvent` for `Cmd+Shift+A` (key down + key up) to the system event tap.
7. Zoom receives the global keystroke and toggles its own mute state.
8. `MuteController` calls `poller.pollBurst()` — several rapid AX reads — so the
   icon and LED reflect Zoom's new state within ~150 ms instead of waiting for the
   next 1 s tick.

## Data flow: Zoom state → icon + LED

1. `ZoomStatePoller` runs on a 1 s timer (plus burst polls after a button press).
2. It walks Zoom's menu bar via the Accessibility API to find the "Mute audio" /
   "Unmute audio" item under the "Meeting" menu.
3. It maps the result to `ZoomMuteState` (`.muted` / `.unmuted` / `.notInMeeting`).
4. On change, `MuteController` updates the status-bar icon and calls
   `device.setLED(byte:)`: off (not in meeting), green `0x02` (unmuted), red `0x01` (muted).

## Source files

| File | Responsibility |
|------|---------------|
| `main.swift` | Entry point: `NSApplication.shared.run()` |
| `AppDelegate.swift` | `NSApplicationDelegate`, owns `NSStatusItem`, builds/updates the menu, Launch at Login (`SMAppService`), holds `MuteController` |
| `MuteMeDevice.swift` | IOKit HID enumeration, open, input callback, touch decoding, LED output |
| `KeySender.swift` | `CGEvent`-based `Cmd+Shift+A` keystroke injection |
| `MuteController.swift` | Event wiring, owns `ZoomStatePoller`, drives icon + LED |
| `ZoomStatePoller.swift` | Reads Zoom mute state via AXUIElement; `ZoomMuteState` enum; `pollBurst()` |
| `PermissionsManager.swift` | Input Monitoring + Accessibility TCC checks and prompts |
| `Info.plist` | `LSUIElement=true` (no Dock icon), `CFBundleIdentifier`, `NSHumanReadableCopyright` |

## Threading model

All IOKit callbacks are delivered on the main run loop (the device is scheduled with `IOHIDDeviceScheduleWithRunLoop(..., CFRunLoopGetMain(), kCFRunLoopDefaultMode)`). The `ZoomStatePoller` timer and its burst polls also run on the main run loop. All AppKit/UI updates happen on the main thread. No background threads or actors are needed.

## LED control

`MuteMeDevice.setLED(byte:)` sends a single-byte output report via `IOHIDDeviceSetReport`. `MuteController` drives it from `ZoomMuteState`:

- Not in meeting → `0x00` (off)
- Unmuted → `0x02` (green)
- Muted → `0x01` (red)

The LED is also re-synced via the `onConnected` closure when the device connects or reconnects. See `01-hid-protocol.md` for the full LED byte table.
