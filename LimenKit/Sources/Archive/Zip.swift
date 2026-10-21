import Compression
import Foundation

/// The little of ZIP the archive needs: one writer that deflates or stores each entry, one reader
/// that walks the central directory. Both stream: an entry passes through in 256 KiB pieces, so a
/// backup of a phone's photographs never holds a photograph in memory, let alone the archive.
///
/// Written rather than borrowed because iOS has no public ZIP API, and the archive has to be read
/// by the Android app's `java.util.zip` and read from it: Java writes entries with a data
/// descriptor after the bytes, which is why the reader trusts the central directory and never the
/// local header's sizes, and Java switches to ZIP64 records past 4 GiB or 65,535 entries, which is
/// why both sides here write and read them wherever a size, offset or count needs them, and only
/// there, so a smaller archive stays byte-compatible with what 1.2.4 and earlier read.
enum Zip {
    struct Entry {
        let name: String
        let method: UInt16
        let crc: UInt32
        let compressedSize: Int64
        let uncompressedSize: Int64
        let localHeaderOffset: Int64
        var flags: UInt16 = 0x0800
        var isDirectory: Bool { name.hasSuffix("/") }
    }

    enum ZipError: Error, Equatable {
        case notAZip
        case truncated
        case unsupported(String)
        case badCRC(String)
        case inflateFailed(String)
    }

    static let chunk = 256 * 1024
    private static let marker32: UInt32 = 0xFFFF_FFFF
    private static let marker16: UInt16 = 0xFFFF

    // MARK: Writing

    final class Writer {
        private let handle: FileHandle
        private var entries: [(Entry, Data)] = []
        private var offset: Int64 = 0
        /// The value past which a size, an offset or a count needs a ZIP64 field. The classic
        /// limit, except in the test that lowers it to prove the records on a small archive.
        private let zip64Threshold: Int64

        init(to url: URL, zip64Threshold: Int64 = Int64(UInt32.max)) throws {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try FileHandle(forWritingTo: url)
            self.zip64Threshold = zip64Threshold
        }

        /// Already compressed inside, so stored rather than deflated a second time for nothing:
        /// photographs are nearly all of a backup, and a repacked one is JPEG XL.
        static func stores(_ name: String) -> Bool {
            name.hasPrefix("jpegxl/") || [".jpg", ".jpeg", ".png", ".heic", ".heif"].contains { name.lowercased().hasSuffix($0) }
        }

        func put(_ name: String, bytes: Data, stored: Bool? = nil) throws {
            var cursor = bytes.startIndex
            try put(name, size: Int64(bytes.count), stored: stored ?? Self.stores(name)) {
                guard cursor < bytes.endIndex else { return nil }
                let end = min(cursor + Zip.chunk, bytes.endIndex)
                defer { cursor = end }
                return bytes[cursor..<end]
            }
        }

        func put(_ name: String, file: URL, stored: Bool? = nil) throws {
            guard Files.isRegularFile(file) else { throw ArchiveError.invalidEntry(name) }
            let input = try FileHandle(forReadingFrom: file)
            defer { try? input.close() }
            try put(name, size: Files.size(file), stored: stored ?? Self.stores(name)) {
                let piece = try input.read(upToCount: Zip.chunk) ?? Data()
                return piece.isEmpty ? nil : piece
            }
        }

