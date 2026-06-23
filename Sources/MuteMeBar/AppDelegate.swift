import AppKit
import ServiceManagement
import os.log

private let log = Logger(subsystem: "com.muteme.bar", category: "AppDelegate")

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    private var controller: MuteController?

    // Menu items that need to be updated dynamically
    private var muteStateItem: NSMenuItem?
    private var inputMonitoringItem: NSMenuItem?
    private var accessibilityItem: NSMenuItem?
    private var verboseLoggingItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Make this a menu-bar-only accessory app with no Dock icon.
        // LSUIElement in the embedded plist handles this for .app bundles, but
        // calling setActivationPolicy explicitly ensures it works when running
        // via `swift run` (unbundled binary) as well.
        NSApp.setActivationPolicy(.accessory)

        // Request permissions before anything else so dialogs appear on launch
        PermissionsManager.shared.requestInputMonitoring()
        PermissionsManager.shared.requestAccessibility()

        setupStatusItem()

        // Start the controller after the menu exists so icon updates work
        let ctrl = MuteController()
        self.controller = ctrl
        ctrl.onStateChanged = { [weak self] state in
            self?.updateMuteIcon(state: state)
            self?.updateMuteStateItem(state: state)
        }
        ctrl.start()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        updateMuteIcon(state: .notInMeeting)
        item.button?.toolTip = "MuteMe — tap button to toggle Zoom mute"

        let menu = buildMenu()
        menu.delegate = self
        item.menu = menu
    }

    private func updateMuteIcon(state: ZoomMuteState) {
        guard let button = statusItem?.button else { return }
        switch state {
        case .muted:
            button.image = NSImage(systemSymbolName: "mic.slash.fill", accessibilityDescription: "Muted")
            button.appearsDisabled = false
        case .unmuted:
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Unmuted")
            button.appearsDisabled = false
        case .notInMeeting:
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Not in meeting")
            button.appearsDisabled = true
        }
        button.image?.isTemplate = true
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let muteState = NSMenuItem(title: "Not in meeting", action: nil, keyEquivalent: "")
        muteState.isEnabled = false
        menu.addItem(muteState)
        muteStateItem = muteState

        menu.addItem(.separator())

        let verboseItem = NSMenuItem(
            title: "Verbose Logging",
            action: #selector(toggleVerboseLogging(_:)),
            keyEquivalent: ""
        )
        verboseItem.target = self
        verboseItem.state = MuteMeDevice.verboseLogging ? .on : .off
        menu.addItem(verboseItem)
        verboseLoggingItem = verboseItem

        let copyLogItem = NSMenuItem(
            title: "Copy Debug Log",
            action: #selector(copyDebugLog(_:)),
            keyEquivalent: ""
        )
        copyLogItem.target = self
        menu.addItem(copyLogItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)
        launchAtLoginItem = loginItem

        menu.addItem(.separator())

        let inputItem = NSMenuItem(
            title: permissionTitle(label: "Input Monitoring", granted: PermissionsManager.shared.hasInputMonitoring),
            action: #selector(openInputMonitoringSettings(_:)),
            keyEquivalent: ""
        )
        inputItem.target = self
        menu.addItem(inputItem)
        inputMonitoringItem = inputItem

        let axItem = NSMenuItem(
            title: permissionTitle(label: "Accessibility", granted: PermissionsManager.shared.hasAccessibility),
            action: #selector(openAccessibilitySettings(_:)),
            keyEquivalent: ""
        )
        axItem.target = self
        menu.addItem(axItem)
        accessibilityItem = axItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit MuteMe Bar",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        return menu
    }

    // Called each time the menu is about to open, so dynamic items stay current
    func menuWillOpen(_ menu: NSMenu) {
        let hasIM = PermissionsManager.shared.hasInputMonitoring
        let hasAX = PermissionsManager.shared.hasAccessibility
        inputMonitoringItem?.title = permissionTitle(label: "Input Monitoring", granted: hasIM)
        accessibilityItem?.title = permissionTitle(label: "Accessibility", granted: hasAX)
        launchAtLoginItem?.state = isLaunchAtLoginEnabled ? .on : .off
    }

    private func permissionTitle(label: String, granted: Bool) -> String {
        granted ? "\(label): ✓" : "\(label): ✗ (click to fix)"
    }

    private func updateMuteStateItem(state: ZoomMuteState) {
        switch state {
        case .muted:        muteStateItem?.title = "Status: Muted"
        case .unmuted:      muteStateItem?.title = "Status: Unmuted"
        case .notInMeeting: muteStateItem?.title = "Not in meeting"
        }
    }

    // MARK: - Menu actions

    @objc private func toggleVerboseLogging(_ sender: NSMenuItem) {
        MuteMeDevice.verboseLogging.toggle()
        sender.state = MuteMeDevice.verboseLogging ? .on : .off
        log.info("Verbose logging: \(MuteMeDevice.verboseLogging)")
    }

    @objc private func copyDebugLog(_ sender: Any) {
        let text = MuteMeDevice.debugLog.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text.isEmpty ? "(no events recorded)" : text, forType: .string)
    }

    @objc private func openInputMonitoringSettings(_ sender: Any) {
        if !PermissionsManager.shared.hasInputMonitoring {
            PermissionsManager.shared.openInputMonitoringSettings()
        }
    }

    @objc private func openAccessibilitySettings(_ sender: Any) {
        if !PermissionsManager.shared.hasAccessibility {
            PermissionsManager.shared.openAccessibilitySettings()
        }
    }

    // MARK: - Launch at Login

    private var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if isLaunchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
                log.info("Launch at login disabled")
            } else {
                try SMAppService.mainApp.register()
                log.info("Launch at login enabled")
            }
        } catch {
            log.error("Failed to toggle launch at login: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "macOS reported: \(error.localizedDescription)\n\nThis requires running the app from a fixed location (the .app bundle), not via 'swift run'."
            alert.alertStyle = .warning
            alert.runModal()
        }
        sender.state = isLaunchAtLoginEnabled ? .on : .off
    }
}
