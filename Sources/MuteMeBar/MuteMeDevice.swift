import IOKit.hid
import os.log

private let log = Logger(subsystem: "com.muteme.bar", category: "MuteMeDevice")

// MARK: - Touch event type

enum TouchEvent {
    case startTouch   // 0x04 — leading edge, trigger mute toggle here
    case touching     // 0x01 — held, repeating
    case endTouch     // 0x02 — trailing edge
    case clear        // 0x00 — idle / reset
    case unknown(UInt8)
}

// MARK: - Known VID / PID pairs

private struct MuteMeID {
    let vendorID: Int
    let productID: Int
}

private let knownDevices: [MuteMeID] = [
    MuteMeID(vendorID: 0x3603, productID: 0x0001), // Original Batch 009+ (primary target)
    MuteMeID(vendorID: 0x3603, productID: 0x0002), // Mini USB-C
    MuteMeID(vendorID: 0x3603, productID: 0x0003), // Mini USB-A
    MuteMeID(vendorID: 0x3603, productID: 0x0004), // Mini Generic
    MuteMeID(vendorID: 0x20a0, productID: 0x42da), // Original production (Batch 001-008)
    MuteMeID(vendorID: 0x20a0, productID: 0x42db), // Mini production (Batch 001-008)
    MuteMeID(vendorID: 0x16c0, productID: 0x27db), // Prototype
]

// MARK: - MuteMeDevice

final class MuteMeDevice {

    /// Set to true to log every raw HID report; toggled from the menu.
    static var verboseLogging = false

    /// Rolling buffer of the last 200 debug log entries for "Copy Debug Log".
    private(set) static var debugLog: [String] = []
    private static let debugLogMaxEntries = 200

    /// Called on the main thread when the device successfully opens (after connect or reconnect).
    var onConnected: (() -> Void)?

    /// Called on every decoded touch event (on the main thread).
    var onEvent: ((TouchEvent) -> Void)?

    private var hidManager: IOHIDManager?
    private var openDevice: IOHIDDevice?

    // Buffer for input reports — IOKit needs a pre-allocated buffer.
    // MuteMe reports are 1 byte but we allocate a generous buffer.
    private var reportBuffer = [UInt8](repeating: 0, count: 64)

    // Last report bytes seen — used to suppress duplicate verbose log entries.
    private var lastReportBytes: [UInt8] = []

    // MARK: - Start / stop

    func start() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.hidManager = manager

        // Build a matching dictionary array covering all known VID/PID pairs.
        // IOHIDManager accepts a CFArray of matching dictionaries (OR logic).
        let matchingArray = knownDevices.map { id -> CFDictionary in
            [
                kIOHIDVendorIDKey: id.vendorID,
                kIOHIDProductIDKey: id.productID
            ] as CFDictionary
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingArray as CFArray)

