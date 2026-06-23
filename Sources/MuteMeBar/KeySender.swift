import CoreGraphics
import os.log

private let log = Logger(subsystem: "com.muteme.bar", category: "KeySender")

/// Posts a synthetic Cmd+Shift+A keystroke to the system event stream.
/// Zoom must have "Enable Global Shortcut" checked for Mute/Unmute My Audio
/// in Zoom → Settings → Keyboard Shortcuts for this to work when Zoom is not focused.
enum KeySender {

    // Virtual key code for 'A' on a US keyboard layout.
    // This is a hardware-level keycode and is layout-independent for standard keys.
    private static let keyCodeA: CGKeyCode = 0x00

    static func toggleZoomMute() {
        let flags: CGEventFlags = [.maskCommand, .maskShift]

        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCodeA, keyDown: true),
            let keyUp   = CGEvent(keyboardEventSource: nil, virtualKey: keyCodeA, keyDown: false)
        else {
            log.error("Failed to create CGEvent for Cmd+Shift+A")
            return
        }

        keyDown.flags = flags
        keyUp.flags   = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        log.debug("Posted Cmd+Shift+A (toggle Zoom mute)")
    }
}
