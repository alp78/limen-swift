import Compression
import Foundation

/// The little of ZIP the archive needs: one writer that deflates each entry, one reader that
/// walks the central directory.
///
/// Written rather than borrowed because iOS has no public ZIP API, and the archive has to be
/// read by the Android app's `java.util.zip` and read from it: Java writes entries with a data
/// descriptor after the bytes, which is why the reader trusts the central directory and never
/// the local header's sizes.
enum Zip {
    struct Entry {
        let name: String
        let method: UInt16
        let crc: UInt32
        let compressedSize: Int64
        let uncompressedSize: Int64
        let localHeaderOffset: Int64
        var isDirectory: Bool { name.hasSuffix("/") }
    }

    enum ZipError: Error, Equatable {
        case notAZip
        case truncated
        case unsupported(String)
        case badCRC(String)
        case inflateFailed(String)
    }

    // MARK: Writing

    final class Writer {
        private let handle: FileHandle
        private var entries: [(Entry, Data)] = []
        private var offset: Int64 = 0

        init(to url: URL) throws {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try FileHandle(forWritingTo: url)
        }

        /// Deflated when that saves anything, stored otherwise, which is what java.util.zip's
        /// reader accepts either way. The entry's time is the DOS epoch, as Android's `time = 0`.
        func put(_ name: String, bytes: Data) throws {
            let crc = CRC32.checksum(bytes)
            let deflated = Deflate.compress(bytes)
            let useDeflate = deflated.count < bytes.count
            let payload = useDeflate ? deflated : bytes
            let method: UInt16 = useDeflate ? 8 : 0
            let nameBytes = Data(name.utf8)
            var header = Data()
            header.appendUInt32(0x0403_4B50)
            header.appendUInt16(20)
            header.appendUInt16(0x0800) // UTF-8 names
            header.appendUInt16(method)
            header.appendUInt16(0) // time
            header.appendUInt16(0x0021) // date: 1980-01-01, the DOS epoch Java writes for time 0
            header.appendUInt32(crc)
            header.appendUInt32(UInt32(payload.count))
            header.appendUInt32(UInt32(bytes.count))
            header.appendUInt16(UInt16(nameBytes.count))
            header.appendUInt16(0)
            header.append(nameBytes)
            try handle.write(contentsOf: header)
            try handle.write(contentsOf: payload)
            let entry = Entry(name: name, method: method, crc: crc, compressedSize: Int64(payload.count), uncompressedSize: Int64(bytes.count), localHeaderOffset: offset)
            entries.append((entry, nameBytes))
            offset += Int64(header.count + payload.count)
        }

        func put(_ name: String, file: URL) throws {
            try put(name, bytes: try Data(contentsOf: file, options: .mappedIfSafe))
        }

        func finish() throws {
            let start = offset
            var central = Data()
            for (entry, nameBytes) in entries {
                central.appendUInt32(0x0201_4B50)
                central.appendUInt16(20)
                central.appendUInt16(20)
                central.appendUInt16(0x0800)
                central.appendUInt16(entry.method)
                central.appendUInt16(0)
                central.appendUInt16(0x0021)
                central.appendUInt32(entry.crc)
                central.appendUInt32(UInt32(entry.compressedSize))
                central.appendUInt32(UInt32(entry.uncompressedSize))
                central.appendUInt16(UInt16(nameBytes.count))
                central.appendUInt16(0)
                central.appendUInt16(0)
                central.appendUInt16(0)
                central.appendUInt16(0)
                central.appendUInt32(0)
                central.appendUInt32(UInt32(entry.localHeaderOffset))
                central.append(nameBytes)
            }
            var end = Data()
            end.appendUInt32(0x0605_4B50)
            end.appendUInt16(0)
            end.appendUInt16(0)
            end.appendUInt16(UInt16(entries.count))
            end.appendUInt16(UInt16(entries.count))
            end.appendUInt32(UInt32(central.count))
            end.appendUInt32(UInt32(start))
            end.appendUInt16(0)
            try handle.write(contentsOf: central)
            try handle.write(contentsOf: end)
            try handle.close()
        }
    }

    // MARK: Reading

    final class Reader {
        private let handle: FileHandle
        let entries: [Entry]

