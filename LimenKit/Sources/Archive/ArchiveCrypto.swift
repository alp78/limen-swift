import CommonCrypto
import Foundation

/// Password-encrypted envelope around the validated Limen archive stream.
///
/// The layout is the Android one byte for byte: "LIMENSAFE", one version byte, a 16 byte salt,
/// a 12 byte IV, then AES-256-GCM over the ZIP with that whole header as the associated data,
/// the key derived by PBKDF2-HMAC-SHA256 over 210,000 rounds. A backup made on either phone
/// restores on the other.
enum ArchiveCrypto {
    private static let magic = Data("LIMENSAFE".utf8)
    private static let version: UInt8 = 1
    private static let saltBytes = 16
    private static let ivBytes = 12
    private static let keyBytes = 32
    private static let iterations: UInt32 = 210_000
    /// The same ceiling the unpacker applies, enforced before the unpacker ever sees the bytes.
    private static let maxPlaintextBytes: Int64 = 2 * 1024 * 1024 * 1024

    static func export(root: URL, password: String, to output: URL) throws {
        // No password writes the plain archive, byte for byte the form the legacy branch of
        // `importArchive` has always read, so an unprotected backup needs no new reader and no new
        // version. Whether to protect is the person's call; the screen says which they made.
        if password.isEmpty {
            try ArchiveIO.export(root: root, to: output)
            return
        }
        let salt = randomBytes(saltBytes)
        let iv = randomBytes(ivBytes)
        let header = magic + [version] + salt + iv
        let key = try derive(password: password, salt: salt)
        // The ZIP is built in a scratch file beside the output and encrypted from it in chunks:
        // a whole backup never sits in memory, and the scratch file is removed whatever happens.
        let plain = output.deletingLastPathComponent().appendingPathComponent(".limen-export-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: plain) }
        try ArchiveIO.export(root: root, to: plain)
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let out = try FileHandle(forWritingTo: output)
        defer { try? out.close() }
        try out.write(contentsOf: header)
        let cipher = try AESGCMStream(key: key, iv: iv, aad: header)
        let input = try FileHandle(forReadingFrom: plain)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 256 * 1024), !chunk.isEmpty {
            try out.write(contentsOf: cipher.encrypt(chunk))
        }
        try out.write(contentsOf: cipher.finalizeEncryption())
    }

    /// Encrypted archives are preferred; version-1 plain ZIP files remain importable.
    static func importArchive(root: URL, password: String, from input: URL) throws -> ArchiveImportResult {
        let probe = try FileHandle(forReadingFrom: input)
        defer { try? probe.close() }
        let prefix = try probe.read(upToCount: magic.count) ?? Data()
        if prefix != magic {
            return try ArchiveIO.importArchive(root: root, from: input)
        }
        guard !password.isEmpty else { throw ArchiveError.emptyPassword }
        guard let versionByte = try probe.read(upToCount: 1)?.first, versionByte == version else { throw ArchiveError.unsupportedVersion }
        let salt = try probe.read(upToCount: saltBytes) ?? Data()
        let iv = try probe.read(upToCount: ivBytes) ?? Data()
        guard salt.count == saltBytes, iv.count == ivBytes else { throw ArchiveError.truncated }
        let header = magic + [version] + salt + iv
        let key = try derive(password: password, salt: salt)
        let cipher = try AESGCMStream(key: key, iv: iv, aad: header)

        // Decrypted whole, and authenticated, BEFORE a single record is installed: the tag at the
        // end is what makes the bytes mean anything, and the installer only ever sees a verified
        // file.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let staged = root.appendingPathComponent("archive-decrypt-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: staged) }
        FileManager.default.createFile(atPath: staged.path, contents: nil)
        let out = try FileHandle(forWritingTo: staged)
        var written: Int64 = 0
        var tail = Data()
        do {
            defer { try? out.close() }
            while let chunk = try probe.read(upToCount: 256 * 1024), !chunk.isEmpty {
                tail.append(chunk)
                // The last 16 bytes of the stream are the tag, not ciphertext; everything ahead
                // of that window is safe to decrypt now.
                if tail.count > 16 {
                    let body = tail.prefix(tail.count - 16)
                    tail = tail.suffix(16)
                    written += Int64(body.count)
                    guard written <= maxPlaintextBytes else { throw ArchiveError.tooLarge }
                    try out.write(contentsOf: cipher.decrypt(Data(body)))
                }
            }
            guard tail.count == 16 else { throw ArchiveError.truncated }
            guard cipher.finalizeDecryption(tag: tail) else { throw ArchiveError.wrongPassword }
        }
        return try ArchiveIO.importArchive(root: root, from: staged)
    }

