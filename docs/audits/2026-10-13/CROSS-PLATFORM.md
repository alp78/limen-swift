# Canonical records and archive interoperability

Engineering verification continued on 14 October 2026 in Europe/Zurich. The Android checkout was read only throughout.

## References

The requested baseline is `eb5c03800a9e749155db718136c9418a58c0d11c`. It was exported with `git archive` to `/tmp/limen-android-eb5c038-reference` without changing that repository. The clean local Android HEAD is `d81796d07ada38aa6e7955d31cf297fe02cac010`. The intervening remediation changes include stable default serialization, numeric validation and export/ordering corrections, so the current verified HEAD is the implementation reference, with the original baseline retained for comparison.

`tools/schema.py` reads the actual 26 serializable constructors and 243 fields. It handles both `@EncodeDefault(NEVER)` and `@EncodeDefault(ALWAYS)` and fails on unsupported constructor syntax. `SupportingDocument.mime`, `ReplacementEstimate.source` and `LegalSnapshot.checkedOn` are explicitly persisted even when equal to their defaults, matching current Android. This does not change canonical encoding or historical fingerprints.

## Executed evidence

`tools/compatibility.py` compiled the original Android JVM data, integrity, store, ZIP and cipher sources with Kotlin 2.3.20 and kotlinx.serialization 1.8.1, matching its declared dependencies. Compiler dependencies live in `/tmp/limen-jvm-compatibility`; the Android tree was neither built nor modified. A Java URL-constructor deprecation warning in the original address helper is the only compile warning. No address lookup was invoked.

Synthetic fixtures exercise all 243 constructor fields, every nested map, intentional nonalphabetical insertion order, escaped/Unicode testimony, three participants, independent positions/reservations, an unknown deposit, room/meter evidence, a supporting PDF, legal snapshot and retained PDF/HTML. Draft, final, delivered and amendment stages are encoded separately. The synthetic pictures and PDFs contain no personal data.

The simulator passed canonical/stored-byte and fingerprint comparisons against Kotlin outputs for all four stages. It imported both the Android plain ZIP and Unicode-password encrypted archive, then wrote Swift plain/encrypted archives. Java imported both Swift archives and independently verified every canonical record and fingerprint. See `evidence/cross-platform-swift.log` and `evidence/jvm-bidirectional.log`.

The verified Swift artifacts are retained in `evidence/`:

| File | SHA-256 |
|---|---|
| `swift.zip` | `b38f2dd7abb0df06c88ed9e2384ccbc6136207339e976975c87e52cbb1742ce1` |
| `swift.limen` | `05fe44bc90630e8ed675928bc4577e86fd70a44bbc4cbd89296de96cb9a7145f` |

The Java verifier also emitted `jvm-return.zip` and `jvm-return.limen` after reading Swift archives. The final simulator suite passed importing those files, closing Swift → JVM → Swift. All **144 tests in 20 LimenKit suites** passed on iPhone 17 Pro / iOS 26.5, including the unchanged-byte HEIC fixture, all eight EXIF pixel permutations, upright-width sampling, strict schema limits, finalized-record immutability and explicit repair of missing retained exports. The latest combined rerun also passed **25 app tests in 5 suites plus 4 bundle XCTest tests**, including complete PDF/HTML output, rasterized glyph pixels, export/preview races and photo-intake ownership. See [final-unit-all.log](evidence/final-unit-all.log), result bundle `/tmp/limen-final-unit-all.xcresult`; the earlier [kit-only log](evidence/final-kit.log) is retained. This is simulator evidence, not physical-device HEIC/camera coverage.

The exact latest combined unit command was:

```sh
xcodebuild -workspace Limen.xcworkspace -scheme AllTests \
  -destination 'platform=iOS Simulator,id=6F9172CC-DF86-4F05-9EB3-42E8E287668F' \
  -derivedDataPath ./DD-final -collect-test-diagnostics never \
  -only-testing:LimenKitTests -only-testing:LimenTests \
  -resultBundlePath /tmp/limen-final-unit-all.xcresult test
```

