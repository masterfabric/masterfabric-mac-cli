import Foundation
import IOKit

/// AppleSMC client. Param struct layout matches SMCKit (80 bytes).
public final class SMCClient: @unchecked Sendable {
    public enum SMCError: Error, LocalizedError {
        case serviceNotFound
        case openFailed
        case readFailed(String)
        case writeFailed(String, UInt8)
        /// macOS blocked the SMC write (`kIOReturnNotPrivileged`). Needs `sudo` / admin elevation.
        case notPrivileged(String)

        public var errorDescription: String? {
            switch self {
            case .serviceNotFound: return "AppleSMC service not found"
            case .openFailed: return "Failed to open AppleSMC connection"
            case .readFailed(let key): return "Failed to read SMC key \(key)"
            case .writeFailed(let key, let code): return "Failed to write SMC key \(key) (result=\(code))"
            case .notPrivileged(let key):
                return "SMC write denied for \(key) (administrator privileges required — try: sudo mf fan …)"
            }
        }
    }

    /// `kIOReturnNotPrivileged` — user client write blocked without root.
    private static let ioReturnNotPrivileged: kern_return_t = kern_return_t(bitPattern: 0xE000_02C1)

    private var connection: io_connect_t = 0

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
            throw SMCError.openFailed
        }
        connection = conn
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    public func readNumber(_ key: String) -> Double? {
        guard let raw = try? readRaw(key) else { return nil }
        return decode(raw)
    }

    /// Enumerate SMC four-char keys (for discovering temperature sensors per SoC).
    public func allKeys() -> [String] {
        guard let count = keyCount() else { return [] }
        var names: [String] = []
        names.reserveCapacity(count)
        for i in 0..<count {
            if let name = keyName(at: i) {
                names.append(name)
            }
        }
        return names
    }

    private func keyCount() -> Int? {
        guard let n = readNumber("#KEY") else { return nil }
        return Int(n)
    }

    private func keyName(at index: Int) -> String? {
        var input = SMCParamStruct()
        input.data8 = SMCParamStruct.Selector.getKeyFromIndex.rawValue
        input.data32 = UInt32(index)
        var output = SMCParamStruct()
        do {
            try invoke(&input, &output)
        } catch {
            return nil
        }
        guard output.result == SMCParamStruct.Result.success.rawValue else { return nil }
        return FourChar.toString(output.key).trimmingCharacters(in: .whitespaces)
    }

    public func readUInt8(_ key: String) -> UInt8? {
        guard let raw = try? readRaw(key), !raw.bytes.isEmpty else { return nil }
        return raw.bytes[0]
    }

    /// Returns key data type string if the key exists (e.g. `ui8`, `flt`, `fpe2`).
    public func keyType(_ key: String) -> String? {
        guard let raw = try? readRaw(key) else { return nil }
        return raw.dataType.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
    }

    public func writeUInt8(_ key: String, _ value: UInt8) throws {
        try writeBytes(key, [value])
    }

    public func writeNumber(_ key: String, _ value: Double) throws {
        let type = try keyTypeRequired(key)
        let bytes: [UInt8]
        switch type {
        case "ui8", "ui8 ":
            bytes = [UInt8(clamping: Int(value.rounded()))]
        case "ui16":
            let v = UInt16(clamping: Int(value.rounded()))
            bytes = [UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
        case "fpe2":
            let v = Int(value.rounded())
            bytes = [UInt8((v >> 6) & 0xFF), UInt8((v << 2) & 0xFF)]
        case "flt", "flt ":
            var f = Float(value)
            bytes = withUnsafeBytes(of: &f) { Array($0) }
        default:
            // Prefer float payload for unknown 4-byte targets (common for F*Tg on AS).
            var f = Float(value)
            bytes = withUnsafeBytes(of: &f) { Array($0) }
        }
        try writeBytes(key, bytes)
    }

    // MARK: - Private

    private struct RawValue {
        var dataType: String
        var bytes: [UInt8]
    }

    private func readRaw(_ key: String) throws -> RawValue {
        var input = SMCParamStruct()
        input.key = FourChar.from(key)
        input.data8 = SMCParamStruct.Selector.getKeyInfo.rawValue

        var output = SMCParamStruct()
        try invoke(&input, &output)
        guard output.result == SMCParamStruct.Result.success.rawValue else {
            throw SMCError.readFailed(key)
        }

        var readIn = SMCParamStruct()
        readIn.key = FourChar.from(key)
        readIn.keyInfo.dataSize = output.keyInfo.dataSize
        readIn.data8 = SMCParamStruct.Selector.readKey.rawValue

        var readOut = SMCParamStruct()
        try invoke(&readIn, &readOut)
        guard readOut.result == SMCParamStruct.Result.success.rawValue else {
            throw SMCError.readFailed(key)
        }

        let size = Int(min(output.keyInfo.dataSize, 32))
        let bytes: [UInt8] = withUnsafeBytes(of: readOut.bytes) { Array($0.prefix(size)) }
        return RawValue(
            dataType: FourChar.toString(output.keyInfo.dataType),
            bytes: bytes
        )
    }

    private func keyTypeRequired(_ key: String) throws -> String {
        var input = SMCParamStruct()
        input.key = FourChar.from(key)
        input.data8 = SMCParamStruct.Selector.getKeyInfo.rawValue
        var output = SMCParamStruct()
        try invoke(&input, &output)
        guard output.result == SMCParamStruct.Result.success.rawValue else {
            throw SMCError.readFailed(key)
        }
        return FourChar.toString(output.keyInfo.dataType)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
    }

    private func writeBytes(_ key: String, _ bytes: [UInt8]) throws {
        var infoIn = SMCParamStruct()
        infoIn.key = FourChar.from(key)
        infoIn.data8 = SMCParamStruct.Selector.getKeyInfo.rawValue
        var infoOut = SMCParamStruct()
        try invoke(&infoIn, &infoOut)
        guard infoOut.result == SMCParamStruct.Result.success.rawValue else {
            throw SMCError.writeFailed(key, infoOut.result)
        }

        let size = Int(min(infoOut.keyInfo.dataSize, 32))
        guard size > 0 else { throw SMCError.writeFailed(key, infoOut.result) }

        var writeIn = SMCParamStruct()
        writeIn.key = FourChar.from(key)
        writeIn.keyInfo.dataSize = infoOut.keyInfo.dataSize
        writeIn.data8 = SMCParamStruct.Selector.writeKey.rawValue
        withUnsafeMutableBytes(of: &writeIn.bytes) { dest in
            for i in 0..<size {
                dest[i] = i < bytes.count ? bytes[i] : 0
            }
        }

        var writeOut = SMCParamStruct()
        try invoke(&writeIn, &writeOut)
        guard writeOut.result == SMCParamStruct.Result.success.rawValue else {
            throw SMCError.writeFailed(key, writeOut.result)
        }
    }

    private func invoke(_ input: inout SMCParamStruct, _ output: inout SMCParamStruct) throws {
        assert(MemoryLayout<SMCParamStruct>.stride == 80, "SMCParamStruct must be 80 bytes")
        let inSize = MemoryLayout<SMCParamStruct>.stride
        var outSize = MemoryLayout<SMCParamStruct>.stride
        let kr = IOConnectCallStructMethod(connection, 2, &input, inSize, &output, &outSize)
        guard kr == KERN_SUCCESS else {
            let key = FourChar.toString(input.key)
            let writing = input.data8 == SMCParamStruct.Selector.writeKey.rawValue
            if writing, kr == Self.ioReturnNotPrivileged {
                throw SMCError.notPrivileged(key)
            }
            if writing {
                throw SMCError.writeFailed(key, UInt8(truncatingIfNeeded: kr))
            }
            throw SMCError.readFailed(key)
        }
    }

    private func decode(_ raw: RawValue) -> Double? {
        let t = raw.dataType.trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
        let b = raw.bytes
        guard !b.isEmpty else { return nil }

        switch t {
        case "sp78":
            guard b.count >= 2 else { return nil }
            let v = Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))
            return Double(v) / 256.0
        case "fpe2":
            guard b.count >= 2 else { return nil }
            // SMCKit: (Int(b0) << 6) + (Int(b1) >> 2)
            return Double((Int(b[0]) << 6) + (Int(b[1]) >> 2))
        case "flt", "flt ":
            guard b.count >= 4 else { return nil }
            var f: Float = 0
            withUnsafeMutableBytes(of: &f) { dest in
                for i in 0..<4 { dest[i] = b[i] }
            }
            return Double(f)
        case "ui8", "ui8 ":
            return Double(b[0])
        case "ui16":
            guard b.count >= 2 else { return nil }
            return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        case "ui32":
            guard b.count >= 4 else { return nil }
            let v = UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
            return Double(v)
        default:
            if (t.hasPrefix("sp") || t.hasPrefix("fp")), b.count >= 2 {
                let v = Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))
                let frac = Int(String(t.suffix(1)), radix: 16) ?? 8
                return Double(v) / pow(2.0, Double(frac))
            }
            if b.count >= 4 {
                var f: Float = 0
                withUnsafeMutableBytes(of: &f) { dest in
                    for i in 0..<4 { dest[i] = b[i] }
                }
                if f.isFinite, abs(f) < 1e6 { return Double(f) }
            }
            return nil
        }
    }
}

/// Must be exactly 80 bytes (see SMCKit / Apple PowerManagement-211).
private struct SMCParamStruct {
    enum Selector: UInt8 {
        case readKey = 5
        case writeKey = 6
        case getKeyFromIndex = 8
        case getKeyInfo = 9
    }

    enum Result: UInt8 {
        case success = 0
        case error = 1
        case keyNotFound = 132
    }

    struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct SMCKeyInfoData {
        /// Use UInt32 (not IOByteCount) to keep struct at 80 bytes.
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    /// Padding for C struct alignment
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

private enum FourChar {
    static func from(_ string: String) -> UInt32 {
        let chars = Array(string.utf8.prefix(4))
        var result: UInt32 = 0
        for i in 0..<4 {
            let byte: UInt8 = i < chars.count ? chars[i] : 32
            result = (result << 8) | UInt32(byte)
        }
        return result
    }

    static func toString(_ code: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF),
        ]
        return String(bytes.map { Character(UnicodeScalar($0)) })
    }
}
