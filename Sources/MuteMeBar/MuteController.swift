import Foundation
import os.log

private let log = Logger(subsystem: "com.muteme.bar", category: "MuteController")

/// Wires MuteMeDevice touch events to Zoom mute toggles, and keeps the
/// menu-bar icon in sync with Zoom's actual mute state via ZoomStatePoller.
final class MuteController {

    /// Called on the main thread whenever the Zoom mute state changes.
    var onStateChanged: ((ZoomMuteState) -> Void)?

    private(set) var zoomState: ZoomMuteState = .notInMeeting

    private let device = MuteMeDevice()
    private let poller = ZoomStatePoller()

    func start() {
        // Wire HID events
        device.onEvent = { [weak self] event in
            self?.handleEvent(event)
        }
        device.start()

        // When the HID device connects, immediately sync the LED to current state
        device.onConnected = { [weak self] in
            guard let self else { return }
            self.updateLED(for: self.zoomState)
        }

        // Wire Zoom state changes from the poller
        poller.onStateChanged = { [weak self] state in
            self?.handleZoomStateChange(state)
        }
        poller.start()

        log.info("MuteController started")
    }

    func stop() {
        device.stop()
        poller.stop()
        log.info("MuteController stopped")
    }

    // MARK: - HID event handling

    private func handleEvent(_ event: TouchEvent) {
        switch event {
        case .startTouch:
            sendToggle()
        case .touching, .endTouch, .clear:
            break
        case .unknown(let byte):
            let hex = String(byte, radix: 16)
            log.warning("Unexpected HID byte: 0x\(hex, privacy: .public)")
            MuteMeDevice.appendDebugLog("[MuteMe] WARN unexpected byte 0x\(hex)")
        }
    }

    /// Send the toggle keystroke. The icon update follows on the next poller
    /// tick (~1 s) once Zoom confirms the new state. No optimistic flip needed.
    private func sendToggle() {
        log.info("Button pressed — sending Cmd+Shift+A")
        MuteMeDevice.appendDebugLog("[MuteMe] Button pressed -> sending toggle")
        KeySender.toggleZoomMute()
        // Quick feedback: poll Zoom rapidly so the icon/LED flip in ~150 ms
        // rather than waiting for the next 1 s tick.
        poller.pollBurst()
    }

    // MARK: - Zoom state sync

    private func handleZoomStateChange(_ state: ZoomMuteState) {
        zoomState = state
        let label: String
        switch state {
        case .muted:        label = "muted"
        case .unmuted:      label = "unmuted"
        case .notInMeeting: label = "not in meeting"
        }
        log.info("Zoom state: \(label, privacy: .public)")
        MuteMeDevice.appendDebugLog("[MuteMe] Zoom state: \(label)")
        updateLED(for: state)
        onStateChanged?(state)
    }

    // MARK: - LED control

    private func updateLED(for state: ZoomMuteState) {
        switch state {
        case .notInMeeting: device.setLED(byte: 0x00) // off
        case .unmuted:      device.setLED(byte: 0x02) // green solid
        case .muted:        device.setLED(byte: 0x01) // red solid
        }
    }
}
