// Device identifiers and feature-report decoding adapted from LidAngleSensor.
// Copyright 2026 Sam Gold. Apache-2.0; see NOTICE and Licenses/LidAngleSensor.txt.
import Foundation
import IOKit.hid
#if SWIFT_PACKAGE
import DuoFXCore
#endif

@MainActor
final class HIDAngleSensor {
    private(set) var isAvailable = false
    var onReading: ((Double) -> Void)?
    var onDiagnostic: ((SensorDiagnostic) -> Void)?
    // All HID handles, discovery, reads and teardown belong to this queue.
    private let worker = HIDWorker()
    private var generation = 0

    func start() {
        generation += 1
        let token = generation
        worker.start { [weak self] reading, diagnostic in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if let diagnostic {
                    self.isAvailable = diagnostic.isAvailable
                    self.onDiagnostic?(diagnostic)
                }
                if let reading {
                    self.onReading?(reading)
                }
            }
        }
    }

    func stop() { generation += 1; isAvailable = false; worker.stop() }
    deinit { worker.stop() }
}

private final class HIDWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.duofx.sensor", qos: .userInteractive)
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var timer: DispatchSourceTimer?
    private var failures = 0
    private var report = [UInt8](repeating: 0, count: 8)
    private var reportDetail = ""
    private let options = IOOptionBits(kIOHIDOptionsTypeNone)

    func start(_ callback: @escaping @Sendable (Double?, SensorDiagnostic?) -> Void) {
        queue.async { [self] in
            close()
            var diagnostic = SensorDiagnostic()
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, options)
            self.manager = manager
            IOHIDManagerSetDeviceMatching(manager, [
                kIOHIDVendorIDKey: 0x05ac, kIOHIDProductIDKey: 0x8104
            ] as CFDictionary)
            let result = IOHIDManagerOpen(manager, options)
            guard result == kIOReturnSuccess else {
                diagnostic.message = "HID discovery failed (\(result)). Manual preview is available."
                close(); callback(nil, diagnostic); return
            }
            let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
            diagnostic.message = devices.isEmpty
                ? "No supported lid sensor found. Use Manual preview on this Mac."
                : "Sensor found on an unsupported HID interface. Use Manual preview."
            for candidate in devices {
                func property(_ key: String) -> Int? {
                    (IOHIDDeviceGetProperty(candidate, key as CFString) as? NSNumber)?.intValue
                }
                guard property(kIOHIDVendorIDKey) == 0x05ac,
                      property(kIOHIDProductIDKey) == 0x8104,
                      property(kIOHIDPrimaryUsagePageKey) == 0x20,
                      property(kIOHIDPrimaryUsageKey) == 0x8a else { continue }
                // Mac16,8 advertises a one-byte maximum but returns the angle in a
                // longer feature report. Descriptor size is diagnostic only; validate
                // the actual report length, ID and value before accepting a reading.
                if let maxSize = property(kIOHIDMaxFeatureReportSizeKey) {
                    diagnostic.properties += " · declared feature bytes: \(maxSize)"
                }
                let opened = IOHIDDeviceOpen(candidate, options)
                guard opened == kIOReturnSuccess else {
                    diagnostic.message = "Cannot open lid sensor (\(opened)). Close other sensor utilities and retry."
                    continue
                }
                device = candidate
                guard let first = read() else {
                    diagnostic.message = "Sensor report is unreadable or has an unsupported layout (\(reportDetail)). Use Manual preview."
                    IOHIDDeviceClose(candidate, options); device = nil; continue
                }
                diagnostic.isAvailable = true
                diagnostic.properties += " · \(reportDetail)"
                diagnostic.message = "Lid sensor connected."
                callback(first, diagnostic)
                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(deadline: .now(), repeating: 1.0 / 60, leeway: .milliseconds(2))
                timer.setEventHandler { [weak self] in
                    guard let self else { return }
                    if let value = self.read() { self.failures = 0; callback(value, nil) }
                    else {
                        self.failures += 1
                        if self.failures >= 5 {
                            var failed = SensorDiagnostic()
                            failed.message = "Lid sensor stopped responding. Effect paused; retry or use Manual preview."
                            self.close(); callback(nil, failed)
                        }
                    }
                }
                self.timer = timer; timer.resume()
                return
            }
            close(); callback(nil, diagnostic)
        }
    }

    func stop() { queue.async { [self] in close() } }

    private func read() -> Double? {
        guard let device else { return nil }
        var size = CFIndex(report.count)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &size)
        reportDetail = "result: \(result), bytes: \(size), report ID: \(report[0])"
        guard result == kIOReturnSuccess, (3...8).contains(size) else { return nil }
        return LidReport.decode(Array(report.prefix(size)))
    }

    private func close() {
        timer?.cancel(); timer = nil
        if let device { IOHIDDeviceClose(device, options) }
        device = nil
        if let manager { IOHIDManagerClose(manager, options) }
        manager = nil; failures = 0
    }
}
