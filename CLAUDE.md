# Limen, the iOS port

Native Swift/SwiftUI port of the Android original at `/Users/aperi/DEV/ANDROID/limen` (from this repo: `../../ANDROID/limen`). The Android source is the specification: its product decisions are deliberate, its comments carry the reasons, and those reasons apply here unless iOS genuinely cannot honor them. No redesigns, no added features, nothing dropped for being awkward.

## Decisions, settled 2026-09-04

| Decision | Choice | Reason in one line |
|---|---|---|
| Deployment target | iOS 17.0, current SDK | Android minSdk 29 keeps 2019 handsets; 17 reaches 2018 iPhones and keeps Observation, which the model is built on |
| UI framework | SwiftUI, every screen; rotates | The original is custom Compose over one embossed key kit; nothing uses platform chrome UIKit would do better |
| The record | One value type per Kotlin data class, enum raw values are the Kotlin names, field order is the Kotlin declaration order | The JSON on disk and in the archive is the Android file byte for byte, so a backup restores across phones |
| JSON | An ordered `JSON` tree and one writer per type with the Android `@EncodeDefault(NEVER)` marks; kotlinx's compact form and escape table; reading through JSONSerialization with map order recovered from the text | Foundation's encoders order keys by hash or alphabetically; the fingerprint hashes the text, so the order is part of the contract |
| Fingerprint | SHA-256 over the canonical text plus every photo and ink hash, labels sorted by UTF-16 units | `LegacyCompatTests` pins the Android suite's own golden hex: a record signed on either phone verifies on the other |
| Store | JSON files under Application Support, photos and ink beside them, excluded from backup, written through a scratch file and a POSIX rename | filesDir's iOS shape, and the manifest's allowBackup=false |
| Archive | Own ZIP writer and reader (raw DEFLATE through Compression, CRC-32 table), the manifest and the name rules as on Android | iOS has no public ZIP API and the archive has to be read by java.util.zip and read from it; the reader trusts the central directory because Java writes data descriptors |
| Archive cipher | The Android envelope byte for byte: LIMENSAFE, version, salt, IV, PBKDF2-HMAC-SHA256 at 210,000 rounds, AES-256-GCM with the header as associated data; GCM assembled from CommonCrypto's AES-CTR and a GHASH written here so it streams, the multiply through Shoup's byte tables and the associated data padded to its block as the standard says. The plaintext ZIP is staged in the cache, never beside the output. The password is optional, and without one the export is the plain ZIP the legacy reader already took | CryptoKit seals a whole Data and a backup can be most of a phone's photographs; `ArchiveTests` checks the stream against CryptoKit at nine associated-data lengths including the envelope's 38, because a 16-byte test AAD had hidden a dropped final block for a whole release: the tag was not Java's, and an archive made on either phone would not have opened on the other. Documents is in Files, so a plaintext copy staged there was readable for the export's duration and for good after a kill. An unprotected archive needs no new reader and no new version, and the screen says in the warning colour which the person chose |
| Phone numbers | libphonenumber's metadata (Apache 2.0, pinned v9.0.34, the Android build's version) reduced by `tools/phones.py` to a bundled JSON; parsing, national prefix stripping, per-type patterns and lengths, E.164 and the national example written in `InternationalPhone` | The platform has no number validation and the Android tests name exact numbers and formats |
| Address lookup | An ephemeral URLSession to swisstopo's SearchServer, the same label regex | The one network call the app makes, only while the person asks; ephemeral so the typed address and the reply never reach the shared URL cache on disk |
| Strings | `ui/Strings.kt` converted by `tools/strings.py` into `Str.swift`: a `val` becomes a computed property, a `fun` over an enum a `switch`, templates become interpolation | Nothing retyped: 339 declarations in five languages reach the phone from the Kotlin class, and a misspelt name is a compile error. The generator knows two body shapes, `when` over an enum and `if (param == Enum.CASE) a else b`, and stops on anything else rather than guessing |
| Enum case names | The Kotlin name with its leading capitals lowered (`Tenant` to `tenant`, `WCSeat` to `wcSeat`, `AG` to `ag`), one rule in the generator and the model alike | The generated strings and the hand-written model have to agree without a table |
| PDF | UIGraphicsPDFRenderer's CGContext, an A4 page scaled so the Android 1240 by 1754 sheet fills it, every measurement in the Android units, system sans and Menlo for the mono; the rule-snapshot line cited per canton, the RULV named on Vaud records only | The same layout at the same proportions to a tenth of a percent, and a print at 100 percent is the size it was meant to be; the badge is the same 512 px mark |
| Photographs | PhotosPicker for the gallery (original bytes, no permission); UIImagePickerController for the camera, which is the one permission the app asks for, its picture written through ImageIO with the capture's own EXIF | Android used the system camera through a provider grant; iOS has no such route |
| Photo decoding | ImageIO's thumbnail path with the EXIF transform, sampled at the requested width | One upright decoder for the thumbnails and the annex, as on Android |
| Signature pad | SwiftUI Canvas with a zero-distance drag, quadratic-midpoint smoothing, a full-screen cover, alpha-box trim with 12 px of air, PNG. The ink is 9 pixels as Android's INK_WIDTH is, drawn at 9 / displayScale points and rendered at the display scale; a drag with a new start point drops a cancelled stroke | Signet's capture, with the Android pad's ink and baseline. Drawn in points on a 1x bitmap the line was three times Android's on screen and the PNG a third of its resolution; SwiftUI has no drag cancel callback, and Android's onDragCancel discards the stroke |
| Third-party notice | The repository's `NOTICE` referenced straight from `Project.swift` as an app resource, shown verbatim and unlocalized on its own screen under Data, backup and privacy | Apache-2.0 section 4(d) asks for the notice to travel with the distribution, and a second copy under Resources would drift from the first. The iOS build carries no third-party code, so the notice names only libphonenumber's metadata and the Commons flags |
| Exports | Documents/Limen through `UIFileSharingEnabled`, shown by Files as On My iPhone / Limen; the share sheet and a PDFKit preview | The iOS shape of Download/Limen; Android's Open and Share intents, one for one |
| Model | `LimenModel`, `@MainActor @Observable`, every edit through `edit`, a 400 ms debounced save, a 6 s undo, flush on the `.background` scene phase | The ViewModel line for line, with the lifecycle's ON_STOP as the scene phase. `.inactive` is not ON_STOP: Control Centre, a banner and the app switcher all pass through it, and a flush there committed the undo the moment the person glanced away |
| Navigation | Home pages and the flow held in the model; the flow trail and the back key as on Android; no system back gesture. A step arrives sliding a tenth of the width from its side while it fades, as AnimatedContent does; the departing step only fades | The Android activity swapped the home out whole when a record opened and lost the page; the model is where both survive. SwiftUI takes a departing view's transition from the render before the change, so a slide on it ran the wrong way on every reversal, and a `.modifier` transition reading the direction late never let the UI tests settle |
| Info tips | A popover under the info mark, forced to popover on the phone | Material's persistent tooltip |
| Sheets | The canton grid at the medium detent, the date and time pickers as sheets seeded and read in the device calendar (Material's picker is UTC both ways, SwiftUI's draws in the device zone, and mixing the two stored the day after the one tapped west of UTC), the country pickers as searchable lists, alerts for the confirmations and the backup password | Material's bottom sheet, date dialog, time dialog, exposed dropdown and AlertDialog |
| Dropdowns | The system `Menu` for the item catalogue, the language and the caution provider | Material's DropdownMenu |
| Haptics | Five weights through the system generators: light impact for a key, the soft impact at two intensities for a switch turning on and off, success, error. Both answers of a confirmation play the key, as Android's RoomActionKeys do | The Android five-weight contract; iOS has no TOGGLE_ON/TOGGLE_OFF constant, so the pair is the softer impact under the key's, which keeps Android's rule that a toggle feels lighter than a submission. The system honours the phone's own switch |
| Theme | Day and Night palettes hex for hex from `theme/Theme.kt`, the app's own choice in UserDefaults; system controls follow through `preferredColorScheme` | The instrument's own faces |
| Type | System face through `Font.custom(relativeTo:)` at Android's sizes; Menlo for the monospaced readouts | The one form SwiftUI scales live, which is the sp contract |
| Readable width | Every content column capped at 560 points by `View.readable()` and centred, the background left on the full window; the licences screen alone uncapped | Android's `ReadableMax`: past it a label and its value drift apart and two fields sharing a row get a hand's width of nothing between them. Above every iPhone's portrait width and below every iPad's, so a phone upright renders as it did. NOTICE is a fixed-column document that already scrolls sideways on a phone, so width is the one thing a tablet gives it |
| Icon | The seal (`limen_logo_master.xml` rewritten as SVG by `tools/marks.py`) grown to span the day plate edge to edge, written by `AppIconTests` | Taking the Android canvas's middle 72dp cut the top and bottom off a seal drawn to reach its launcher mask; iOS masks only corners, so the seal fills the square and the rim wording survives |
| Tests | The fifteen Android unit suites ported name for name into `LimenKitTests`, plus the ZIP, cipher, JSON and phone suites; `LimenTests` exports the Android instrumentation's records as real PDFs and walks the model; two XCUITest smokes with screenshots | The suite is the spec; the golden fingerprint is the cross-phone contract |
| Signing | The owner's own account (aperinger@proton.me), team KDSZB7N44K, pinned in `Project.swift`; `dev.peringer.limen` | An Individual enrollment needs no company and publishes the enrolled legal name, so the account that will hold the paid membership signs from the start |

