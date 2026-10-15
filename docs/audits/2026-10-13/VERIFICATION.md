# Verification and release handoff

This report was written on 14 October 2026 and completed on 15 October 2026; the completion pass is the final section, and its results supersede any 14 October claim they contradict. [IMPLEMENTATION.md](IMPLEMENTATION.md) maps F01–F28 and Android parity; [DOMAIN-REVIEW.md](DOMAIN-REVIEW.md) records independent integration findings. Earlier intermediate logs do not certify later source changes.

## Environment and isolation

- Swift repository base: `12324623dc427ca92ca5342af9b7177c331ed394`.
- Read-only Android reference: `d81796d07ada38aa6e7955d31cf297fe02cac010`; baseline `eb5c03800a9e749155db718136c9418a58c0d11c` retained separately. Android working tree remains clean.
- Xcode 27.0 (27A266a); Swift 6 complete concurrency checking; deployment target iOS 17.0.
- Core/app unit simulator: iPhone 17 Pro, iOS 26.5, `6F9172CC-DF86-4F05-9EB3-42E8E287668F`.
- Main UI simulator: iPhone 18 Pro, iOS 27, `CDF6919D-01E4-44D4-84F9-AF3CF5BFB1CA`.
- Connected physical device: iPhone 17, iOS 26.6.2 (23G90), UDID `00008150-001074183A7B401C`, CoreDevice `D5A6144A-6100-5A25-90E7-898D11325105`.
- Debug bundle `dev.peringer.limen.audit` uses a separate container. Release uses `dev.peringer.limen`, team `KDSZB7N44K`, version 1.2.0 (5). Reset/fixture arguments are compiled only in Debug and additionally require the audit bundle identity.

The latest physical preflight (`/tmp/limen-phone-udid-before.json`, `/tmp/limen-before-launch.json`) reports no installed production bundle. Launch fails with “requested application ... is not installed”. This differs from the earlier session preflight reporting 1.1.2 (4). No uninstall/reset of production was executed by this work. An existing-production-record preservation claim cannot be made from this environment; a new install and isolated synthetic device workflow can be verified.

## Executed checks

| Check | Evidence/result |
|---|---|
| Deterministic generators | 26 constructors, 243 fields; 386 string declarations, two iOS path overrides; three Python parser tests pass. `/tmp/limen-generation-final.log` |
| Core tests | 144 tests in 20 suites pass on iOS 26.5. Latest combined run: [final-unit-all.log](evidence/final-unit-all.log), `/tmp/limen-final-unit-all.xcresult` |
| App/model/bundle integration | 25 Swift tests in five suites plus four XCTest bundle checks pass in the same combined run. Includes the PDF raster correction, queued-consent regression and deterministic asynchronous photo-intake ownership tests |
| Bidirectional archive exchange | Actual Android JVM sources read Swift plain/encrypted archives; Swift reads the Java-returned archives. See [CROSS-PLATFORM.md](CROSS-PLATFORM.md) |
| Static checks | SwiftLint and `git diff --check` pass at the recorded checkpoint; final generator/lint checkpoint after application-source changes is recorded in [generation.log](evidence/generation.log) and [lint.log](evidence/lint.log) |

Core coverage includes strict unsupported/null/type/enum/overflow/nesting boundaries, legacy fingerprint preservation, all-field current JVM vectors, authenticated encrypted archive failures and bounds, scoped evidence/export repair, stale/frozen writes, actual pixel orientation across all eight EXIF cases, HEIC original-byte preservation and rotated sampling width.

App integration covers concurrent delivery/export metadata, switching and deleting an originating record during export, same-ID replacement with a different fingerprint, retryable first-save failure, sequence monotonicity through undo/consent, durable cleared reservations, stale pre-sign preview rejection, decoded TIFF MIME/suffix preservation, seeded access-device inventory, all five document languages and three participant roles. Photo-intake barriers cover switching, deletion, amendment and finalization before attachment, preservation of another operation's private capture, and exact original bytes/hash with distinct gallery-intake metadata. The combined run passed all 173 checks.

