import Foundation
import LimenJxl

/// A lossless repacking of a JPEG and its inverse; nil when the input does not take it.
public protocol JpegPacker: Sendable {
    func pack(_ jpeg: Data) -> Data?
    func unpack(_ packed: Data) -> Data?
}

/// JPEG XL's lossless JPEG recompression, from libjxl built into the app, for the photographs in a
/// backup. A JPEG is general compression's worst case: Deflate took 1.3 percent off thirty camera
/// originals and XZ 1.5 percent. Repacked, they came out 20.8 percent smaller on Android, and each
/// unpacked to the identical file, metadata and a Pixel's appended gain map included, so the
/// evidence hashes recorded against the originals hold after a restore. The photographs on the
/// phone and in the PDF stay JPEG.
///
/// Single-threaded and at effort 7, as the Android build runs it: libjxl's thread pool spread over
/// a phone's big and little cores took four times as long as one thread, and effort 9 saved 0.3
/// percent more and took 19 times as long.
public struct JpegXL: JpegPacker {
    /// libjxl as linked into this build. The unit tests substitute a packer of their own, and a
    /// build that lacked the library would pass nil here and refuse a repacked backup whole.
    public static let loaded: (any JpegPacker)? = JpegXL()

    public init() {}

    public func pack(_ jpeg: Data) -> Data? {
        call(jpeg, limen_jxl_pack)
    }

    public func unpack(_ packed: Data) -> Data? {
        call(packed, limen_jxl_unpack)
    }

    private func call(_ input: Data, _ function: (UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, UnsafeMutablePointer<Int>?) -> Int32) -> Data? {
        var out: UnsafeMutablePointer<UInt8>?
        var length = 0
        let ok = input.withUnsafeBytes { bytes -> Int32 in
            guard let base = bytes.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return function(base, bytes.count, &out, &length)
        }
        guard ok != 0, let out else { return nil }
        defer { limen_jxl_free(out) }
        return Data(bytes: out, count: length)
    }
}