## House rules

- SF Symbols only for control glyphs. The seal is the app's own artwork and exempt; the 26 canton flags are the public-domain data assets the Android app ships and identify a canton beside its name. No found, stock, or AI-generated images.
- Never a control that implies a capability the app lacks: the camera key says so when there is no camera, the export key is disabled on a draft, the exit key on an entry card says to finalize first.
- No em-dashes, no period ending a title or heading, never "land" as a verb for data or files. In comments and UI strings alike.
- Comments explain why: the constraint or the bug that forced the shape. Port the Android comments' reasons with the code they explain.
- Signed only as the owner's own account (aperinger@proton.me, team KDSZB7N44K), which is the one that will hold the paid membership. Never build for the device before the pin exists: an identifier registered once by a team is closed to every other, which is why the previous namespace had to be abandoned.
- One network call, the swisstopo address suggestion, and only while the person asks. One permission, the camera. Records leave the phone only as the PDF or the password-protected archive the person exports.

## Glyph map, Material to SF Symbols

| Android | SF Symbol |
|---|---|
| Add / Remove | plus / minus |
| Delete / Edit | trash / pencil |
| PhotoCamera / PhotoLibrary | camera / photo.on.rectangle |
| ArrowBack / ArrowForward | arrow.backward / arrow.forward |
| Check / Close | checkmark / xmark |
| Refresh (clear) | arrow.counterclockwise |
| Share / OpenInNew | square.and.arrow.up / arrow.up.forward.square |
| CalendarMonth / Schedule | calendar / clock |
| Info | info.circle |
| ArrowDropDown / KeyboardArrowRight | chevron.down / chevron.forward |
| DarkMode / the sun drawable | moon.fill / sun.max.fill |

