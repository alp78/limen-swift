# Limen iPhone, the App Store screenshots from the Android scene, 26 October 2026

Written 26 October 2026 against Swift commit `934219f` plus the record commit of the 1.2.7 upload, and Android `origin/main` at `5e92a57`, the commit after `1b1b5ed` that carries the Play store walk. The request is `_scratch/prompts/ios-store-shots-1.2.7.md`: both listings still showed the September screenshots, the 1.1 interface and a record without a photograph; the Play listing was replaced on 25 October from a seeded record with three photographed defects, and the App Store is to show the same record, the same eight shots, the same photographs. Nothing in the Android repository or on the website was modified.

## What changed

**The scene is Android's.** `StoreScene.swift` keeps its five scenes (Zug, Lausanne, Bern, Lugano, Ilanz) and adds what `StoreScene.kt` seeds: the representative's `authority` (the management mandate, in the five languages), and three defects in place of the paint chip, each with one photograph: the kitchen wall's water stain, which the tenant disputes with the existing comment; the hole in a bathroom tile, charged to the tenant, fixed by the tenant for CHF 180; the scratches in the living room's parquet, normal wear. `StoreScene.seed(into:lang:)` builds the record in the kit, the one function the app's `seedStoreScene` and the tests share, and mirrors Android's seed field for field: parties with the stable ids `tenant` and `landlord`, the agency and the authority on the landlord, the five rooms inspected, the three defects on walls, tiles and floor, Contract and Keys as the dossier with `dossierChosen`, three apartment keys and one mailbox key all transferred, every requirement of the canton's overlay confirmed. The walk that had failed in every language since the parity commit `ca3e6bc` now finalizes: the seeded landlord carried `representedBy` and no `authority`, which `partiesRecorded` refuses.

**The photographs are the kit's Debug fixtures.** The three JPEGs beside the prompt, byte for byte the files under Android's `app/src/androidTest/assets/store/`, are `LimenKit/Resources/store-scene-*.jpg`, and the LimenKit target's Release configuration sets `EXCLUDED_SOURCE_FILE_NAMES` to `store-scene-*`, so they are in the Debug framework the UI tests run against and in no shipped build, as `#if DEBUG` keeps the scene itself out. The seed copies each out of `Bundle.limenKit` into `store.photoDir(id)` under the name the app gives a capture, `<defectId>-<capturedEpochMs>-1.jpg`, hashes it with `ProtocolIntegrity.fileHash`, and lists it in both `photos` and `photoEvidence` with source camera, since the editor's thumbnail strip reads the one and the fingerprint reads both. The handover is 10 September 2026 at noon in Europe/Zurich, kept as the instant 1,789,034,400 rather than assembled from a calendar, and the photographs are taken 18, 31 and 44 minutes later, so the legends read 12:18, 12:31 and 12:44; `StoreSceneTests` checks the stamps.