        // Device connected / disconnected callbacks
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatchingCallback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemovedCallback, Unmanaged.passUnretained(self).toOpaque())

        // Schedule on the main run loop
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            log.error("IOHIDManagerOpen failed: \(result, privacy: .public)")
        } else {
            log.info("IOHIDManager opened, scanning for MuteMe devices...")
        }
    }

    func stop() {
        if let device = openDevice {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            openDevice = nil
        }
        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            hidManager = nil
        }
    }

    // MARK: - Device matching (connected)

    // fileprivate so the file-scope C callback functions can call these
    fileprivate func deviceConnected(_ device: IOHIDDevice) {
        guard openDevice == nil else {
            log.debug("Additional MuteMe device detected but one is already open; ignoring.")
            return
        }

        let vid = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString)
            .map { ($0 as? Int) ?? 0 } ?? 0
        let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString)
            .map { ($0 as? Int) ?? 0 } ?? 0
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString)
            .map { ($0 as? String) ?? "unknown" } ?? "unknown"

        let msg = "Connected: \(product) VID=0x\(String(vid, radix: 16)) PID=0x\(String(pid, radix: 16))"
        log.info("\(msg, privacy: .public)")
        Self.appendDebugLog("[MuteMe] \(msg)")

        // Open device and register input report callback at device level.
        // (Manager-level report callback can cause hangs — see 01-hid-protocol.md)
        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            log.error("IOHIDDeviceOpen failed: \(openResult, privacy: .public) — check Input Monitoring permission")
            return
        }

        openDevice = device
        onConnected?()

        // reportBuffer must remain valid for the lifetime of the callback.
        IOHIDDeviceRegisterInputReportCallback(
            device,
            &reportBuffer,
            CFIndex(reportBuffer.count),
            inputReportCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )

        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    fileprivate func deviceDisconnected(_ device: IOHIDDevice) {
        guard openDevice != nil else { return }

        log.info("Disconnected")
        Self.appendDebugLog("[MuteMe] Disconnected")

        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        openDevice = nil
    }

    // MARK: - Input report handling

    // Called from file-scope C callback; report is guaranteed non-nil by IOKit.
    // The MuteMe sends an 8-byte report; the touch byte is at index 3:
    //   idle:        00 00 00 00 00 00 00 00
    //   start touch: 00 00 00 04 00 00 00 00
    //   touching:    00 00 00 01 00 00 00 00
    //   end touch:   00 00 00 02 00 00 00 00
    fileprivate func handleInputReport(type: IOHIDReportType, reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        guard length >= 4 else { return }
        let byte = report[3]
        let event = touchEvent(from: byte)

        if Self.verboseLogging {
            // Suppress idle (all-zero) reports — the device streams them continuously.
            let allZero = (0..<min(length, 8)).allSatisfy { report[$0] == 0x00 }
            if !allZero {
                let allBytes = (0..<min(length, 8)).map {
                    String(format: "%02x", report[$0])
                }.joined(separator: " ")
                let label = eventLabel(event)
                let entry = "[MuteMe] [\(allBytes)] byte[3]=0x\(String(format: "%02x", byte)) -> \(label)"
                log.debug("\(entry, privacy: .public)")
                Self.appendDebugLog(entry)
            }
        }

        onEvent?(event)
    }

    // MARK: - LED output

    /// Send an LED control byte to the device.
    /// Byte = base_color | effect_modifier. See 01-hid-protocol.md for the full table.
    ///   0x00 = off
    ///   0x01 = red solid,   0x02 = green solid,  0x04 = blue solid
    ///   0x21 = red fast pulse, 0x32 = green slow pulse, etc.
    func setLED(byte: UInt8) {
        guard let device = openDevice else {
            log.debug("setLED: no device connected, skipping")
            return
        }
        var reportData: UInt8 = byte
        let result = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            CFIndex(0),
            &reportData,
            CFIndex(1)
        )
        if result == kIOReturnSuccess {
            log.debug("setLED(0x\(String(format: "%02x", byte), privacy: .public)) OK")
        } else {
            log.error("setLED(0x\(String(format: "%02x", byte), privacy: .public)) failed: \(result, privacy: .public)")
        }
    }

    // MARK: - Helpers

    private func touchEvent(from byte: UInt8) -> TouchEvent {
        switch byte {
        case 0x04: return .startTouch
        case 0x01: return .touching
        case 0x02: return .endTouch
        case 0x00: return .clear
        default:   return .unknown(byte)
        }
    }

    private func eventLabel(_ event: TouchEvent) -> String {
        switch event {
        case .startTouch:       return "startTouch"
        case .touching:         return "touching"
        case .endTouch:         return "endTouch"
        case .clear:            return "clear"
        case .unknown(let b):  return "unknown(0x\(String(b, radix: 16)))"
        }
    }

    static func appendDebugLog(_ entry: String) {
        debugLog.append(entry)
        if debugLog.count > debugLogMaxEntries {
            debugLog.removeFirst(debugLog.count - debugLogMaxEntries)
        }
    }
}

// MARK: - IOKit C callbacks (free functions, bridge to instance)

private func deviceMatchingCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let ctx = context else { return }
    let me = Unmanaged<MuteMeDevice>.fromOpaque(ctx).takeUnretainedValue()
    me.deviceConnected(device)
}

private func deviceRemovedCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let ctx = context else { return }
    let me = Unmanaged<MuteMeDevice>.fromOpaque(ctx).takeUnretainedValue()
    me.deviceDisconnected(device)
}

private func inputReportCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard let ctx = context else { return }
    let me = Unmanaged<MuteMeDevice>.fromOpaque(ctx).takeUnretainedValue()
    me.handleInputReport(type: type, reportID: reportID, report: report, length: reportLength)
}

// MARK: - String helpers

private extension String {
    func leftPadded(toLength length: Int, with character: Character) -> String {
        guard self.count < length else { return self }
        return String(repeating: character, count: length - self.count) + self
    }
}