    /// PBKDF2 encodes the password as UTF-8, as Java's PBKDF2WithHmacSHA256 does.
    private static func derive(password: String, salt: Data) throws -> Data {
        var key = Data(count: keyBytes)
        let passwordBytes = Array(password.utf8)
        let status = key.withUnsafeMutableBytes { keyBuffer in
            salt.withUnsafeBytes { saltBuffer in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.map { CChar(bitPattern: $0) }, passwordBytes.count,
                    saltBuffer.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
                    keyBuffer.bindMemory(to: UInt8.self).baseAddress, keyBytes
                )
            }
        }
        guard status == kCCSuccess else { throw ArchiveError.wrongPassword }
        return key
    }

    private static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}

/// AES-GCM a chunk at a time.
///
/// CryptoKit seals a whole `Data` in one call, and a backup can be most of a phone's
/// photographs; CommonCrypto has no public GCM at all. So the mode is assembled the way the
/// standard defines it: AES in counter mode from CommonCrypto for the bytes, and GHASH written
/// here for the tag. `ArchiveCryptoTests` checks it against CryptoKit's own implementation.
final class AESGCMStream {
    private var cryptor: CCCryptorRef?
    private let hashKey: (UInt64, UInt64)
    private let encryptedJ0: [UInt8]
    private var ghash: (UInt64, UInt64) = (0, 0)
    private var aadLength: UInt64 = 0
    private var textLength: UInt64 = 0
    private var pending: [UInt8] = []