        /// One entry, its bytes pulled from `next` until it returns nil. The local header is
        /// written with the CRC and the sizes blank and patched once the bytes have passed, which
        /// keeps the file free of data descriptors: Java's `ZipInputStream` refuses a stored entry
        /// that carries one. The entry's time is the DOS epoch, as Android's `time = 0`.
        private func put(_ name: String, size declared: Int64, stored: Bool, next: () throws -> Data?) throws {
            let nameBytes = Data(name.utf8)
            guard nameBytes.count <= Int(UInt16.max) else { throw ArchiveError.invalidEntry(name) }
            let method: UInt16 = stored ? 0 : 8
            // Sizes past the threshold go into a ZIP64 extra field; the declared size decides
            // it ahead of the bytes, and a deflated entry can only come out larger by a hair.
            let wide = declared >= zip64Threshold || offset >= zip64Threshold
            var header = Data()
            header.appendUInt32(0x0403_4B50)
            header.appendUInt16(wide ? 45 : 20)
            header.appendUInt16(0x0800) // UTF-8 names
            header.appendUInt16(method)
            header.appendUInt16(0) // time
            header.appendUInt16(0x0021) // date: 1980-01-01, the DOS epoch Java writes for time 0
            header.appendUInt32(0) // crc, patched below
            header.appendUInt32(wide ? marker32 : 0) // compressed size, patched below
            header.appendUInt32(wide ? marker32 : 0) // uncompressed size, patched below
            header.appendUInt16(UInt16(nameBytes.count))
            header.appendUInt16(wide ? 20 : 0)
            header.append(nameBytes)
            if wide {
                header.appendUInt16(0x0001)
                header.appendUInt16(16)
                header.appendUInt64(0) // uncompressed, patched below
                header.appendUInt64(0) // compressed, patched below
            }
            let headerOffset = offset
            try handle.write(contentsOf: header)
            offset += Int64(header.count)
            var crc = CRC32.Running()
            var raw: Int64 = 0
            var written: Int64 = 0
            let deflater = stored ? nil : try Deflate.Encoder()
            // A pool per piece: FileHandle hands back autoreleased buffers, and a backup written
            // in one synchronous call on the main actor drains nothing until it returns, so
            // without this a 100 MB record held its whole size in dead chunks by the end.
            while try autoreleasepool(invoking: { () throws -> Bool in
                guard let piece = try next() else { return false }
                crc.update(piece)
                raw += Int64(piece.count)
                let out = try deflater?.push(piece) ?? piece
                try handle.write(contentsOf: out)
                written += Int64(out.count)
                return true
            }) {}
            if let deflater {
                let tail = try deflater.finish()
                try handle.write(contentsOf: tail)
                written += Int64(tail.count)
            }
            offset += written
            guard raw == declared else { throw ArchiveError.invalidEntry(name) }
            guard wide || (written < zip64Threshold && raw < zip64Threshold) else { throw ZipError.unsupported("zip64 size on a classic header") }
            // The patch: CRC and sizes into the header already on disk.
            var patch = Data()
            patch.appendUInt32(crc.value)
            patch.appendUInt32(wide ? marker32 : UInt32(written))
            patch.appendUInt32(wide ? marker32 : UInt32(raw))
            try handle.seek(toOffset: UInt64(headerOffset + 14))
            try handle.write(contentsOf: patch)
            if wide {
                var sizes = Data()
                sizes.appendUInt64(UInt64(raw))
                sizes.appendUInt64(UInt64(written))
                try handle.seek(toOffset: UInt64(headerOffset + 30 + Int64(nameBytes.count) + 4))
                try handle.write(contentsOf: sizes)
            }
            try handle.seek(toOffset: UInt64(offset))
            entries.append((Entry(name: name, method: method, crc: crc.value, compressedSize: written, uncompressedSize: raw, localHeaderOffset: headerOffset), nameBytes))
        }

