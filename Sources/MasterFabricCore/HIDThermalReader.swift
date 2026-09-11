import CoreFoundation
import Foundation
import IOKit

/// Apple Silicon thermal sensors via IOHIDEventSystemClient + matching dictionary.
enum HIDThermalReader {
    static func readSensors() -> [String: Double] {
        var results: [String: Double] = [:]

        guard let client = createClient() else { return results }

        // Match temperature HID events (Apple Silicon)
        let matching: [String: Any] = [
            "PrimaryUsagePage": 0xFF00,
            "PrimaryUsage": 5,
        ]
        setMatching(client, matching as CFDictionary)

        guard let services = copyServices(client) else {
            // Broad fallback without matching filter
            return readAllTemperatureEvents(client: client)
        }

        let count = CFArrayGetCount(services)
        for i in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(services, i) else { continue }
            let service = Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
            if let (name, value) = temperature(from: service) {
                results[name] = value
            }
        }

        if results.isEmpty {
            results.merge(readAllTemperatureEvents(client: client)) { a, b in max(a, b) }
        }

        return results
    }

    private static func readAllTemperatureEvents(client: UnsafeMutableRawPointer) -> [String: Double] {
        var results: [String: Double] = [:]
        guard let services = copyServices(client) else { return results }
        let count = CFArrayGetCount(services)
        for i in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(services, i) else { continue }
            let service = Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
            if let (name, value) = temperature(from: service) {
                results[name] = value
            }
        }
        return results
    }

    private static func temperature(from service: AnyObject) -> (String, Double)? {
        guard let event = copyEvent(service, type: 15) else { return nil }
        let value = floatValue(event, field: 15 << 16)
        guard value.isFinite, value >= 25, value < 150 else { return nil }

        let product = (copyProperty(service, "Product") as? String)
            ?? (copyProperty(service, "ProductName") as? String)
            ?? "sensor"
        let usage = (copyProperty(service, "PrimaryUsage") as? NSNumber)?.intValue ?? 0
        return ("\(product)#\(usage)", value)
    }

    // MARK: - dlsym IOHID SPI

    private static func createClient() -> UnsafeMutableRawPointer? {
        call("IOHIDEventSystemClientCreateSimpleClient", as: (@convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?).self)?(kCFAllocatorDefault)
    }

    private static func setMatching(_ client: UnsafeMutableRawPointer, _ matching: CFDictionary) {
        typealias Fn = @convention(c) (UnsafeMutableRawPointer, CFDictionary) -> Void
        call("IOHIDEventSystemClientSetMatching", as: Fn.self)?(client, matching)
    }

    private static func copyServices(_ client: UnsafeMutableRawPointer) -> CFArray? {
        typealias Fn = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFArray>?
        return call("IOHIDEventSystemClientCopyServices", as: Fn.self)?(client)?.takeRetainedValue()
    }

    private static func copyEvent(_ service: AnyObject, type: Int64) -> UnsafeMutableRawPointer? {
        typealias Fn = @convention(c) (UnsafeMutableRawPointer, Int64, Int32, Int32) -> UnsafeMutableRawPointer?
        return call("IOHIDServiceClientCopyEvent", as: Fn.self)?(
            Unmanaged.passUnretained(service).toOpaque(),
            type,
            0,
            0
        )
    }

    private static func floatValue(_ event: UnsafeMutableRawPointer, field: Int32) -> Double {
        typealias Fn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Double
        return call("IOHIDEventGetFloatValue", as: Fn.self)?(event, field) ?? .nan
    }

    private static func copyProperty(_ service: AnyObject, _ key: String) -> AnyObject? {
        typealias Fn = @convention(c) (UnsafeMutableRawPointer, CFString) -> Unmanaged<AnyObject>?
        return call("IOHIDServiceClientCopyProperty", as: Fn.self)?(
            Unmanaged.passUnretained(service).toOpaque(),
            key as CFString
        )?.takeRetainedValue()
    }

    private static func call<T>(_ name: String, as: T.Type) -> T? {
        let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        guard handle != nil, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }
}