`LimenKitTests/Fixtures/Compatibility/reference.json` records the source/tool versions and artifact hashes. The normal encrypted backups use fresh randomness. `crypto-vector.limen` is a separate deterministic JVM/JCE test-only vector: fixed 16-byte salt, 12-byte IV, the real 38-byte authenticated LIMENSAFE header, Unicode password `päss 🔐`, 210,000 PBKDF2 rounds and 700,003 payload bytes. Swift compares its complete ciphertext/tag and derived key against this vector across 256 KiB chunk boundaries. The existing CryptoKit tests additionally cover nonaligned associated-data lengths.

## Reproduction

```sh
cd /Users/aperi/DEV/SWIFT/limen
LIMEN_ANDROID=/Users/aperi/DEV/ANDROID/limen python3 tools/schema.py --check
LIMEN_ANDROID=/Users/aperi/DEV/ANDROID/limen python3 tools/fixtures/input.py
LIMEN_ANDROID=/Users/aperi/DEV/ANDROID/limen python3 tools/compatibility.py
make gen
# Run the LimenKit test scheme on the isolated audit simulator.
# CrossPlatformTests prints LIMEN_SWIFT_COMPAT_OUTPUT with its generated archive directory.
LIMEN_ANDROID=/Users/aperi/DEV/ANDROID/limen python3 tools/compatibility.py --verify-swift '<LIMEN_SWIFT_COMPAT_OUTPUT>'
# Run CrossPlatformTests again to verify the Java-returned plain/encrypted archives.
```

The provided return fixtures permit the suite to run without Java. The generator deliberately does not overwrite those return fixtures unless `--verify-swift` is supplied. The generator omits transient duplicated store directories from committed evidence. A synthetic HEIC was made from `assets/wall.png` with the system `sips -s format heic` encoder; its original bytes remain unchanged during validation.

## Intentional reader and storage boundaries

Swift explicitly refuses unknown fields, unknown enum values, unsupported schemas, duplicate keys, invalid nonnullable nulls, Boolean/integer coercion, fractional or overflowing integers, excessive nesting and protocol JSON over 8 MiB. Current Android ignores unknown keys. This is an intentional safety difference required by this audit: a richer unsupported record is listed as unreadable and retained intact rather than silently rewritten with missing facts. No automatic migration adds participant IDs or legal snapshots to old finalized records.

All mutable distribution metadata is excluded identically from canonical fingerprints. Store saves serialize through a shared lock, reject stale/divergent sequences and older content revisions, and reject material changes to a finalized record even under a newer save sequence. The previous exact readable file is retained under `recovery/<id>/last-good.json`; repair preserves the damaged original before replacement. Unsupported originals cannot be overwritten by a normal save.

Scoped backups include selected records, referenced photos/signatures/documents and tracked retained PDF/HTML. Unreferenced private evidence, another record and recovery originals are excluded. Retrieval uses safe retained filenames under the restored private export directory; foreign URIs are never dereferenced. A healthy existing record is preserved. Explicit corrupt-record repair quarantines the prior JSON/evidence/exports and rolls them back if installation fails.

ZIP input/output is capped at 64 MiB, with exactly 54 additional bytes allowed for the encrypted envelope. Expanded size is capped at 256 MiB, 20,000 entries, 8 MiB protocol entries and 64 MiB other entries. Central/local headers, name/size agreement, data descriptors, offsets, overlaps, symlink metadata and payload sizes are checked before allocation. CRC and actual inflated sizes are checked before installation. Authentication completes before any encrypted record is installed.

Image/document intake is capped at 32 MiB. ImageIO validates pixel decoding and all eight EXIF orientations, with a maximum 80 million pixels and 32,768 per dimension; photos are sampled using upright width and originals are never reencoded. Finalization/export use a separate decoding/hash boundary while canonical hashing preserves the historical byte-based contract. Supporting PDFs require readable pages, images must decode, and failures name the evidence. A file extension is not treated as proof of its content type.

The interoperability execution is JVM data/archive code, not a physical Android UI test or proof that every Android handset renders HEIC. PDF/HTML renderer meaning, assistive-technology behavior and legal/native-language review are separate gates. The JSON strictness and bounds intentionally go beyond the Android reader where preserving unsupported or damaged facts requires refusal.