        func finish() throws {
            let start = offset
            var central = Data()
            for (entry, nameBytes) in entries {
                let wideSizes = entry.uncompressedSize >= zip64Threshold || entry.compressedSize >= zip64Threshold
                let wideOffset = entry.localHeaderOffset >= zip64Threshold
                var extra = Data()
                if wideSizes {
                    extra.appendUInt64(UInt64(entry.uncompressedSize))
                    extra.appendUInt64(UInt64(entry.compressedSize))
                }
                if wideOffset { extra.appendUInt64(UInt64(entry.localHeaderOffset)) }
                central.appendUInt32(0x0201_4B50)
                central.appendUInt16(extra.isEmpty ? 20 : 45)
                central.appendUInt16(extra.isEmpty ? 20 : 45)
                central.appendUInt16(0x0800)
                central.appendUInt16(entry.method)
                central.appendUInt16(0)
                central.appendUInt16(0x0021)
                central.appendUInt32(entry.crc)
                central.appendUInt32(wideSizes ? marker32 : UInt32(entry.compressedSize))
                central.appendUInt32(wideSizes ? marker32 : UInt32(entry.uncompressedSize))
                central.appendUInt16(UInt16(nameBytes.count))
                central.appendUInt16(extra.isEmpty ? 0 : UInt16(extra.count + 4))
                central.appendUInt16(0)
                central.appendUInt16(0)
                central.appendUInt16(0)
                central.appendUInt32(0)
                central.appendUInt32(wideOffset ? marker32 : UInt32(entry.localHeaderOffset))
                central.append(nameBytes)
                if !extra.isEmpty {
                    central.appendUInt16(0x0001)
                    central.appendUInt16(UInt16(extra.count))
                    central.append(extra)
                }
            }
            try handle.write(contentsOf: central)
            let count = Int64(entries.count)
            let needs64 = count >= Int64(marker16) || Int64(central.count) >= zip64Threshold || start >= zip64Threshold
            if needs64 {
                let recordOffset = start + Int64(central.count)
                var record = Data()
                record.appendUInt32(0x0606_4B50)
                record.appendUInt64(44)
                record.appendUInt16(45)
                record.appendUInt16(45)
                record.appendUInt32(0)
                record.appendUInt32(0)
                record.appendUInt64(UInt64(count))
                record.appendUInt64(UInt64(count))
                record.appendUInt64(UInt64(central.count))
                record.appendUInt64(UInt64(start))
                record.appendUInt32(0x0706_4B50)
                record.appendUInt32(0)
                record.appendUInt64(UInt64(recordOffset))
                record.appendUInt32(1)
                try handle.write(contentsOf: record)
            }
            var end = Data()
            end.appendUInt32(0x0605_4B50)
            end.appendUInt16(0)
            end.appendUInt16(0)
            end.appendUInt16(count >= Int64(marker16) ? marker16 : UInt16(count))
            end.appendUInt16(count >= Int64(marker16) ? marker16 : UInt16(count))
            end.appendUInt32(Int64(central.count) >= zip64Threshold ? marker32 : UInt32(central.count))
            end.appendUInt32(start >= zip64Threshold ? marker32 : UInt32(start))
            end.appendUInt16(0)
            try handle.write(contentsOf: end)
            try handle.close()
        }
        deinit { try? handle.close() }
    }

    // MARK: Reading

    final class Reader {
        private let handle: FileHandle
        let entries: [Entry]
        private let centralBoundary: Int64