        init(_ url: URL) throws {
            handle = try FileHandle(forReadingFrom: url)
            let size = Files.size(url)
            guard size >= 22 else { throw ZipError.notAZip }
            // The end record sits in the last 64 KB, behind an optional comment.
            let tailLength = Int(min(size, 66_000))
            try handle.seek(toOffset: UInt64(size - Int64(tailLength)))
            let tail = try handle.read(upToCount: tailLength) ?? Data()
            guard let eocd = tail.lastRange(of: Data([0x50, 0x4B, 0x05, 0x06])) else { throw ZipError.notAZip }
            let record = tail.subdata(in: eocd.lowerBound..<tail.endIndex)
            guard record.count >= 22 else { throw ZipError.truncated }
            let count = Int(record.uint16(at: 10))
            let centralSize = Int(record.uint32(at: 12))
            let centralOffset = Int64(record.uint32(at: 16))
            if count == 0xFFFF || centralOffset == 0xFFFF_FFFF { throw ZipError.unsupported("zip64") }
            try handle.seek(toOffset: UInt64(centralOffset))
            let central = try handle.read(upToCount: centralSize) ?? Data()
            guard central.count == centralSize else { throw ZipError.truncated }
            var list: [Entry] = []
            var cursor = 0
            for _ in 0..<count {
                guard cursor + 46 <= central.count, central.uint32(at: cursor) == 0x0201_4B50 else { throw ZipError.truncated }
                let flags = central.uint16(at: cursor + 8)
                let method = central.uint16(at: cursor + 10)
                let crc = central.uint32(at: cursor + 16)
                let compressed = Int64(central.uint32(at: cursor + 20))
                let uncompressed = Int64(central.uint32(at: cursor + 24))
                let nameLength = Int(central.uint16(at: cursor + 28))
                let extraLength = Int(central.uint16(at: cursor + 30))
                let commentLength = Int(central.uint16(at: cursor + 32))
                let localOffset = Int64(central.uint32(at: cursor + 42))
                guard cursor + 46 + nameLength <= central.count else { throw ZipError.truncated }
                let nameData = central.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength))
                if flags & 0x0001 != 0 { throw ZipError.unsupported("encrypted entry") }
                let name = String(decoding: nameData, as: UTF8.self)
                list.append(Entry(name: name, method: method, crc: crc, compressedSize: compressed, uncompressedSize: uncompressed, localHeaderOffset: localOffset))
                cursor += 46 + nameLength + extraLength + commentLength
            }
            entries = list
        }

        /// The entry's bytes, inflated and checked against the CRC the directory carries.
        func read(_ entry: Entry) throws -> Data {
            try handle.seek(toOffset: UInt64(entry.localHeaderOffset))
            let head = try handle.read(upToCount: 30) ?? Data()
            guard head.count == 30, head.uint32(at: 0) == 0x0403_4B50 else { throw ZipError.truncated }
            let nameLength = Int(head.uint16(at: 26))
            let extraLength = Int(head.uint16(at: 28))
            try handle.seek(toOffset: UInt64(entry.localHeaderOffset + 30 + Int64(nameLength + extraLength)))
            let payload = try handle.read(upToCount: Int(entry.compressedSize)) ?? Data()
            guard Int64(payload.count) == entry.compressedSize else { throw ZipError.truncated }
            let bytes: Data
            switch entry.method {
            case 0: bytes = payload
            case 8:
                guard let inflated = Deflate.decompress(payload, expected: Int(entry.uncompressedSize)) else { throw ZipError.inflateFailed(entry.name) }
                bytes = inflated
            default: throw ZipError.unsupported("method \(entry.method)")
            }
            guard Int64(bytes.count) == entry.uncompressedSize, CRC32.checksum(bytes) == entry.crc else { throw ZipError.badCRC(entry.name) }
            return bytes
        }

        deinit { try? handle.close() }
    }
}

/// Raw DEFLATE through the Compression framework, which is what a ZIP entry holds: no zlib
/// header, no trailer, exactly what `java.util.zip.Inflater(nowrap = true)` expects.
enum Deflate {
    static func compress(_ input: Data) -> Data {
        run(input, operation: COMPRESSION_STREAM_ENCODE, capacity: max(input.count + 1024, 4096)) ?? input
    }

    static func decompress(_ input: Data, expected: Int) -> Data? {
        run(input, operation: COMPRESSION_STREAM_DECODE, capacity: max(expected, 4096))
    }

    private static func run(_ input: Data, operation: compression_stream_operation, capacity: Int) -> Data? {
        var stream = compression_stream(dst_ptr: UnsafeMutablePointer<UInt8>.allocate(capacity: 1), dst_size: 0, src_ptr: UnsafePointer<UInt8>(bitPattern: 1) ?? UnsafePointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 1)), src_size: 0, state: nil)
        guard compression_stream_init(&stream, operation, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(&stream) }
        var output = Data()
        let chunk = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { buffer.deallocate() }
        return input.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Data? in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else {
                // An empty input still has to produce a valid empty stream.
                return finish(&stream, operation: operation, buffer: buffer, chunk: chunk, output: &output)
            }
            stream.src_ptr = base
            stream.src_size = source.count
            while true {
                stream.dst_ptr = buffer
                stream.dst_size = chunk
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                output.append(buffer, count: chunk - stream.dst_size)
                switch status {
                case COMPRESSION_STATUS_OK: continue
                case COMPRESSION_STATUS_END: return output
                default: return nil
                }
            }
        }
    }

    private static func finish(_ stream: inout compression_stream, operation: compression_stream_operation, buffer: UnsafeMutablePointer<UInt8>, chunk: Int, output: inout Data) -> Data? {
        let empty = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        defer { empty.deallocate() }
        stream.src_ptr = UnsafePointer(empty)
        stream.src_size = 0
        while true {
            stream.dst_ptr = buffer
            stream.dst_size = chunk
            let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
            output.append(buffer, count: chunk - stream.dst_size)
            switch status {
            case COMPRESSION_STATUS_OK: continue
            case COMPRESSION_STATUS_END: return output
            default: return nil
            }
        }
    }
}

/// The ZIP CRC, table driven.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var c = UInt32(index)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}

extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func appendUInt32(_ value: UInt32) {
        appendUInt16(UInt16(value & 0xFFFF))
        appendUInt16(UInt16(value >> 16))
    }

    func uint16(at offset: Int) -> UInt16 {
        let i = startIndex + offset
        return UInt16(self[i]) | (UInt16(self[i + 1]) << 8)
    }

    func uint32(at offset: Int) -> UInt32 {
        UInt32(uint16(at: offset)) | (UInt32(uint16(at: offset + 2)) << 16)
    }

    func lastRange(of pattern: Data) -> Range<Int>? {
        guard count >= pattern.count else { return nil }
        var index = count - pattern.count
        while index >= 0 {
            if self[startIndex + index..<startIndex + index + pattern.count] == pattern { return index..<(index + pattern.count) }
            index -= 1
        }
        return nil
    }
}
