import AppKit
import IOKit.hid
import ApplicationServices
import os.log

private let log = Logger(subsystem: "com.muteme.bar", category: "PermissionsManager")

/// Manages macOS TCC permissions needed by the app:
///   - Input Monitoring — to open and read the MuteMe HID device
///   - Accessibility    — to post synthetic CGEvent keystrokes to Zoom
final class PermissionsManager {

    static let shared = PermissionsManager()
    private init() {}

    // MARK: - Status checks

    var hasInputMonitoring: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    // MARK: - Requests (prompt on first launch)

    /// Triggers the macOS Input Monitoring permission prompt if not yet decided.
    /// If the user previously denied it, this is a no-op — direct them to System Settings instead.
    func requestInputMonitoring() {
        let status = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        switch status {
        case kIOHIDAccessTypeGranted:
            log.info("Input Monitoring: already granted")
        case kIOHIDAccessTypeUnknown:
            log.info("Input Monitoring: requesting access…")
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        case kIOHIDAccessTypeDenied:
            log.warning("Input Monitoring: denied — user must grant in System Settings")
        default:
            log.warning("Input Monitoring: unknown status \(status.rawValue, privacy: .public)")
        }
    }

    /// Triggers the macOS Accessibility permission prompt if not yet decided.
    func requestAccessibility() {
        if AXIsProcessTrusted() {
            log.info("Accessibility: already granted")
        } else {
            log.info("Accessibility: requesting access…")
            // Passing prompt:true shows the system dialog
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }

    // MARK: - Deep links to System Settings

    func openInputMonitoringSettings() {
        openPrivacyPane(section: "ListenEvent")
    }

    func openAccessibilitySettings() {
        openPrivacyPane(section: "Accessibility")
    }

    private func openPrivacyPane(section: String) {
        // macOS 13+ uses x-apple.systempreferences scheme
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(section)") {
            NSWorkspace.shared.open(url)
        }
    }
}