## Platform differences accepted

- The camera asks for its permission once. Android took photographs through the system camera app with no permission of its own; iOS has no such route.
- There is no system back gesture and no predictive back animation. The back key on every screen carries the way out, as it did on Android beside the gesture.
- The Android page is 1240 by 1754 points; here it is A4 with the same drawing scaled onto it, so a print at 100 percent is the size the form was meant to be.
- The backup password dialog is a system alert with two secure fields, and the confirmations are system alerts.
- The exported files are in Documents/Limen (Files: On My iPhone / Limen), not a Downloads collection.

## The loop

```bash
make strings  # regenerate Str.swift from the Android Strings.kt
make phones   # regenerate PhoneMetadata.json from the pinned libphonenumber XML
make marks    # copy the seal, the flags and the mark from the Android repository
make gen      # tuist generate, no open
make build    # simulator build
make test     # AllTests scheme
make lint     # swiftlint
make run      # build + install + launch on the simulator
make icon     # write the app icon from the seal
make device   # build Release + install + launch on the connected iPhone
```

Debug builds accept the launch arguments `LIMEN_RESET` (clears the store and the preferences) and `LIMEN_DEMO` (seeds the Android instrumentation's draft and opens it), and the environment variable `LIMEN_LANG` (`En`, `Fr`, `De`, `It`, `Rm`). The UI smokes write their screenshots to the folder named by `TEST_RUNNER_LIMEN_SHOTS`.

Tuist resolves source and resource globs at `make gen`: a new file compiles only after regenerating. Synthesized asset accessors are off, because they would generate a `LimenColors` type over the palette.

Nothing is reported done until it builds in Release and runs on the owner's physical iPhone, with screenshots for anything visual. Git belongs to the owner: never commit or push; end each piece of work with paste-ready `cd`, `git add`, `git commit -m` and `git push` commands as one line, one-line message, no trailing period, no attribution.

The knowledge base entry for this port lives in the vault: `/Users/aperi/DEV/vault/apple/limen.md`.