        /// Reads the directory and checks every size and offset against the file's real length
        /// before anything is allocated from it: a directory that lies about a size cannot ask for
        /// memory, and one that points past the file cannot be read.
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
            var count = Int64(record.uint16(at: 10))
            var centralSize = Int64(record.uint32(at: 12))
            var centralOffset = Int64(record.uint32(at: 16))
            guard record.uint16(at: 4) == 0, record.uint16(at: 6) == 0, Int64(record.uint16(at: 8)) == count,
                  22 + Int(record.uint16(at: 20)) == record.count else { throw ZipError.unsupported("split or malformed directory") }
            var endOffset = size - Int64(tailLength) + Int64(eocd.lowerBound)
            if count == Int64(marker16) || centralOffset == Int64(marker32) || centralSize == Int64(marker32) {
                // ZIP64: the locator sits just before the end record and names the 64 bit record.
                guard eocd.lowerBound >= 20 else { throw ZipError.truncated }
                let locator = tail.subdata(in: (eocd.lowerBound - 20)..<eocd.lowerBound)
                guard locator.uint32(at: 0) == 0x0706_4B50, locator.uint32(at: 4) == 0, locator.uint32(at: 16) == 1 else { throw ZipError.unsupported("zip64 locator") }
                let recordOffset = Int64(bitPattern: locator.uint64(at: 8))
                guard recordOffset >= 0, recordOffset + 56 <= endOffset - 20 else { throw ZipError.truncated }
                try handle.seek(toOffset: UInt64(recordOffset))
                let wide = try handle.read(upToCount: 56) ?? Data()
                guard wide.count == 56, wide.uint32(at: 0) == 0x0606_4B50, wide.uint32(at: 16) == 0, wide.uint32(at: 20) == 0 else { throw ZipError.unsupported("zip64 end record") }
                let total = Int64(bitPattern: wide.uint64(at: 32))
                guard Int64(bitPattern: wide.uint64(at: 24)) == total else { throw ZipError.unsupported("split directory") }
                count = total
                centralSize = Int64(bitPattern: wide.uint64(at: 40))
                centralOffset = Int64(bitPattern: wide.uint64(at: 48))
                endOffset = recordOffset
            }
            guard count >= 0, centralSize >= 0, centralOffset >= 0, centralOffset + centralSize == endOffset,
                  centralSize >= count * 46, centralSize <= size else { throw ZipError.truncated }
            centralBoundary = centralOffset
            try handle.seek(toOffset: UInt64(centralOffset))
            let central = try handle.read(upToCount: Int(centralSize)) ?? Data()
            guard Int64(central.count) == centralSize else { throw ZipError.truncated }
            var list: [Entry] = []
            var cursor = 0
            for _ in 0..<count {
                guard cursor + 46 <= central.count, central.uint32(at: cursor) == 0x0201_4B50 else { throw ZipError.truncated }
                let flags = central.uint16(at: cursor + 8)
                let method = central.uint16(at: cursor + 10)
                let crc = central.uint32(at: cursor + 16)
                var compressed = Int64(central.uint32(at: cursor + 20))
                var uncompressed = Int64(central.uint32(at: cursor + 24))
                let nameLength = Int(central.uint16(at: cursor + 28))
                let extraLength = Int(central.uint16(at: cursor + 30))
                let commentLength = Int(central.uint16(at: cursor + 32))
                var localOffset = Int64(central.uint32(at: cursor + 42))
                guard cursor + 46 + nameLength + extraLength + commentLength <= central.count else { throw ZipError.truncated }
                // The ZIP64 extra field carries, in this order, only the values whose 32 bit
                // fields hold the marker.
                if uncompressed == Int64(marker32) || compressed == Int64(marker32) || localOffset == Int64(marker32) {
                    let extra = central.subdata(in: (cursor + 46 + nameLength)..<(cursor + 46 + nameLength + extraLength))
                    guard let field = Self.zip64Field(extra) else { throw ZipError.unsupported("zip64 entry without its extra field") }
                    var at = 0
                    func take() throws -> Int64 {
                        guard at + 8 <= field.count else { throw ZipError.truncated }
                        defer { at += 8 }
                        return Int64(bitPattern: field.uint64(at: at))
                    }
                    if uncompressed == Int64(marker32) { uncompressed = try take() }
                    if compressed == Int64(marker32) { compressed = try take() }
                    if localOffset == Int64(marker32) { localOffset = try take() }
                }
                guard compressed >= 0, uncompressed >= 0, localOffset >= 0,
                      localOffset + 30 + compressed <= centralOffset else { throw ZipError.truncated }
                // UNIX symlink entries can redirect a later install outside the record directory.
                let mode = (central.uint32(at: cursor + 38) >> 16) & 0xF000
                guard mode != 0xA000, central.uint16(at: cursor + 34) == 0 else { throw ZipError.unsupported("symlink or split entry") }
                guard flags & ~UInt16(0x080E) == 0, method == 0 || method == 8 else { throw ZipError.unsupported("entry flags or method") }
                guard method != 0 || compressed == uncompressed else { throw ZipError.truncated }
                let nameData = central.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength))
                if flags & 0x0001 != 0 { throw ZipError.unsupported("encrypted entry") }
                guard let name = String(data: nameData, encoding: .utf8) else { throw ZipError.unsupported("invalid UTF-8 name") }
                list.append(Entry(name: name, method: method, crc: crc, compressedSize: compressed, uncompressedSize: uncompressed, localHeaderOffset: localOffset, flags: flags))
                cursor += 46 + nameLength + extraLength + commentLength
            }
            guard cursor == central.count else { throw ZipError.truncated }
            var priorEnd: Int64 = 0
            for entry in list.sorted(by: { $0.localHeaderOffset < $1.localHeaderOffset }) {
                guard entry.localHeaderOffset >= priorEnd else { throw ZipError.unsupported("overlapping entries") }
                let payload = try Self.payloadOffset(entry, handle: handle, boundary: centralOffset)
                priorEnd = payload + entry.compressedSize
                if entry.flags & 8 != 0 { priorEnd += try Self.descriptorSize(entry, handle: handle, offset: priorEnd, boundary: centralOffset) }
            }
            entries = list
        }

        /// The entry's bytes, inflated and checked against the CRC the directory carries. For the
        /// small entries, the manifest and a record's JSON; a photograph goes through `extract`.
        func read(_ entry: Entry) throws -> Data {
            var out = Data()
            try stream(entry) { out.append($0) }
            return out
        }

        /// The entry inflated straight into `url`, in pieces, the CRC computed as they pass and the
        /// free storage asked for before each is written.
        func extract(_ entry: Entry, to url: URL, space: FreeSpace?) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let out = try FileHandle(forWritingTo: url)
            defer { try? out.close() }
            try stream(entry) { piece in
                try space?.before(piece.count)
                try out.write(contentsOf: piece)
            }
        }

        private func stream(_ entry: Entry, _ sink: (Data) throws -> Void) throws {
            let offset = try Self.payloadOffset(entry, handle: handle, boundary: centralBoundary)
            try handle.seek(toOffset: UInt64(offset))
            var crc = CRC32.Running()
            var produced: Int64 = 0
            var remaining = entry.compressedSize
            func emit(_ piece: Data) throws {
                produced += Int64(piece.count)
                guard produced <= entry.uncompressedSize else { throw ZipError.badCRC(entry.name) }
                crc.update(piece)
                try sink(piece)
            }
            switch entry.method {
            // A pool per piece, for the same reason the writer has one: the read buffers are
            // autoreleased and a restore is one synchronous call.
            case 0:
                while remaining > 0 {
                    try autoreleasepool {
                        let piece = try handle.read(upToCount: Int(min(Int64(Zip.chunk), remaining))) ?? Data()
                        guard !piece.isEmpty else { throw ZipError.truncated }
                        remaining -= Int64(piece.count)
                        try emit(piece)
                    }
                }
            case 8:
                let inflater = try Deflate.Decoder()
                while remaining > 0 {
                    try autoreleasepool {
                        let piece = try handle.read(upToCount: Int(min(Int64(Zip.chunk), remaining))) ?? Data()
                        guard !piece.isEmpty else { throw ZipError.truncated }
                        remaining -= Int64(piece.count)
                        guard let out = try inflater.push(piece, limit: entry.uncompressedSize - produced) else { throw ZipError.inflateFailed(entry.name) }
                        try emit(out)
                    }
                }
                guard let tail = try inflater.finish(limit: entry.uncompressedSize - produced) else { throw ZipError.inflateFailed(entry.name) }
                try emit(tail)
            default: throw ZipError.unsupported("method \(entry.method)")
            }
            guard produced == entry.uncompressedSize, crc.value == entry.crc else { throw ZipError.badCRC(entry.name) }
        }

        private static func zip64Field(_ extra: Data) -> Data? {
            var at = 0
            while at + 4 <= extra.count {
                let id = extra.uint16(at: at), length = Int(extra.uint16(at: at + 2))
                guard at + 4 + length <= extra.count else { return nil }
                if id == 0x0001 { return extra.subdata(in: (at + 4)..<(at + 4 + length)) }
                at += 4 + length
            }
            return nil
        }

        private static func payloadOffset(_ entry: Entry, handle: FileHandle, boundary: Int64) throws -> Int64 {
            try handle.seek(toOffset: UInt64(entry.localHeaderOffset))
            let head = try handle.read(upToCount: 30) ?? Data()
            guard head.count == 30, head.uint32(at: 0) == 0x0403_4B50,
                  head.uint16(at: 6) == entry.flags, head.uint16(at: 8) == entry.method else { throw ZipError.truncated }
            let nameLength = Int(head.uint16(at: 26)), extraLength = Int(head.uint16(at: 28))
            let offset = entry.localHeaderOffset + 30 + Int64(nameLength + extraLength)
            guard offset + entry.compressedSize <= boundary else { throw ZipError.truncated }
            let name = try handle.read(upToCount: nameLength) ?? Data()
            guard name == Data(entry.name.utf8) else { throw ZipError.unsupported("local name mismatch") }
            if entry.flags & 8 == 0 {
                // A local header may carry ZIP64 markers where the directory did not, as Python's
                // zipfile writes when asked to; the sizes are then in its own extra field.
                var compressed = Int64(head.uint32(at: 18)), uncompressed = Int64(head.uint32(at: 22))
                if compressed == Int64(marker32) || uncompressed == Int64(marker32) {
                    let extra = try handle.read(upToCount: extraLength) ?? Data()
                    guard let field = zip64Field(extra), field.count >= 16 else { throw ZipError.truncated }
                    uncompressed = Int64(bitPattern: field.uint64(at: 0))
                    compressed = Int64(bitPattern: field.uint64(at: 8))
                }
                guard head.uint32(at: 14) == entry.crc, compressed == entry.compressedSize,
                      uncompressed == entry.uncompressedSize else { throw ZipError.truncated }
            }
            return offset
        }

        private static func descriptorSize(_ entry: Entry, handle: FileHandle, offset: Int64, boundary: Int64) throws -> Int64 {
            guard offset + 12 <= boundary else { throw ZipError.truncated }
            try handle.seek(toOffset: UInt64(offset))
            let bytes = try handle.read(upToCount: Int(min(24, boundary - offset))) ?? Data()
            guard bytes.count >= 12 else { throw ZipError.truncated }
            let prefix = bytes.uint32(at: 0) == 0x0807_4B50 ? 4 : 0
            // Java writes 8 byte sizes in the descriptor of a ZIP64 entry.
            if bytes.count >= prefix + 20, entry.compressedSize >= Int64(marker32) || entry.uncompressedSize >= Int64(marker32) {
                guard bytes.uint32(at: prefix) == entry.crc,
                      Int64(bitPattern: bytes.uint64(at: prefix + 4)) == entry.compressedSize,
                      Int64(bitPattern: bytes.uint64(at: prefix + 12)) == entry.uncompressedSize else { throw ZipError.truncated }
                return Int64(prefix + 20)
            }
            guard bytes.count >= prefix + 12, bytes.uint32(at: prefix) == entry.crc,
                  Int64(bytes.uint32(at: prefix + 4)) == entry.compressedSize,
                  Int64(bytes.uint32(at: prefix + 8)) == entry.uncompressedSize else { throw ZipError.truncated }
            return Int64(prefix + 12)
        }

        deinit { try? handle.close() }
    }
}