## Visual and runtime findings

The first post-integration PDF pixel inspection found vertically inverted text despite passing PDF text-extraction checks. The redundant transform is corrected. Seven export tests now pass, including an asymmetric-glyph pixel regression and long-token width checks. All 20 pages of the regenerated five-language samples were inspected. [DOCUMENT-REVIEW.md](DOCUMENT-REVIEW.md) records A4 metrics, computed physical font sizes, HTML structure and visual limits. The queued-consent/sequence regression also passed in the focused eight-test model rerun ([final-consent.log](evidence/final-consent.log)).

UI runs have exposed and corrected undersized input hit regions, role-choice audit contrast inference, obscured starter controls, keyboard dismissal, reusable identity leakage between isolated test launches, and offscreen test-driver targeting. Original failed audit logs and later results must remain distinguishable. A screenshot alone is not a complete VoiceOver, Switch Control or hardware-keyboard audit.

The full private-landlord entry, final document, seeded exit, fresh inspection and second final document passed (178.393 seconds). The agency standalone exit and subsequent amendment passed (221.004 seconds). Each uses actual UI entry and drawn test signatures. These remain separate from the five-language walks, whose latter half uses the explicitly synthetic demonstration draft. [RUNTIME-BOUNDARIES.md](RUNTIME-BOUNDARIES.md) records observed Files cancellation, camera-denial recovery and unsuccessful authentication without persisting an unusable library gate.

## Remaining external validation

Professional Swiss tenancy review, native Romansh review, and representative assistive-technology/usability sessions are outside engineering test results. [LEGAL-MAPPING.md](LEGAL-MAPPING.md) and [MARKET-AND-RESEARCH.md](MARKET-AND-RESEARCH.md) preserve the source scope and proposed research without invented participant results.

Only iOS 26.5 and 27 runtimes are installed; iOS 17 deployment compatibility is compile-target evidence, not an executed minimum-runtime test. The JVM compatibility run is not a physical Android handset/HEIC UI test. A swisstopo opt-in packet capture and service-retention review remain separate from source inspection. Disk-filling the owner's production device and destructive interruption tests were not performed.

No Git commit/push, App Store/TestFlight submission, production website edit, vault write, price/country/account change or tester message was performed.

## Release artifact

The final Release archive and local IPA export succeeded after the last application-source accessibility correction. The source-file hash manifest is retained beside the artifact metadata; later test-driver/documentation changes do not alter the app payload. No upload destination was selected. The built and IPA-extracted bundles both report `dev.peringer.limen`, version **1.2.0 (5)**, minimum iOS 17.0 and all five localizations. Strict recursive code-signature verification passed for both.

- Archive: `/Users/aperi/DEV/SWIFT/limen/DD-release/Limen-1.2.0-5-final.xcarchive`
- IPA: `/Users/aperi/DEV/SWIFT/limen/DD-release/export-final/Limen.ipa`
- Verified install payload: `DD-release/export-final/verified/Payload/Limen.app`, extracted directly from that IPA
- IPA SHA-256: `c7b5cc731c455b9b2fe6bda79fb8a189dd753f49ffb633b8ae790ff155661698`
- Signing: **Apple Development**, team `KDSZB7N44K`, `get-task-allow = true`, authorized phone listed in the profile. Export method `debugging`; this is a development-installable artifact, not App Store/ad hoc distribution evidence. Profile expires 30 September 2027.

[Archive metadata](evidence/archive-metadata.json), [archive log](evidence/release-archive.log) and [IPA export log](evidence/release-export.log) retain the verifiable facts. The first Debug test build had a missing generated provisioning-profile file; the normal automatic-provisioning retry succeeded with the same owner team.

