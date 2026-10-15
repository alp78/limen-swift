# iPad language and Dynamic Type execution

Executed 14 October 2026 on the **iPad Pro 13-inch (M5), iOS 26.5 simulator**, UUID `1832F00F-BAD8-43C6-8246-4E23D1763BFD`, using `DD-tablet` and `LimenUITests/LanguageWalkTest`. A final focused signature check also used iPhone 17 / iOS 26.5, UUID `7685239C-7EC2-48B9-ADFD-66CC3C649D9A`, with `DD-signpad`. This report covers those assigned checks. Other devices, automated accessibility audits and physical-device results have separate reports.

The iPad ran full screen at **1032 × 1376 points portrait** and **1376 × 1032 points landscape**, on a 2× display. `simctl io enumerate` reported 2064 × 2752 native pixels and landscape orientation. Final full-screen landscape PNGs retain that raw pixel size with orientation 8, displaying as 2752 × 2064 pixels; raw PNG dimensions alone do not establish interface orientation. [Display metadata](evidence/tablet-layout/display-metadata.json) records this distinction. The post-fix test explicitly logged and asserted the actual app frame after each launch. No iPad split-window size was exercised.

## Results and build provenance

The initial matrix built the app at **00:50:16 CEST**, after header wrapping and the solid button-text background changes. A final intrinsic button-label sizing/tracking adjustment landed during that run (`KeySurface.swift`, 00:55:24). Its results therefore are not represented as a complete five-language run of that later revision.

| Test | Size and orientation | Result | Duration |
|---|---|---|---:|
| `testEnglishLarge` | XXXL, portrait | Pass | 78.346 s |
| `testFrenchLarge` | XXXL, portrait | Pass | 103.479 s |
| `testGermanLarge` | XXXL, portrait | Pass | 102.627 s |
| `testItalianLarge` | XXXL, portrait | Pass | 101.436 s |
| `testRomanshLarge` | XXXL, portrait | Pass | 101.805 s |
| `testRomanshLargestAccessibilityLandscape` | Accessibility XXXL, landscape | Pass | 183.596 s |

**Six tests passed, zero failures, 671.289 seconds.** The [complete matrix log](evidence/tablet-dynamic-matrix.log) preserves the command and results. Result bundle: `/tmp/limen-final-tablet-matrix.xcresult`.

The button-layout recheck rebuilt both app and tests, with the runner linked at **01:02:04**, including the 00:55:24 button adjustment, viewport/distance-aware coordinate scrolling and `XCUIScreen.main.screenshot()` capture. German XXXL portrait passed in **65.821 seconds** and Romansh Accessibility XXXL landscape passed in **143.429 seconds**: **two passes, zero failures, 209.251 seconds**. See the [recheck log](evidence/tablet-final-style.log), result bundle `/tmp/limen-tablet-final-style.xcresult`, and the 30 original captures plus six overviews in `evidence/tablet-layout/final`. This recheck exposed the signature-header defect described below; passing navigation alone did not establish an unclipped layout.

Both commands use `xcodebuild -workspace Limen.xcworkspace -scheme AllTests`, the destination UUID above, `-derivedDataPath ./DD-tablet -parallel-testing-enabled NO -collect-test-diagnostics never`, and the named `-only-testing:LimenUITests/LanguageWalkTest/...` methods. The exact command is retained at the top of each run log.

## What the walks and screenshots establish

Every walk opens the landing screen, agency starter, entry/exit choices, optional contact/address controls, privacy/controller screen and bundled licences. It then launches a synthetic draft and navigates the hub, inspection, objects, dossier, canton picker, Zurich legal overlay, review, complete document preview acknowledgement, signature pad and saved ink status. This checks those visible actions and assertions; it is not a complete finalized-record, delivery or backup lifecycle.