    init(key: Data, iv: Data, aad: Data) throws {
        precondition(iv.count == 12, "GCM here uses a 96 bit IV, the only length the archive writes")
        let keyBytes = [UInt8](key)
        hashKey = Self.block(Self.aesBlock(keyBytes, [UInt8](repeating: 0, count: 16)))
        var j0 = [UInt8](iv)
        j0 += [0, 0, 0, 1]
        encryptedJ0 = Self.aesBlock(keyBytes, j0)
        var counter = j0
        Self.increment(&counter)
        var ref: CCCryptorRef?
        let status = keyBytes.withUnsafeBufferPointer { k in
            counter.withUnsafeBufferPointer { c in
                CCCryptorCreateWithMode(CCOperation(kCCEncrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES), CCPadding(ccNoPadding), c.baseAddress, k.baseAddress, k.count, nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE), &ref)
            }
        }
        guard status == kCCSuccess, let ref else { throw ArchiveError.wrongPassword }
        cryptor = ref
        absorb([UInt8](aad))
        aadLength = UInt64(aad.count)
        pending = []
    }

    deinit {
        if let cryptor { CCCryptorRelease(cryptor) }
    }

    func encrypt(_ plain: Data) throws -> Data {
        let cipher = try keystream(plain)
        absorb([UInt8](cipher))
        textLength += UInt64(cipher.count)
        return cipher
    }

    func finalizeEncryption() -> Data {
        Data(tag())
    }

    func decrypt(_ cipher: Data) throws -> Data {
        absorb([UInt8](cipher))
        textLength += UInt64(cipher.count)
        return try keystream(cipher)
    }

    func finalizeDecryption(tag expected: Data) -> Bool {
        let computed = tag()
        guard expected.count == 16 else { return false }
        var difference: UInt8 = 0
        for (a, b) in zip(computed, expected) { difference |= a ^ b }
        return difference == 0
    }

    private func keystream(_ input: Data) throws -> Data {
        guard let cryptor else { throw ArchiveError.wrongPassword }
        var output = Data(count: input.count + 16)
        var moved = 0
        let status = input.withUnsafeBytes { inBuffer in
            output.withUnsafeMutableBytes { outBuffer in
                CCCryptorUpdate(cryptor, inBuffer.baseAddress, input.count, outBuffer.baseAddress, outBuffer.count, &moved)
            }
        }
        guard status == kCCSuccess else { throw ArchiveError.wrongPassword }
        return output.prefix(moved)
    }

    private func tag() -> [UInt8] {
        flushPending()
        var lengths = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            lengths[i] = UInt8(((aadLength * 8) >> (56 - 8 * UInt64(i))) & 0xFF)
            lengths[8 + i] = UInt8(((textLength * 8) >> (56 - 8 * UInt64(i))) & 0xFF)
        }
        mix(lengths)
        var result = Self.bytes(ghash)
        for i in 0..<16 { result[i] ^= encryptedJ0[i] }
        return result
    }

    // GHASH takes whole blocks; each of the associated data and the text is padded to a block
    // boundary on its own, so the leftover of one is flushed before the other starts.
    private func absorb(_ bytes: [UInt8]) {
        pending += bytes
        var index = 0
        while pending.count - index >= 16 {
            mix(Array(pending[index..<index + 16]))
            index += 16
        }
        pending.removeFirst(index)
    }

    private func flushPending() {
        guard !pending.isEmpty else { return }
        var block = pending
        block += [UInt8](repeating: 0, count: 16 - block.count)
        mix(block)
        pending = []
    }

    /// The associated data is padded before the text begins.
    func endAssociatedData() { flushPending() }

    private func mix(_ block: [UInt8]) {
        let x = Self.block(block)
        ghash = Self.multiply((ghash.0 ^ x.0, ghash.1 ^ x.1), hashKey)
    }

    /// Multiplication in GF(2^128) with the GCM bit order, the textbook shift-and-add.
    private static func multiply(_ x: (UInt64, UInt64), _ y: (UInt64, UInt64)) -> (UInt64, UInt64) {
        var z: (UInt64, UInt64) = (0, 0)
        var v = y
        for i in 0..<128 {
            let bit = i < 64 ? (x.0 >> (63 - UInt64(i))) & 1 : (x.1 >> (127 - UInt64(i))) & 1
            if bit == 1 { z = (z.0 ^ v.0, z.1 ^ v.1) }
            let low = v.1 & 1
            v.1 = (v.1 >> 1) | (v.0 << 63)
            v.0 >>= 1
            if low == 1 { v.0 ^= 0xE100_0000_0000_0000 }
        }
        return z
    }

    private static func block(_ bytes: [UInt8]) -> (UInt64, UInt64) {
        var high: UInt64 = 0
        var low: UInt64 = 0
        for i in 0..<8 {
            high = (high << 8) | UInt64(bytes[i])
            low = (low << 8) | UInt64(bytes[8 + i])
        }
        return (high, low)
    }

    private static func bytes(_ value: (UInt64, UInt64)) -> [UInt8] {
        (0..<8).map { UInt8((value.0 >> (56 - 8 * UInt64($0))) & 0xFF) } + (0..<8).map { UInt8((value.1 >> (56 - 8 * UInt64($0))) & 0xFF) }
    }

    private static func increment(_ counter: inout [UInt8]) {
        for i in stride(from: 15, through: 12, by: -1) {
            counter[i] &+= 1
            if counter[i] != 0 { break }
        }
    }

    /// One AES block in ECB, for the hash subkey and the tag mask.
    private static func aesBlock(_ key: [UInt8], _ input: [UInt8]) -> [UInt8] {
        var output = [UInt8](repeating: 0, count: 16)
        var moved = 0
        _ = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode), key, key.count, nil, input, 16, &output, 16, &moved)
        return output
    }
}