The first physical UI run did not execute test assertions: iOS requested the phone passcode for “XCTest — Enable UI Automation”, and the runner timed out. The credential is to be entered directly on the device by its owner. [That run's log](evidence/physical-ui-awaiting-passcode.log) is retained as an environment gate, not an application failure or a passed device test. The owner subsequently enabled automation. The real iPhone empty-form journey then passed in 101.188 seconds, including two drawn test signatures, finalization and an opened PDF. Physical camera/Files interruption checks are tracked separately; their initial background-driver failures do not negate that journey or count as passes.

## Current visible-workflow evidence

The empty tenant-entry UI journey passed on the main simulator: entered facts from blank fields, applicable checks, inspection, full preview, two actual drawn test signatures, finalization, export and opened PDF (118.293 seconds). This is a scripted acceptance test, not a human task-time measurement. The initial deeper audit subsequently identified further header/control sizing issues, so this early success does not by itself certify every later screen/style.

All five default-language walks passed through landing, actor/kind form, privacy/licences, dossier/canton, inspection, complete preview, signatures and actual saved ink. EN/FR/DE/IT/RM elapsed times were 77.756/72.972/75.871/70.512/70.0 seconds. The unfiltered English landing/form accessibility audit passed without exclusions. See [ui-default-languages.log](evidence/ui-default-languages.log).

The small iPhone SE (3rd generation), iOS 26.5, passed the English largest-accessibility-type full walk (175.279 seconds); the iPad Pro 13-inch (M5) passed German Large (101.650 seconds). Evidence: [small-largest](evidence/ui-small-largest.log), [tablet-German-large](evidence/ui-tablet-german-large.log). A failed initial small run was corrected by revealing the lazily created canton before asserting its existence; no absent canton was hidden by a test skip.

The first IPA payload was installed successfully and device app enumeration confirms 1.2.0 (5). Further measured accessibility fixes require rebuilding/reinstalling the final payload; this initial installation is retained as intermediate evidence only.

## Completion pass, 15 October 2026

The 14 October results above were treated as historical evidence and re-executed where the tree could still change the outcome. Everything in this section ran on 15 October between 21:18 and 22:11 Europe/Zurich, on the same Xcode 27.0 (27A266a), against the uncommitted working tree based on `12324623dc427ca92ca5342af9b7177c331ed394`. Logs and screenshots are in [evidence/ui-2026-10-15](evidence/ui-2026-10-15/) and [evidence/physical-2026-10-15](evidence/physical-2026-10-15/); result bundles stayed in the session scratchpad.

### References and environment

- The local Android reference is still `d81796d07ada38aa6e7955d31cf297fe02cac010` (1.2.0, versionCode 5). **`origin/main` has moved three commits to `91b0103`, Android 1.2.2, versionCode 7**, which strips the audit-era forms. It was fetched and not pulled: this ledger is verified against the reference it names, and the newer head belongs to the separate simplification request in `_scratch/MACBOOK-IOS-SIMPLIFICATION-PROMPT.txt`.
- Simulators: iPhone 17 Pro / iOS 26.5 `6F9172CC-DF86-4F05-9EB3-42E8E287668F`; iPhone 18 Pro / iOS 27 `CDF6919D-01E4-44D4-84F9-AF3CF5BFB1CA`; the SE-class "Limen Audit Small iPhone" / iOS 26.5 `48BEE103-20ED-422E-80F7-101A4058AB0A`.
- Physical device: iPhone 17 (iPhone18,3), iOS 26.6.2 (23G90), UDID `00008150-001074183A7B401C`, developer mode enabled, paired and connected throughout. **At the start of the pass no Limen bundle of any identity was installed on it**, so there were no production records to preserve and none were touched.

### Static and generated checks

`LIMEN_ANDROID=/Users/aperi/DEV/ANDROID/limen make check-generated`: 26 constructors and 243 fields, 386 string declarations (339 core, 47 extensions) with two iOS overrides, three Python parser tests, all passing. `swiftlint lint` exit 0 over the whole tree, before and after the day's edits. `git diff --check` clean. `tuist generate` and a Debug simulator build succeeded with one warning, the usual AppIntents metadata notice.

### Unit tests

`AllTests` with `-only-testing:LimenKitTests -only-testing:LimenTests` on the iPhone 17 Pro / iOS 26.5 simulator: **144 LimenKit tests in 20 suites, 25 app tests in 5 suites, 4 bundle XCTest tests, TEST SUCCEEDED**, the same counts as 14 October. The run includes `CrossPlatformTests` replaying the committed JVM return fixtures; the Java direction itself was not re-executed on 15 October, so the JVM evidence stays dated 14 October. Log: [unit-kit-app-bundle.log](evidence/ui-2026-10-15/unit-kit-app-bundle.log).

### Release artifact, rebuilt twice

The 14 October IPA (`c7b5cc73…`) was built at 00:59 and two application sources changed after it, `SignPad.swift` at 01:11 and `DataPrivacyScreen.swift` at 01:12, so it did not match the tree; the source manifest confirms exactly those two differences. A fresh archive was made at 21:22, again at 21:50 after the role-row change below, at 21:55 after the Field change, and finally at 22:09 after the Field's responder-chain line; each was exported, installed on the phone and smoked. The final artifact set:

| Item | Value |
|---|---|
| Archive | `DD-release/Limen-1.2.0-5-current.xcarchive` |
| Bundle | `dev.peringer.limen` 1.2.0 (5), MinimumOSVersion 17.0, `CFBundleLocalizations` en fr de it rm, five `.lproj` folders with localized camera and Face ID purpose strings, no `ITSAppUsesNonExemptEncryption` key |
| Signing | `Apple Distribution` is not used for the installed build; the archive is signed by the owner's team `KDSZB7N44K`, `codesign --verify --deep --strict` valid, entitlements `application-identifier`, `team-identifier` and `get-task-allow = true` |
| Profile | `iOS Team Provisioning Profile: dev.peringer.limen`, expires 2027-09-30, the phone's UDID listed |
| Development IPA | `DD-release/export-current-dev/Limen.ipa`, method `debugging`, SHA-256 `b745635bc54815d68d373cbe6e978e1bca8fe597e6645a731aaae578b5a5294f`, installed on the phone |
| Distribution IPA | `DD-release/export-current-store/Limen.ipa`, method `app-store-connect`, SHA-256 `6b216b0fca92e9ffb364da4e7c3f5612cd3f501382b222148240077790ac00c6`, signed without `get-task-allow`, **not uploaded, not validated against App Store Connect** |
| Source manifest | [release-source-manifest-2026-10-15.json](evidence/release-source-manifest-2026-10-15.json), 131 application sources, written from the tree the final archive was built from |
| Metadata | [archive-metadata-2026-10-15.json](evidence/archive-metadata-2026-10-15.json) |

The development IPA is a development-installable artifact. A distribution-signed IPA exists only to show the export path works; nothing was sent to Apple.

### Physical iPhone

- The development IPA was installed with `devicectl` (21:26, 21:52, 21:56 and finally 22:10:50, one install per artifact) and enumerates as `dev.peringer.limen` 1.2.0 (5).
- `InstalledReleaseSmokeTest/testInstalledReleaseReadOnlyFlow` against that installed production bundle, opted in with `LIMEN_RELEASE_SMOKE=1`: **passed on each of the four artifacts, 7.398 s, 7.478 s, 7.458 s and 7.454 s**. Landing, empty new-session form, privacy page and return to the landing, four screenshots with provenance in [physical-2026-10-15](evidence/physical-2026-10-15/).
- `ParityJourneyTest/testEmptyFormToDrawnSignaturesAndOpenedDocument` in the isolated audit bundle built from the current tree: **passed, 103.022 s**. Typed facts from blank fields, inspection, two drawn signatures, finalization, export and the opened A4 document; the screenshots show both signers recorded as signed before finalization and the finalized PDF with its fingerprint and the frozen `ch-tenancy-2026.2` overlay.
- The 14 October physical camera-denial and Files-cancellation checks were not re-executed.

### Simulator UI runs

| Run | Simulator | Result |
|---|---|---|
| Lifecycles: tenant blank-form journey, agency standalone exit then amendment, invalid-date relaunch | iPhone 17 Pro / iOS 26.5 | passed, 79.9 s / 119.3 s / 15.7 s |
| Private landlord entry then seeded exit | iPhone 17 Pro / iOS 26.5, iPhone 18 Pro / iOS 27, and the phone | **failed on all three, in every variant tried**; the entry half (full preview, two signatures, opened PDF) completes each time and the seeded exit fails at the legal note's keyboard, see below |
| `SmokeTest`, both cases | iPhone 17 Pro / iOS 26.5 | passed, 34.9 s and 40.9 s |
| `RuntimeBoundaryTests`: camera refusal, Files cancellation, failed authentication | iPhone 17 Pro / iOS 26.5 | passed, 23.8 s / 55.1 s / 20.7 s |
| `PhotoViewerJourneyTests`, three cases, after `tools/fixtures/photo-viewer.py` seeded the reserved records | small iPhone / iOS 26.5 | **passed, 23.2 s / 22.9 s / 20.7 s**, twelve screenshots in [photo-viewer](evidence/ui-2026-10-15/photo-viewer/). This is the first execution of these cases; the 14 October ledger listed F14 as pending UI evidence |
| `LanguageWalkTest` default size, five languages | iPhone 18 Pro / iOS 27 | passed, EN 83.8 s, FR 86.9 s, DE 85.4 s, IT 84.9 s, RM 84.3 s |
| `LanguageWalkTest` largest accessibility size, five languages | iPhone 18 Pro / iOS 27 | **passed, EN 217.7 s, FR 207.5 s, DE 236.7 s, IT 211.4 s, RM 305.0 s**. The 14 October report had only English complete |
| `AccessibilityJourneyTest/testMainHandoverScreens` | iPhone 17 Pro / iOS 26.5 | passed twice, 16.6 s and 16.5 s |

Not re-run on 15 October: the iPad matrix, the small-screen landscape and largest walks, the store shots, and the physical interruption checks. Their 14 October evidence stands as dated evidence of an identical source state for those screens, except where the role row changed, see below.

### The accessibility audits, what they do and do not establish

The unfiltered `performAccessibilityAudit` cases on the new-session form (`AccessibilityJourneyTest`, the five initial-viewport and four visible-control cases) did not behave as the 14 October report describes. On the iPhone 17 Pro simulator, where the four visible-control cases had passed on the 14th, all eight large-type cases failed twice on the 15th, once under heavy load and once on a quiet machine. On the small simulator the same code failed `testEnglishDefault` and passed `testFrenchLarge`, the reverse of the first simulator.

Two causes were separated:

1. **Simulator state.** The iPhone 17 Pro simulator had accumulated German and French keyboards from earlier runs; the other two simulators carried none. After `defaults delete -g AppleKeyboards` and a reboot, the four visible-control cases passed on it in one run (French 9.3 s, German 9.3 s, Italian 9.3 s, Romansh 9.1 s). The code had not changed.
2. **The audit's own sampling.** The driver now passes an issue handler that logs each issue's `detailedDescription`, element and frame and returns `false`, so the verdict is unchanged and the log says what failed. With that in place, the logged findings on the small simulator were: elements whose frame ends below the 667-point window or sits under the pinned footer (`Address` at y 637, `Art der Übergabe` ending at 687, `District` at 657), the page title under the mast after a scroll (y 52), and elements fully inside the viewport whose colours compute well above the threshold. From the day palette: field label `inkDim` #5B6472 on `input` #EFF1F4 is **5.29:1**, section label on `plateRaised` is **4.92:1**, disabled key text on its fill is **5.08:1**, key text on `input` is 14.92:1, white on `action` is 12.64:1. The three largest-type initial-viewport cases that still fail on the iPhone 17 Pro each report one `Contrast failed` with no element at all.

So the contrast verdicts of these cases are not evidence of a contrast defect, and their passes are not evidence of its absence. They remain in the suite unfiltered, as the 14 October report intended, but the 15 October reading is that they measure clipping and sampling, not colour. A human review at large text sizes is still the open gate the 14 October report named.

One finding in that log was real. At the largest accessibility size on a 375-point screen, the three-way role row gave each option about 100 points and the audit reported **`Text clipped` on "Conduttore/trice"**. `EqualChoiceRow` now stacks its options vertically at accessibility type sizes, which also applies to the handover-kind row and the one other call site in the same form. After the change the Italian largest-type initial audit passed outright on the small simulator (7.9 s, zero `Text clipped` findings) where it had failed before. The archive was rebuilt after it, and again after the Field change.

### Landlord lifecycle on iOS 26.5

`testPrivateLandlordEntryThenSeededExit` completed the entry (full preview, two signatures, opened PDF) and failed in the seeded exit's dossier on the iPhone 17 Pro / iOS 26.5 simulator, three times, with the keyboard reset included: after typing the legal note into the multi-line `legal-note-LeaseAndLocalTiming` field and tapping Done twice, the keyboard was still on screen at y 583 and the driver's `reveal` read a stale snapshot while the scroll view re-laid out. The 14 October pass of this case was on the iPhone 18 Pro / iOS 27 simulator. The case was then run with three driver variants and two application variants, on both simulators and on the phone, and failed at the same step every time: the driver reaches the seeded exit, confirms the lease-and-local-timing check, types the explanatory note into the multi-line field, ends editing, and its wait for the keyboard to leave times out. Ending editing by the keyboard's own key, by dragging the list, by Return, and finally by the app's new Done above the keyboard, backed by `resignFirstResponder`, made no difference to that wait. The accessibility hierarchy at failure holds a keyboard frame in some runs and none in others, so whether the keyboard is still displayed or merely still reported was not isolated. The 14 October pass of this case ran on iOS 27 at 00:50 with an earlier driver and screens, before that day's last driver edits.

What this does and does not establish: the entry lifecycle, the tenant journey, the agency standalone exit with its amendment and the invalid-date relaunch all pass on both runtimes, and the first two also on the phone; the seeded-exit journey after a typed legal note is **not demonstrated by automation on any device**, and the keyboard behaviour on that note is an open item for a hand check. The dossier's `scrollDismissesKeyboard(.interactively)` is the way a person leaves that keyboard today; the toolbar Done added on the 15th is implemented but its effect was not confirmed by automation. The simplification request reworks this dossier, which is where the item should be settled.

### Changes made on 15 October

- `Limen/Sources/Home/NewSessionScreen.swift`: `EqualChoiceRow` stacks at accessibility type sizes.
- `Limen/Sources/Kit/Field.swift`: a multi-line field's Return key reads return instead of Done, and the app's Done sits above the keyboard, clearing focus and resigning the first responder. Implemented; not confirmed by automation, see the landlord section.
- `LimenUITests/Sources/ParityJourneyTest.swift`: `performLoggedAudit` logs each audit issue without suppressing it; `reveal` waits for a keyboard to leave before measuring; `finishEditing` ends text entry by the app's Done or Return rather than by a keyboard key labelled Done.
- Evidence files added under `evidence/ui-2026-10-15/`, `evidence/physical-2026-10-15/`, and the two dated manifest and metadata files.

No other source, string, resource, generator or fixture changed. `make check-generated`, SwiftLint and `git diff --check` pass after the edits.
