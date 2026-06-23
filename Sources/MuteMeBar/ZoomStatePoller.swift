import AppKit
import os.log

private let log = Logger(subsystem: "com.muteme.bar", category: "ZoomStatePoller")

// MARK: - Zoom mute state

enum ZoomMuteState: Equatable {
    case unmuted        // In a meeting, microphone is live
    case muted          // In a meeting, microphone is muted
    case notInMeeting   // Zoom not running, or running but no active meeting
}

// MARK: - ZoomStatePoller

/// Polls Zoom's actual mute state once per second by inspecting its Meeting
/// menu bar item via the Accessibility API (no UI interaction — read-only walk).
///
/// Logic: Zoom's menu bar contains a "Meeting" item only during an active
/// meeting. Within that menu, "Mute audio" exists when unmuted, and is absent
/// (replaced by "Unmute audio") when muted.
///
/// Requires the Accessibility permission (already granted by the app).
/// Gracefully returns .notInMeeting when Zoom is not open or not in a call.
final class ZoomStatePoller {

    /// Called on the main thread whenever the detected state changes.
    var onStateChanged: ((ZoomMuteState) -> Void)?

    private var timer: Timer?
    private var lastState: ZoomMuteState = .notInMeeting

    // MARK: - Start / stop

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        log.info("ZoomStatePoller started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        log.info("ZoomStatePoller stopped")
    }

    /// Fire a short burst of quick polls. Call right after sending a mute toggle
    /// so the icon/LED update within ~150 ms instead of waiting for the next
    /// 1 s tick. Zoom needs a brief moment to update its menu after the
    /// keystroke, so we sample a few times. poll() dedupes, so these are cheap.
    func pollBurst() {
        let delays: [TimeInterval] = [0.12, 0.25, 0.4, 0.6, 0.85]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.poll()
            }
        }
    }

    // MARK: - Poll

    private func poll() {
        let state = queryZoomState()
        guard state != lastState else { return }
        lastState = state
        log.debug("Zoom state -> \(state.logLabel, privacy: .public)")
        onStateChanged?(state)
    }

    // MARK: - AXUIElement query (read-only, no menu opening)

    private func queryZoomState() -> ZoomMuteState {
        // If Accessibility isn't actually trusted, every AX call below returns
        // nothing and we'd silently report "not in meeting". Surface that clearly.
        if !AXIsProcessTrusted() {
            log.debug("queryZoomState: Accessibility NOT trusted — cannot read Zoom")
            return .notInMeeting
        }

        // Short-circuit: Zoom not running
        guard let zoom = NSRunningApplication.runningApplications(
            withBundleIdentifier: "us.zoom.xos").first,
              !zoom.isTerminated
        else {
            log.debug("queryZoomState: Zoom (us.zoom.xos) not running")
            return .notInMeeting
        }

        let appElement = AXUIElementCreateApplication(zoom.processIdentifier)

        // 1. Get the application menu bar
        guard let menuBar = appElement.axElement(for: kAXMenuBarAttribute) else {
            log.debug("queryZoomState: no menu bar")
            return .notInMeeting
        }

        // 2. Find the "Meeting" menu bar item (only present during an active meeting)
        guard let meetingBarItem = menuBar.axChildren()?.first(where: {
            $0.axString(for: kAXTitleAttribute) == "Meeting"
        }) else {
            log.debug("queryZoomState: no 'Meeting' menu (not in a call)")
            return .notInMeeting
        }

        // 3. Get the menu attached to the "Meeting" bar item (its first child)
        //    We use kAXChildrenAttribute — this does NOT open the menu on screen.
        guard let meetingMenu = meetingBarItem.axChildren()?.first else {
            log.debug("queryZoomState: 'Meeting' item has no menu child")
            return .notInMeeting
        }

        // 4. Get the menu's items
        guard let menuItems = meetingMenu.axChildren(), !menuItems.isEmpty else {
            log.debug("queryZoomState: 'Meeting' menu has no items")
            return .notInMeeting
        }

        // 5. "Mute audio" present → unmuted; absent (replaced by "Unmute audio") → muted
        let hasMuteItem = menuItems.contains {
            $0.axString(for: kAXTitleAttribute) == "Mute audio"
        }

        return hasMuteItem ? .unmuted : .muted
    }
}

// MARK: - AXUIElement convenience extensions

private extension AXUIElement {

    /// Read an arbitrary AX attribute, returning the raw AnyObject.
    func axValue(for attribute: String) -> AnyObject? {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        return value
    }

    /// Read an attribute and cast it to AXUIElement.
    func axElement(for attribute: String) -> AXUIElement? {
        axValue(for: attribute) as! AXUIElement?
    }

    /// Read an attribute and cast it to String.
    func axString(for attribute: String) -> String? {
        axValue(for: attribute) as? String
    }

    /// Read the kAXChildrenAttribute as [AXUIElement].
    func axChildren() -> [AXUIElement]? {
        guard let raw = axValue(for: kAXChildrenAttribute) else { return nil }
        // CFArray of AXUIElement comes back as a Swift Array when bridged
        return raw as? [AXUIElement]
    }
}

// MARK: - Logging

private extension ZoomMuteState {
    var logLabel: String {
        switch self {
        case .unmuted:      return "unmuted"
        case .muted:        return "muted"
        case .notInMeeting: return "notInMeeting"
        }
    }
}