/// The one bound a restore keeps: the disk it writes to. Asked once per megabyte rather than per
/// piece, and each check leaves room for the next megabyte and one more, so the disk never fills.
/// The same rule as Android's `FreeSpace`, on the restore and on the decrypted staging copy.
final class FreeSpace {
    private let directory: URL
    private var unchecked = Int64.max
    private static let megabyte: Int64 = 1024 * 1024

    init(_ directory: URL) { self.directory = directory }

    func before(_ bytes: Int) throws {
        if unchecked >= Self.megabyte {
            let free = (try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
                ?? ((try? FileManager.default.attributesOfFileSystem(forPath: directory.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? Int64.max)
            guard free > 2 * Self.megabyte else { throw ArchiveError.insufficientStorage }
            unchecked = 0
        }
        unchecked += Int64(bytes)
    }
}

/// Raw DEFLATE through the Compression framework, which is what a ZIP entry holds: no zlib
/// header, no trailer, exactly what `java.util.zip.Inflater(nowrap = true)` expects. A stream in
/// both directions, so an entry of any size passes through in pieces.
enum Deflate {
    final class Encoder {
        private var stream = Stream(operation: COMPRESSION_STREAM_ENCODE)
        init() throws { try stream.open() }
        deinit { stream.close() }
        func push(_ input: Data) throws -> Data { try stream.process(input, finalize: false, limit: nil) ?? Data() }
        func finish() throws -> Data { try stream.process(Data(), finalize: true, limit: nil) ?? Data() }
    }

    /// Stops at the size the entry declared: the reader rejects any other size afterwards anyway,
    /// but a lying entry must not inflate past it first and fill memory on the way.
    final class Decoder {
        private var stream = Stream(operation: COMPRESSION_STREAM_DECODE)
        init() throws { try stream.open() }
        deinit { stream.close() }
        func push(_ input: Data, limit: Int64) throws -> Data? { try stream.process(input, finalize: false, limit: limit) }
        func finish(limit: Int64) throws -> Data? { try stream.process(Data(), finalize: true, limit: limit) }
    }

    static func compress(_ input: Data) -> Data {
        guard let encoder = try? Encoder(), let body = try? encoder.push(input), let tail = try? encoder.finish() else { return input }
        return body + tail
    }

    static func decompress(_ input: Data, expected: Int) -> Data? {
        guard let decoder = try? Decoder(), let body = try? decoder.push(input, limit: Int64(expected)),
              let tail = try? decoder.finish(limit: Int64(expected) - Int64(body.count)) else { return nil }
        return body + tail
    }

    private struct Stream {
        let operation: compression_stream_operation
        // The C struct has non-null pointer fields and so no zero initialiser in Swift; it is
        // allocated raw and filled by compression_stream_init, which is how the C API is used.
        private let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        private var ended = false
        private var closed = false

        init(operation: compression_stream_operation) { self.operation = operation }

        mutating func open() throws {
            guard compression_stream_init(stream, operation, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { throw ArchiveError.invalidEntry("deflate") }
        }

        mutating func close() {
            if !closed { compression_stream_destroy(stream); stream.deallocate(); closed = true }
        }

        /// Feeds `input` and returns what came out; nil when the stream fails or passes `limit`.
        mutating func process(_ input: Data, finalize: Bool, limit: Int64?) throws -> Data? {
            if ended { return input.isEmpty ? Data() : nil }
            var output = Data()
            let bufferSize = Zip.chunk
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            // An empty input still needs a valid source pointer for the finalising call.
            let empty = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
            defer { empty.deallocate() }
            let flags = Int32(finalize ? COMPRESSION_STREAM_FINALIZE.rawValue : 0)
            return input.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Data? in
                let base = source.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer(empty)
                stream.pointee.src_ptr = base
                stream.pointee.src_size = source.count
                while true {
                    stream.pointee.dst_ptr = buffer
                    stream.pointee.dst_size = bufferSize
                    let status = compression_stream_process(stream, flags)
                    output.append(buffer, count: bufferSize - stream.pointee.dst_size)
                    if let limit, Int64(output.count) > limit { return nil }
                    switch status {
                    case COMPRESSION_STATUS_OK:
                        // Without more input, the encoder has emitted what it could for now.
                        if stream.pointee.src_size == 0, !finalize, stream.pointee.dst_size != 0 { return output }
                        continue
                    case COMPRESSION_STATUS_END:
                        ended = true
                        return stream.pointee.src_size == 0 ? output : nil
                    default: return nil
                    }
                }
            }
        }
    }
}

/// The ZIP CRC, table driven, kept running across the pieces of a streamed entry.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var c = UInt32(index)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    struct Running {
        private var crc: UInt32 = 0xFFFF_FFFF
        var value: UInt32 { crc ^ 0xFFFF_FFFF }

        // Data's element iterator is a function call per byte on a type that need not be
        // contiguous, and over an archive of photographs that is the whole cost of the checksum.
        // The bytes are read straight from the buffer, and the table through a binding the
        // compiler does not bounds-check on every lookup.
        mutating func update(_ data: Data) {
            var c = crc
            CRC32.table.withUnsafeBufferPointer { lookup in
                data.withUnsafeBytes { bytes in
                    for byte in bytes { c = lookup[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
                }
            }
            crc = c
        }
    }

    static func checksum(_ data: Data) -> UInt32 {
        var running = Running()
        running.update(data)
        return running.value
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

    mutating func appendUInt64(_ value: UInt64) {
        appendUInt32(UInt32(value & 0xFFFF_FFFF))
        appendUInt32(UInt32(value >> 32))
    }

    func uint16(at offset: Int) -> UInt16 {
        let i = startIndex + offset
        return UInt16(self[i]) | (UInt16(self[i + 1]) << 8)
    }

    func uint32(at offset: Int) -> UInt32 {
        UInt32(uint16(at: offset)) | (UInt32(uint16(at: offset + 2)) << 16)
    }

    func uint64(at offset: Int) -> UInt64 {
        UInt64(uint32(at: offset)) | (UInt64(uint32(at: offset + 4)) << 32)
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