**The tenant's position is seeded twice**, in the legacy `tenantResponse` and `tenantComment` Android's seed writes and the paper prints for a record with one tenant, and in the position map keyed by the tenant's id, which this port's finding editor shows for a party that has one (Android's editor shows the legacy fields for a single tenant). With one tenant the paper prints only the legacy chip, so nothing is doubled. The seed is the place for this; that an Android-made record with a stable-id tenant shows "Not stated" in this editor is a question for a later pass.

**The walk.** `StoreShotsTest` takes the eight shots in Android's order: 01 the home screen, 02 the rooms, 03 the kitchen's defect with its photograph and the tenant's position (the frame waits two seconds for the thumbnail to decode), 04 the canton overlay, 05 the review, 06 the signature pad with the agency's representative signing first, pressed through `sign-landlord` so the pad's title carries the signer, then the tenant through `sign-tenant`, the app finalizing on its own, 07 the finalized record's cover in the preview sheet, which is on the sign step one press back from the export step finalizing arrives on, and 08 the annex's first photograph page. For 08 the preview is opened on the page that carries the living room photograph's file name, which the legend prints and nothing else does: `PDFPreview` reads `LIMEN_PREVIEW_FIND` from the launch environment under the Debug identity and goes to the first page `PDFDocument.findString` returns, after the view has laid out, since a destination set before that is reset by `autoScales`. `LIMEN_PREVIEW_FIND_FROM` names the first preview of the process the page applies to, counted as the document views the process makes; the walk sets both at its one launch with 3, since the first preview is the draft the review validates and the second is shot 07's cover. The choice was the environment variable, not a swipe count: the page count is not known to the test and would change with every record. The first version relaunched the app with the variable between 07 and 08, after pressing home so the app saved its step; the simulator came back on the sign step every time, but on the iPhone the relaunch came back on the hub, whose record door opens the export step of a finalized record with no way to the sign step, so the walk now never relaunches. The walk's scroll helper asks nothing of an element before it exists and drags the tallest scroll view, the list rather than the rail above it.

**Tooling.** `tools/store-shots-check.py` checks each language's eight names and the pixel size of the device class with `sips`, since this Mac has no Pillow, and sorts the set under `<into>/<device>/<locale>/`; `tools/contact-sheet.swift` draws one sheet per device class with AppKit. The upload script, `~/.appstoreconnect/tools/upload_screenshots.py`, lives beside the API key and outside the repository: per locale and device class it clears the set, reserves each screenshot, sends its bytes to the upload operations Apple returns, commits it with its MD5, waits for Apple to process the set, writes the set's order explicitly and reads it back; with `--descriptions` it appends the credit line a CC BY 4.0 photograph asks for to the four descriptions, the lines Android's `docs/listing/store-listing.md` carries.

**The iPad's document sheet.** The first full run showed the finalized cover on the iPad in a form sheet 578 by 650 points, an A4 page at little more than half its height, cut off above the record's reference. Android shows the document in a dialog that fills the screen on a tablet as on a phone (`DocumentPreview.kt`, `usePlatformDefaultWidth = false`), so the four sheets that show a document, the record's preview, an export, a copy and a supporting document, now ask for the page sizing through `documentSizing()` in `RecordPanels.swift` on iOS 18 and later. A phone's sheet already spans the screen, and iOS 17 keeps the form sheet, having no presentation sizing to ask for. This is the one change of the pass a shipped build shows, and only on an iPad. Even at that size the cover is taller than the sheet at the width it fits, so the walk drags the iPad's cover up by the page's white margin before shot 07, which brings the reference into the frame with the whole banner still in it.

**The overlay's own note.** The canton overlay's closing field carried the label of each requirement's reason field, and on the iPad's frame two fields under one name read as one field shown twice. Android names it "Remarks · Canton overlay" (`LegalOverlayPanel.kt`), and so does the port now; the review step and the paper keep the reason label for that note, as Android's do.

**Shot 04 settled as Android settles it.** The creep toward the overlay stopped the moment its title entered at the bottom of a phone, which left the frame showing the object's fields with the overlay's heading on the last line. Android's walk scrolls the title to just under the dossier's sticky rail (`settleUnderStickyHeader`), and the port's walk now does the same: the rail's lowest chip above the title is its edge, and slow drags held at their end close the distance to twelve points, measured again after each drag.

**The photographs and their licences**

| File | Source | Author | Licence |
|---|---|---|---|
| kitchen-wall-water-stain.jpg | Wikimedia Commons, Berlin Wasserschaden lub 2025-01-19.jpg | Lukas Beck | CC BY 4.0 |
| bathroom-tile-hole.jpg | Unsplash KnZhqTdIZTA | Elias | Unsplash licence |
| living-room-parquet-scratches.jpg | Pexels 28101637 | Askara Svarga | Pexels licence |

The owner chose them on 25 October 2026, after the devices and disks held no photograph of a defect. They are listing material and test fixtures, never part of the shipped app.

## Simulators

| Device class | Simulator | Pixels | App Store display type |
|---|---|---|---|
| 6.9-inch iPhone | iPhone 17 Pro Max, iOS 26.5, `24A076E8-EB1A-4556-9761-03079E56AA42` | 1320 by 2868 | `APP_IPHONE_67` |
| 13-inch iPad | iPad Pro 13-inch (M5), iOS 26.5, `1832F00F-BAD8-43C6-8246-4E23D1763BFD` | 2064 by 2752 | `APP_IPAD_PRO_3GEN_129` |

Both with the status bar set to 09:30, charged, full Wi-Fi and four cellular bars (`xcrun simctl status_bar <udid> override --time 09:30 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4`), the clock Android's demo mode shows. Xcode 27.1.

## Verification

- `StoreShotsTest` passes in all five languages on both simulators, ten runs of 96 to 99 seconds each, in the final run of 26 October after the three changes above; the walk logs are [evidence/store-shots-walk-iphone69.log](evidence/store-shots-walk-iphone69.log) and [evidence/store-shots-walk-ipad13.log](evidence/store-shots-walk-ipad13.log).
- `tools/store-shots-check.py` found eight names per language and the device class's exact size in all 80 frames; 64 of them, the four App Store locales, were uploaded, and Romansh, which has no App Store locale, stays in the scratch set.
- The frames were read one by one before the upload: on the iPhone all eight in English, French, German and Italian, on the iPad all eight in English and 04, 06, 07 and 08 in French, German and Italian, and the rest on the contact sheets ([iPhone](evidence/store-shots-contact-iphone69.jpg), [iPad](evidence/store-shots-contact-ipad13.jpg)). Shot 03 shows the kitchen photograph's thumbnail and the tenant's disputed position with the comment; shot 06 names the agency's representative in the pad's title; shot 07 shows the cover with the LIMEN reference under the finalized pill; shot 08 shows the living room's plate, its legend, "12:44" and the file name.
- The Release build of the app for the simulator carries none of the three photographs, no `StoreScene` symbol and no `LIMEN_PREVIEW_FIND` string, against three photographs in the Debug framework: [evidence/store-shots-release-exclusion.log](evidence/store-shots-release-exclusion.log).
- `make check-generated` and `make lint` pass.
- `make test` on the iPhone 17 Pro simulator: 327 tests, 313 passed, 8 skipped, 6 failed: [evidence/store-shots-make-test.log](evidence/store-shots-make-test.log). The six are `AccessibilityJourneyTest`'s contrast samplings, the known simulator failures the 1.2.7 handoff carries and the 15 October section of `docs/audits/2026-10-13/VERIFICATION.md` explains. Two failures that handoff also carried now pass: `ParityJourneyTest` (its seeded exit had the same missing authority) and the five `StoreShotsTest` cases.
- `make device` built Release with the page-sized document sheets and the renamed note, installed it on the iPhone 17 (iOS 26.6.2) over 1.2.7 (9) and launched it.
- The English store walk on the iPhone, in two runs. The first, at 04:21, timed out "while enabling automation mode", the prompt on the phone that asks for its passcode before Xcode may drive it. The owner ran it again at 04:29 and answered it: shots 01 to 07 were taken on the iPhone 17 (1206 by 2622, kept under [shots/store-iphone17-ios26.6.2/](shots/store-iphone17-ios26.6.2/)), among them 04 with "Remarks · Canton overlay" and 07 with the finalized cover and its reference; the walk then failed at the relaunch for 08, which reopened on the hub, as the paragraph on the walk explains. The walk no longer relaunches, and passes on both store simulators in English after that change (91 and 89 seconds), shots 07 and 08 checked by eye. Xcode then asked for the Mac's password in the terminal to collect diagnostics from the phone after the failure, because Developer Mode is off on this Mac (`DevToolsSecurity -status`); nothing needs it. The walk's test bundle is built for the phone; with the phone at hand, the rerun is:

```bash
xcodebuild -workspace Limen.xcworkspace -scheme AllTests -destination 'id=00008150-001074183A7B401C' -derivedDataPath ./DD -only-testing:LimenUITests/StoreShotsTest/testStoreShotsInEnglish test-without-building && make shots
```

## Upload, 26 October 2026

`python3 -I ~/.appstoreconnect/tools/upload_screenshots.py _scratch/store-shots --descriptions`, the owner's script beside the API key, against store version 1.2.7 (`9724da24-37c6-46c5-a2f8-91cb416ffee6`) of app 6817920270. Each set was cleared, filled with its eight frames, processed by Apple, put in order and read back; then each description took the credit line Android's listing carries, byte for byte, and was read back. A separate read afterwards found every set at eight frames, all COMPLETE, from `NN-01-home` to `NN-08-photo-annex`, each description ending with its credit line, and store version 1.2.7 in Prepare for Submission with build 9 VALID, not submitted for sale. The script's log is [evidence/store-shots-upload.log](evidence/store-shots-upload.log).

| Locale | `APP_IPHONE_67` set | `APP_IPAD_PRO_3GEN_129` set |
|---|---|---|
| en-US | `206f8a36-0235-497e-b35d-5c4af7a70279` | `3f10f5e6-63e6-4240-bbb4-ef48c90cd12e` |
| fr-FR | `04790e41-5a80-456d-9610-3e534ad8aeca` | `b811e02a-1445-4c1a-882e-84637afd1868` |
| de-DE | `364be955-e58d-4748-8772-f1401b3620d1` | `d3c0e6ba-441e-4c56-8497-ac987e10cdad` |
| it | `1f021060-079c-4e47-a82c-1883cbf3a714` | `3c548ad0-9ced-43f3-b091-2a4820b6de6e` |

## Differences from the Play frames, and what was left

- The canton overlay on Android lists its sources as numbered keys, a conciliation key and the rule set's date, where this port lists each source as a link named by its host. The frame shows the port as it is; carrying Android's form over is a change to the app, not to the screenshots, and is left for a later pass.
- In French the cover's last panel ends page 1 with the fingerprint's label and carries the value to page 2 under a Continued pill, because the fingerprint's line wraps after its label and each wrapped line of a text block is a row of its own, as in Android's `Text.rows` in `Blocks.kt`. The listing's 07 frame shows the reference, which is what the frame is for; the split follows a rule this port shares with Android and is left as it is.
- The iPad's 07 frame is dragged up by the page's white margin to bring the reference in, where Android's tablet frame shows the page from its top. The banner stays whole.
- The tenant's position is seeded in both places this editor and the paper read, as the "What changed" section says.

## Git

Nothing was committed or pushed. The owner's line:

```bash
cd /Users/aperi/DEV/SWIFT/limen && git add CLAUDE.md Project.swift Limen LimenKit LimenTests LimenUITests docs tools && git commit -m "Take the App Store screenshots from Android's seeded scene: three photographed defects as Debug-only kit fixtures, the annex page reached by its text, document sheets at page size on iPad, the overlay's note named as on Android, and the listing replaced in four locales" && git push
```
