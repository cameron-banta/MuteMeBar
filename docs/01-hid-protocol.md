# MuteMe HID Protocol Reference

Source: https://muteme.com/pages/muteme-hid-key

## VID / PID Table

| Device | VID | PID | Notes |
|--------|-----|-----|-------|
| MuteMe Original (prototypes) | 0x16c0 | 0x27db | Early dev units |
| MuteMe Original (production) | 0x20a0 | 0x42da | Batches 001–008 |
| MuteMe Mini (production) | 0x20a0 | 0x42db | Batches 001–008 |
| **MuteMe Original (Batch 009+)** | **0x3603** | **0x0001** | **Your device** |
| MuteMe Mini USB-C | 0x3603 | 0x0002 | |
| MuteMe Mini USB-A | 0x3603 | 0x0003 | |
| MuteMe Mini (Generic) | 0x3603 | 0x0004 | |

The app matches all of the above; `0x3603/0x0001` is the primary target.

## Input Reports (button → host)

Each report is **8 bytes**. The touch state is at **byte index 3** (0-indexed); the other bytes are always `0x00`.

```
Idle:        00 00 00 00 00 00 00 00
Start touch: 00 00 00 04 00 00 00 00
Touching:    00 00 00 01 00 00 00 00  (repeats ~60 Hz while held)
End touch:   00 00 00 02 00 00 00 00
```

Confirmed via `inspect-hid monitor` on VID=0x3603, PID=0x0001, firmware 25.07.

| byte[3] value | Event | Notes |
|------------|-------|-------|
| `0x04` | Start touch | Leading edge — **trigger mute toggle here** |
| `0x01` | Touching | Repeats while finger is held (~60 Hz) |
| `0x02` | End touch | Trailing edge |
| `0x00` | Clear | Idle / reset (streams continuously) |

The app triggers the Zoom mute toggle on `0x04` only (start-touch). The hold (`0x01`) and release (`0x02`) bytes are decoded and logged but do not trigger further actions (until a push-to-talk mode is added).

> **Note:** The MuteMe protocol documentation describes the values as single bytes. The actual HID report is 8 bytes with the relevant value at offset 3. The device also streams idle `0x00` reports at ~2 Hz when untouched.

### Verbose log format

When verbose logging is enabled, every input report is printed:

```
[MuteMe] 0x04 → startTouch  (raw: 04)
[MuteMe] 0x01 → touching    (raw: 01)
[MuteMe] 0x02 → endTouch    (raw: 02)
[MuteMe] 0x00 → clear       (raw: 00)
[MuteMe] 0xXX → unknown     (raw: XX)   ← unexpected byte from your firmware
```

Unknown bytes should be noted and may indicate firmware-specific behaviour on your batch.

## Output Reports (host → button, LED control — future)

LED control is sent as a single-byte output report. The byte is composed as:

```
LED byte = base_color | effect_modifier
```

### Base colors

| Value | Color |
|-------|-------|
| `0x00` | Off |
| `0x01` | Red |
| `0x02` | Green |
| `0x04` | Blue |
| `0x03` | Yellow (Red + Green) |
| `0x05` | Magenta (Red + Blue) |
| `0x06` | Cyan (Green + Blue) |
| `0x07` | White (Red + Green + Blue) |

### Effect modifiers (OR with base color)

| Value | Effect |
|-------|--------|
| `0x00` | Solid (no modifier) |
| `0x10` | Dim |
| `0x20` | Fast pulse |
| `0x30` | Slow pulse |

### Examples

| Byte | Result |
|------|--------|
| `0x00` | Off |
| `0x01` | Red solid |
| `0x21` | Red fast pulse |
| `0x32` | Green slow pulse |
| `0x14` | Blue dim |

### Proposed LED states (future)

| App state | Suggested LED |
|-----------|--------------|
| Connected, unmuted | Green solid (`0x02`) |
| Muted | Red solid (`0x01`) |
| No Zoom meeting | Off (`0x00`) |
| Device connecting | Blue slow pulse (`0x34`) |
| Permissions missing | Red fast pulse (`0x21`) |

## IOKit notes

- Register the input callback at the **device level** (`IOHIDDeviceRegisterInputReportCallback`), not the manager level. The manager-level callback can cause hangs on some macOS versions.
- Schedule the device on `kCFRunLoopDefaultMode`, not `kCFRunLoopCommonModes`.
- `hidapi` opens the device exclusively and blocks IOKit — do not use it in the same process or concurrently.
- The Input Monitoring TCC permission (`kIOHIDRequestTypeListenEvent`) must be explicitly requested via `IOHIDRequestAccess`. macOS does not prompt automatically.