All 70 portrait captures were inspected in two overview sheets per language, with selected forms, legal text and ink screens examined at full resolution. Portrait overview links: [EN 1–7](evidence/tablet-layout/matrix/overview-en-UICTContentSizeCategoryXXXL-1.png), [EN 8–14](evidence/tablet-layout/matrix/overview-en-UICTContentSizeCategoryXXXL-8.png), [FR 1–7](evidence/tablet-layout/matrix/overview-fr-UICTContentSizeCategoryXXXL-1.png), [FR 8–14](evidence/tablet-layout/matrix/overview-fr-UICTContentSizeCategoryXXXL-8.png), [DE 1–7](evidence/tablet-layout/matrix/overview-de-UICTContentSizeCategoryXXXL-1.png), [DE 8–14](evidence/tablet-layout/matrix/overview-de-UICTContentSizeCategoryXXXL-8.png), [IT 1–7](evidence/tablet-layout/matrix/overview-it-UICTContentSizeCategoryXXXL-1.png), [IT 8–14](evidence/tablet-layout/matrix/overview-it-UICTContentSizeCategoryXXXL-8.png), [RM 1–7](evidence/tablet-layout/matrix/overview-rm-UICTContentSizeCategoryXXXL-1.png), [RM 8–14](evidence/tablet-layout/matrix/overview-rm-UICTContentSizeCategoryXXXL-8.png).

In those samples, long legal sentences and agency guidance wrap, named controls remain distinct, and ink can be drawn and saved. The [French](evidence/tablet-layout/matrix/fr-UICTContentSizeCategoryXXXL-02-new-session.png) and [Romansh](evidence/tablet-layout/matrix/rm-UICTContentSizeCategoryXXXL-02-new-session.png) street-field placeholders shorten; the full address guidance remains above those fields. This is not a claim that every placeholder is untruncated.

The first landscape run's 14 captures were inspected and exposed a test artifact: `app.screenshot()` produced rotated/cropped images with black regions despite the successful walk. A contemporaneous `simctl io screenshot` showed the landscape screen correctly. Those captures are not used as evidence of a correct final landscape layout; the final rerun uses the corrected full-screen capture method.

## Signature-header defect and verified correction

The corrected landscape capture showed a real layout defect: `SignPad` capped a separately scrollable header at 160 points, cutting the signer name and leaving the signature purpose out of the initial view despite available space. The old capture is preserved in [the button-layout recheck](evidence/tablet-layout/final/rm-UICTContentSizeCategoryAccessibilityXXXL-13-ink.png).

`SignPad` now gives the title and purpose their natural height and puts them with a full-width 2.1:1 drawing surface in one scrollable content region. The actions remain pinned below it. This uses available tablet space and lets a shorter phone window scroll to the pad without compressing or truncating the text. The test checks the exact purpose label, captures it, scrolls to the pad as needed, draws and saves ink, and verifies the signed state.

| Post-fix check | Measured app frame | Result | Evidence |
|---|---|---|---|
| Romansh Accessibility XXXL complete iPad landscape walk | 1376 × 1032 pt; landscape assertion passed on both launches | Pass, 149.074 s | [Log](evidence/tablet-signpad.log), `/tmp/limen-tablet-signpad.xcresult` |
| Romansh Accessibility XXXL focused iPhone signature path | 402 × 874 pt; portrait assertion passed | Pass, 79.641 s | [Log](evidence/phone-signpad.log), `/tmp/limen-phone-signpad.xcresult` |

The final full-size images were inspected. On iPad the [complete signer and purpose](evidence/tablet-layout/signature-recheck/tablet/rm-UICTContentSizeCategoryAccessibilityXXXL-12a-signature-purpose.png) and [ink with pinned actions](evidence/tablet-layout/signature-recheck/tablet/rm-UICTContentSizeCategoryAccessibilityXXXL-13-ink.png) fit together. On iPhone the [complete text](evidence/tablet-layout/signature-recheck/phone/rm-UICTContentSizeCategoryAccessibilityXXXL-signature-only-12a-signature-purpose.png) flows naturally and the user can [scroll to the full drawing surface](evidence/tablet-layout/signature-recheck/phone/rm-UICTContentSizeCategoryAccessibilityXXXL-signature-only-13-ink.png); long Romansh words wrap across lines rather than disappearing into an ellipsis. All 22 post-fix captures are retained with filename/hash indexes in the `signature-recheck/tablet` and `signature-recheck/phone` directories. SwiftLint and `git diff --check` passed for the source/test change.

No human VoiceOver, Switch Control, hardware keyboard, low-vision comprehension or native-language assessment was performed by this subset. Screenshot review and passing XCTest actions do not establish assistive-technology conformance. The largest-text checks here are Romansh landscape and a focused Romansh phone signature path; full largest-text portrait walks in other languages belong to the separate phone run.
