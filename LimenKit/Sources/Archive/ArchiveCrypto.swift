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
    private static let zipStart: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
    static let decryptPrefix = "archive-decrypt-"

    /// What a restore killed part way leaves in `root`: the decrypted copy of an encrypted backup
    /// and the unpacked stage. Each is a whole extra copy of the evidence that nothing else reads,
    /// so it sits in private storage until something removes it.
    static func sweep(_ root: URL) {
        ArchiveStaging.sweepAll(root, prefix: decryptPrefix)
        ArchiveStaging.sweepAll(root, prefix: ArchiveIO.stagePrefix)
    }

    static func export(root: URL, password: String, to output: URL, protocolIds: Set<String>? = nil, packer: (any JpegPacker)? = JpegXL.loaded) throws {
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: output) } }
        ArchiveStaging.sweep(AppFiles.scratch, prefix: "limen-export-")
        // No password writes the plain archive, byte for byte the form the legacy branch of
        // `importArchive` has always read, so an unprotected backup needs no new reader and no new
        // version. Whether to protect is the person's call; the screen says which they made.
        if password.isEmpty {
            try ArchiveIO.export(root: root, to: output, protocolIds: protocolIds, packer: packer)
            completed = true
            return
        }
        let salt = try randomBytes(saltBytes)
        let iv = try randomBytes(ivBytes)
        let header = magic + [version] + salt + iv
        let key = try derive(password: password, salt: salt)
        // The ZIP is built in a scratch file and encrypted from it in chunks, so a whole backup
        // never sits in memory, and the scratch file is removed whatever happens.
        //
        // In the CACHE, never beside the output. Android hands the ZIP writer a CipherOutputStream
        // and no plaintext ever reaches disk; here it must, and `output` is in Documents, which
        // `UIFileSharingEnabled` shows in Files. A plaintext archive of every record, photograph
        // and signature staged there is readable for as long as the export runs, and a kill before
        // the defer leaves it readable for good.
        let plain = AppFiles.scratch.appendingPathComponent("limen-export-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: plain) }
        try ArchiveIO.export(root: root, to: plain, protocolIds: protocolIds, packer: packer)
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let out = try FileHandle(forWritingTo: output)
        defer { try? out.close() }
        try out.write(contentsOf: header)
        let cipher = try AESGCMStream(key: key, iv: iv, aad: header)
        let input = try FileHandle(forReadingFrom: plain)
        defer { try? input.close() }
        // A pool per chunk: the reads are autoreleased and the export is one synchronous call.
        while try autoreleasepool(invoking: { () throws -> Bool in
            guard let chunk = try input.read(upToCount: 256 * 1024), !chunk.isEmpty else { return false }
            try out.write(contentsOf: cipher.encrypt(chunk))
            return true
        }) {}
        try out.write(contentsOf: cipher.finalizeEncryption())
        try out.synchronize()
        completed = true
    }

    /// Encrypted archives are preferred; plain ZIP files remain importable. No size bound: the
    /// one limit a restore meets is the free storage the decrypted copy and the unpacked stage
    /// need, asked for as the bytes are written.
    static func importArchive(root: URL, password: String, from input: URL, repairCorrupt: Bool = false, packer: (any JpegPacker)? = JpegXL.loaded) throws -> ArchiveImportResult {
        guard Files.isRegularFile(input) else { throw ArchiveError.truncated }
        let probe = try FileHandle(forReadingFrom: input)
        defer { try? probe.close() }
        let prefix = try probe.read(upToCount: magic.count) ?? Data()
        if prefix != magic {
            return try ArchiveIO.importArchive(root: root, from: input, repairCorrupt: repairCorrupt, packer: packer)
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
        // The staged file is every record in the archive in the clear, and the defer below cannot
        // run if the process is killed part way. Anything an earlier run left behind goes first,
        // rather than sitting in Application Support until the app is deleted.
        ArchiveStaging.sweep(root, prefix: decryptPrefix)
        let staged = root.appendingPathComponent("\(decryptPrefix)\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: staged) }
        FileManager.default.createFile(atPath: staged.path, contents: nil)
        let out = try FileHandle(forWritingTo: staged)
        let space = FreeSpace(root)
        // The last 16 bytes of the stream are the tag, not ciphertext: each chunk is decrypted up
        // to that window and the window is carried to the next chunk as a copy of its own. A
        // slice (`suffix`) of the chunk carried it before, and on the phone a slice keeps its
        // whole storage alive and appends into it, so the restore held every chunk it had read:
        // a 1 GiB backup grew the footprint by 1 GiB where the simulator showed nothing.
        var holdback = Data()
        // A wrong password decrypts to noise, but the tag that says so is the last thing in the
        // file. Every archive ArchiveIO.importArchive accepts opens with a zip local header, since
        // it needs the manifest entry, so noise there is refused after the first chunk instead of
        // after the whole backup has been written to disk.
        var opening = Data()
        do {
            defer { try? out.close() }
            while try autoreleasepool(invoking: { () throws -> Bool in
                guard let chunk = try probe.read(upToCount: 256 * 1024), !chunk.isEmpty else { return false }
                var block = holdback
                block.append(chunk)
                if block.count > 16 {
                    let bodyCount = block.count - 16
                    try space.before(bodyCount)
                    let plain = try cipher.decrypt(block.prefix(bodyCount))
                    if opening.count < zipStart.count {
                        opening.append(plain.prefix(zipStart.count - opening.count))
                        if opening.count == zipStart.count, [UInt8](opening) != zipStart { throw ArchiveError.wrongPassword }
                    }
                    try out.write(contentsOf: plain)
                    holdback = Data(block.suffix(16))
                } else {
                    holdback = Data(block)
                }
                return true
            }) {}
            guard holdback.count == 16 else { throw ArchiveError.truncated }
            guard cipher.finalizeDecryption(tag: holdback) else { throw ArchiveError.wrongPassword }
        }
        return try ArchiveIO.importArchive(root: root, from: staged, repairCorrupt: repairCorrupt, packer: packer)
    }

    /// PBKDF2 encodes the password as UTF-8, as Java's PBKDF2WithHmacSHA256 does.
    static func derive(password: String, salt: Data) throws -> Data {
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

    private static func randomBytes(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        // Checked, not assumed. A generator that failed silently would have left the salt and the
        // IV all zero, and an all-zero IV under a reused key is the one thing GCM cannot survive.
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { throw ArchiveError.randomUnavailable }
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
    // Shoup's tables: the hash subkey multiplied by every byte value, and the reduction for every
    // byte an 8 bit shift carries past x^127. Sixteen lookups per block where the textbook
    // shift-and-add took 128 rounds, which at about a megabyte a second in a debug build made an
    // encrypted backup of a phone's photographs a matter of hours.
    private let multiples: [(UInt64, UInt64)]
    private let reductions: [UInt64]
    private let encryptedJ0: [UInt8]
    private var ghash: (UInt64, UInt64) = (0, 0)
    private var aadLength: UInt64 = 0
    private var textLength: UInt64 = 0
    private var pending: [UInt8] = []

    init(key: Data, iv: Data, aad: Data) throws {
        precondition(iv.count == 12, "GCM here uses a 96 bit IV, the only length the archive writes")
        let keyBytes = [UInt8](key)
        let hashKey = Self.block(Self.aesBlock(keyBytes, [UInt8](repeating: 0, count: 16)))
        (multiples, reductions) = Self.tables(for: hashKey)
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
        absorb(aad)
        aadLength = UInt64(aad.count)
        // GCM pads the associated data to a block boundary and hashes that final block; it does
        // not drop the remainder. Clearing `pending` here instead threw the header's last 6 bytes
        // away, because the envelope's 38 byte header is two blocks and a remainder, and the tag
        // stopped being the tag Java computes over the same header.
        flushPending()
    }

    deinit {
        if let cryptor { CCCryptorRelease(cryptor) }
    }

    func encrypt(_ plain: Data) throws -> Data {
        let cipher = try keystream(plain)
        absorb(cipher)
        textLength += UInt64(cipher.count)
        return cipher
    }

    func finalizeEncryption() -> Data {
        Data(tag())
    }

    func decrypt(_ cipher: Data) throws -> Data {
        absorb(cipher)
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
    // boundary on its own, so the leftover of one is flushed before the other starts. Whole blocks
    // are read straight out of the buffer: building a 16 byte array per block, and copying every
    // chunk into `pending` first, cost more than the multiply once the multiply had its tables.
    private func absorb(_ bytes: Data) {
        bytes.withUnsafeBytes { raw in
            var i = 0
            if !pending.isEmpty {
                let take = min(16 - pending.count, raw.count)
                pending.append(contentsOf: raw[0..<take])
                i = take
                guard pending.count == 16 else { return }
                mix(pending)
                pending.removeAll(keepingCapacity: true)
            }
            while raw.count - i >= 16 {
                var high: UInt64 = 0
                var low: UInt64 = 0
                for j in 0..<8 {
                    high = (high << 8) | UInt64(raw[i + j])
                    low = (low << 8) | UInt64(raw[i + 8 + j])
                }
                mix(high: high, low: low)
                i += 16
            }
            if i < raw.count { pending.append(contentsOf: raw[i...]) }
        }
    }

    private func flushPending() {
        guard !pending.isEmpty else { return }
        var block = pending
        block += [UInt8](repeating: 0, count: 16 - block.count)
        mix(block)
        pending = []
    }

    private func mix(_ block: [UInt8]) {
        let x = Self.block(block)
        mix(high: x.0, low: x.1)
    }

    /// One GHASH step: Y = (Y xor X) times H, the product taken a byte at a time from the tables.
    private func mix(high: UInt64, low: UInt64) {
        let xh = ghash.0 ^ high
        let xl = ghash.1 ^ low
        var rh: UInt64 = 0
        var rl: UInt64 = 0
        // Horner over the sixteen bytes from the last: r = r times x^8, plus the byte's multiple.
        for k in stride(from: 15, through: 0, by: -1) {
            let byte = k < 8 ? Int((xh >> (56 - 8 * UInt64(k))) & 0xFF) : Int((xl >> (56 - 8 * UInt64(k - 8))) & 0xFF)
            let carried = Int(rl & 0xFF)
            rl = (rl >> 8) | (rh << 56)
            rh = (rh >> 8) ^ reductions[carried]
            let m = multiples[byte]
            rh ^= m.0
            rl ^= m.1
        }
        ghash = (rh, rl)
    }

    /// `multiples[b]` is H times the polynomial whose coefficients are the byte b at x^0 to x^7,
    /// so the top bit of b is x^0 and H itself. `reductions[b]` folds the byte an 8 bit shift
    /// pushes past x^127 back under the field polynomial x^128 + x^7 + x^2 + x + 1, whose low
    /// terms are 0xE1 at the top of the block in GCM's bit order.
    private static func tables(for h: (UInt64, UInt64)) -> ([(UInt64, UInt64)], [UInt64]) {
        var multiples = [(UInt64, UInt64)](repeating: (0, 0), count: 256)
        var reductions = [UInt64](repeating: 0, count: 256)
        multiples[128] = h
        reductions[128] = 0xE100_0000_0000_0000
        var bit = 64
        while bit > 0 {
            multiples[bit] = timesX(multiples[bit * 2])
            reductions[bit] = reductions[bit * 2] >> 1
            bit /= 2
        }
        var power = 2
        while power <= 128 {
            for j in 1..<power {
                multiples[power + j] = (multiples[power].0 ^ multiples[j].0, multiples[power].1 ^ multiples[j].1)
                reductions[power + j] = reductions[power] ^ reductions[j]
            }
            power *= 2
        }
        return (multiples, reductions)
    }

    /// Multiplication by x in GF(2^128) with the GCM bit order: a shift toward the high powers,
    /// which is a shift right here, and the field polynomial folded in when a bit leaves.
    private static func timesX(_ v: (UInt64, UInt64)) -> (UInt64, UInt64) {
        let carried = v.1 & 1
        var out = ((v.0 >> 1), (v.1 >> 1) | (v.0 << 63))
        if carried == 1 { out.0 ^= 0xE100_0000_0000_0000 }
        return out
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
