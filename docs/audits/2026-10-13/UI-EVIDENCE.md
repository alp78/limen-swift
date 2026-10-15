# Visible workflow and accessibility evidence

Recorded 14 October 2026 against the uncommitted Android 1.2 parity/audit update based on Swift commit `12324623dc427ca92ca5342af9b7177c331ed394`. These are synthetic engineering acceptance runs. Their durations are test execution times, not measured human task times. All reset/demo launches target the isolated Debug bundle `dev.peringer.limen.audit`; production records were not reset.

## Executed workflows

| Workflow | Observed result | Result bundle |
|---|---|---|
| Tenant, empty entry | Passed, 118.293 s. Enters names, object facts, canton checks, time and keys from blank fields; inspects a room; acknowledges the full document; draws both signatures; finalizes, exports and opens the PDF | `/tmp/limen-ui-parity-8.xcresult`, `ParityJourneyTest/testEmptyFormToDrawnSignaturesAndOpenedDocument` |
| Private landlord, empty entry then seeded exit | Passed, 178.393 s. Completes the entry and its PDF, starts an exit from that finalized entry, sees its baseline section, records fresh handover facts and inspection, draws fresh signatures and opens the exit PDF | `/tmp/limen-ui-lifecycles.xcresult`, `ParityJourneyTest/testPrivateLandlordEntryThenSeededExit` |
| Agency, standalone exit then amendment | Passed, 221.004 s. Keeps contractual owner, agency and representative distinct; completes the standalone exit; creates an amendment; changes the time; previews, draws fresh signatures, finalizes and opens the amended PDF | `/tmp/limen-ui-lifecycles-retry.xcresult`, `ParityJourneyTest/testAgencyStandaloneExitThenAmendment` |
| Invalid date draft | Passed, 25.141 s in the recorded retry. Invalid `31/02/2026` survives relaunch and the explicit restore action recovers the previous valid input | `/tmp/limen-ui-parity-7.xcresult`, `ParityJourneyTest/testInvalidDateSurvivesRelaunchAndHasExplicitRevert` |

The first three result bundles also contain earlier accessibility cases. A passing lifecycle case does not make its entire mixed bundle pass. Their original logs are retained in [the UI evidence directory](evidence/ui/); the final separate handover audit below supersedes the earlier audit findings on those screens. The seeded-exit screenshot records the baseline section heading. A later test-driver addition expands that section, but it is not part of the cited 178.393-second pass.

Selected originals: [tenant signatures](evidence/ui/empty-journey-signed.png), [tenant opened PDF](evidence/ui/empty-journey-opened-pdf.png), [landlord entry preview](evidence/ui/landlord-entry-full-preview.png), [seeded-exit signatures](evidence/ui/landlord-seeded-exit-signed.png), [seeded-exit PDF](evidence/ui/landlord-seeded-exit-opened-pdf.png), [agency signatures](evidence/ui/agency-standalone-exit-signed.png), [amended PDF](evidence/ui/agency-amendment-opened-pdf.png).

The existing two `SmokeTest` cases also passed on iPhone 17 Pro / iOS 26.5: landing/form/privacy and plain archive 34.835 s; seeded all-steps, drawn signature and rotation 41.136 s. The archive case asserts that empty protected-export credentials disable submission, then exercises the separate explicit plain-export confirmation. See [the log](evidence/ui/limen-ui-smoke-final.log), [protected-export prompt](evidence/ui/smoke-05-backup-password.png) and [plain-export result](evidence/ui/smoke-06-backup-unprotected.png). This smoke run preceded the small archive-picker provider-failure feedback addition; it does not simulate a failing document provider.

## Languages, sizes and orientation

The language walk opens the empty actor/kind form and optional contacts, privacy and licences, then explicitly launches a demonstration draft for inspection, objects, dossier/canton and legal checks, full preview and drawn/saved ink. It is a navigation/localization test, separate from the complete blank-form lifecycle above.

| Device / runtime | Size and orientation | Coverage / result |
|---|---|---|
| iPhone 18 Pro, iOS 27, `CDF6919D-01E4-44D4-84F9-AF3CF5BFB1CA` | Default `UICTContentSizeCategoryL`, portrait | EN/FR/DE/IT/RM all passed, respectively 77.756/72.972/75.871/70.512/69.956 s; `/tmp/limen-ui-language-default.xcresult` |
| iPhone SE (3rd generation), iOS 26.5, `48BEE103-20ED-422E-80F7-101A4058AB0A` | Largest accessibility, portrait | English passed, 175.279 s; `/tmp/limen-small-retry.xcresult` |
| iPhone SE (3rd generation), iOS 26.5 | Default, landscape | English passed with corrected whole-screen capture, 100.691 s; `/tmp/limen-small-landscape-screen.xcresult`. Selected originals and provenance are in [ui-small-landscape](evidence/ui-small-landscape/) |
| iPad Pro 13-inch (M5), iOS 26.5, `1832F00F-BAD8-43C6-8246-4E23D1763BFD` | Large `UICTContentSizeCategoryXXXL`, portrait | EN/FR/DE/IT/RM all passed, respectively 78.346/103.479/102.627/101.436/101.805 s; `/tmp/limen-final-tablet-matrix.xcresult` |
| iPad Pro 13-inch (M5), iOS 26.5 | Largest accessibility, landscape | Romansh passed with corrected whole-screen capture, 143.429 s; `/tmp/limen-tablet-final-style.xcresult`. Subsequent signature-header correction passed a fresh Romansh walk, 149.074 s; see [the tablet review](TABLET-DYNAMIC-TYPE.md) |
| iPhone 18 Pro, iOS 27 | Largest accessibility `UICTContentSizeCategoryAccessibilityXXXL`, portrait | English passed, 206.046 s. Remaining four languages in progress at this document checkpoint |

Default language samples: [English form](evidence/ui/default-en-02-new-session.png), [French legal checks](evidence/ui/default-fr-10-legal-overlay.png), [German legal checks](evidence/ui/default-de-10-legal-overlay.png), [Italian form](evidence/ui/default-it-02-new-session.png), [Romansh legal checks](evidence/ui/default-rm-10-legal-overlay.png). These precede the final shared-key and mast wrapping fixes; they establish localized navigation at their recorded source checkpoint, not byte-identical final-build screenshots.

The main iPhone's portrait app window is 402 × 874 points, captured at 1206 × 2622 pixels. The SE landscape window is 667 × 375 points, captured at 1334 × 750 pixels. The iPad display is 2064 × 2752 pixels at 2× scale: 1032 × 1376 points in portrait and 1376 × 1032 in landscape. A whole-screen snapshot is used for final landscape evidence because an XCTest app-window snapshot could be rotated/cropped even when the displayed simulator itself was correct. Image orientation metadata must be honored when viewing those original landscape files. iPad split-window operation has not been exercised by these full-window tests.

## Accessibility audit and actual fixes

`AccessibilityJourneyTest/testMainHandoverScreens` passed all unfiltered `performAccessibilityAudit()` calls on Hub, Dossier, Inspection and Review in **20.535 seconds**. The final result is `/tmp/limen-ui-audit-final.xcresult`; [its log](evidence/ui/limen-ui-audit-final.log) and [Hub](evidence/ui/final-audit-hub.png), [Dossier](evidence/ui/final-audit-dossier.png), [Inspection](evidence/ui/final-audit-inspection.png) and [Review](evidence/ui/final-audit-review.png) screenshots are retained. No issue handler, exclusion or audit-type suppression was used. This run includes the final `KeySurface` label sizing, solid text backgrounds, disabled-ink contrast and mast wrapping changes.

The English default landing/form audit also passed unfiltered in `/tmp/limen-ui-language-default.xcresult`. Earlier automated findings drove concrete changes: text-field hit regions now have at least 44-point height; disabled text has stronger contrast; essential key text wraps intrinsically; a solid text background replaces gradients under key labels; and the handover address wraps instead of ellipsizing. The final Review-key clipping report disappeared after sizing the `ButtonStyle` label intrinsically and removing extra tracking from its text.

A final larger-type initial-viewport run on iPhone 17 Pro / iOS 26.5 (`6F9172CC-DF86-4F05-9EB3-42E8E287668F`) still reported four contrast failures: French Large `Adresse`, and German/Italian/Romansh largest-type Exit. These results are retained in [the original log](evidence/ui/limen-ui-sized-audits-final.log). The French label occupied y719–754 while the scroll viewport ended at y729; the German Exit button occupied y812–879 while its viewport ended at y832. The [French element crop](evidence/ui/sized-audit-initial-fr-element.png) and [German element crop](evidence/ui/sized-audit-initial-de-element.png) show the pinned footer or home-indicator region replacing most of the audited label's pixels. They are partially occluded scroll-edge controls, so the initial audits are not reported as passes.

Separate cases move each flagged control fully into the visible viewport, assert its complete frame is inside that viewport and run another **unfiltered** audit; no contrast exemption is installed. All four passed in `/tmp/limen-ui-visible-audits-retry.xcresult`: French 8.399 s, German 9.232 s, Italian 9.324 s and Romansh 9.200 s. [The passing log](evidence/ui/limen-ui-visible-audits-retry.log) and [French](evidence/ui/sized-audit-visible-fr.png), [German](evidence/ui/sized-audit-visible-de.png), [Italian](evidence/ui/sized-audit-visible-it.png) and [Romansh](evidence/ui/sized-audit-visible-rm.png) originals are retained. An intermediate recheck moved the controls farther than necessary and brought the following identity heading into the lower clipping edge; [that failed log](evidence/ui/limen-ui-visible-audits-final.log) is retained too. The final driver reveals the full target with a 12-point margin rather than centering it.

Driver defects were kept separate from product defects. Lazy canton cells must be revealed before asserting creation. A keyboard's offscreen Done element is not a tappable dismissal control. Scroll gestures now start within the app's scroll viewport; global downward swipes could open Notification Center in compact landscape. Distance-based drags avoid oscillating above/below nearby controls. These corrections change navigation of the test, not the app's completion rules or audit results.

An automated audit samples the current screen. These passes do not establish every scroll position, every assistive-technology interaction or all accessibility categories. Human VoiceOver, Switch Control, external-keyboard and native-language comprehension testing remain distinct validation gates. Only iOS 26.5 and 27 simulators were available; iOS 17 minimum-runtime behavior was not executed.

The default-size screens expose the handover's sections and incomplete items clearly, with consistent large controls. The visible largest-type walks show the cost of the longer legal/privacy content: more vertical scrolling, and multiline mast titles leave less space for the scroll viewport. The full preview is deliberately available again on the signature screen, which adds vertical content there. These are observed layout tradeoffs, not claimed participant preferences or a measured human success rate; representative users still need to assess whether the amount of optional detail is comfortable during a real handover.

Pixel review of the largest-type iPad signature screen found its old 160-point header region exposed only part of the signer title/purpose while leaving excess space elsewhere. That header constraint was removed. The final signature layout was rechecked in Romansh on iPad landscape (149.074 s) and a phone signature-only journey (79.641 s): complete title/name/purpose, an accessible drawing surface and pinned actions, with actual ink saved. [The tablet review](TABLET-DYNAMIC-TYPE.md) retains the before/after source and device details. Earlier matrix ink-pad images remain earlier-checkpoint evidence, superseded by this focused correction.

## Reproduction and provenance

Tests are in `LimenUITests/Sources/ParityJourneyTest.swift` and `LanguageWalkTest.swift`. [The command index](evidence/ui/commands.json) preserves the actual `Command line invocation` emitted by each selected run's `xcodebuild` log, including mixed-bundle selectors. The final handover audit command was:

```sh
xcodebuild -workspace Limen.xcworkspace -scheme AllTests \
  -destination 'platform=iOS Simulator,id=CDF6919D-01E4-44D4-84F9-AF3CF5BFB1CA' \
  -derivedDataPath ./DD -collect-test-diagnostics never \
  -resultBundlePath /tmp/limen-ui-audit-final.xcresult \
  -only-testing:LimenUITests/AccessibilityJourneyTest/testMainHandoverScreens test \
  > /tmp/limen-ui-audit-final.log 2>&1
```

Use the same workspace, scheme and simulator with the exact case selectors in the workflow table to rerun an individual lifecycle; choose a new result path because `xcodebuild` does not overwrite an existing result bundle. Each case sets its own isolated launch arguments and language. The five largest-type cases are `LimenUITests/LanguageWalkTest/testEnglishLargestAccessibility`, `testFrenchLargestAccessibility`, `testGermanLargestAccessibility`, `testItalianLargestAccessibility` and `testRomanshLargestAccessibility`.

`xcrun xcresulttool export attachments --path <result.xcresult> --output-path <new-directory>` exports the originals. [The screenshot index](evidence/ui/index.json) records each selected file's source result, test identifier, original attachment name, device identifier, timestamp and SHA-256. Images were copied without alteration. Full `.xcresult` bundles remain at the stated local paths; selected logs and original images are retained in this repository for the handoff.

## 15 October rerun

The lifecycles, smokes, runtime boundaries, default and largest-type language walks and the handover-screen audit were re-executed on 15 October, the photo-viewer journeys were executed for the first time, and the sized form audits were run on three simulators with a driver that logs each issue's element and frame. The findings, including why the sized audits' contrast verdicts are not evidence either way, the keyboard state the first simulator had accumulated, the Italian role-key clipping that was real and is fixed, and the landlord lifecycle's keyboard behaviour on iOS 26.5, are in the final section of [VERIFICATION.md](VERIFICATION.md). Logs are under [evidence/ui-2026-10-15](evidence/ui-2026-10-15/). The 14 October screenshots above remain evidence of that day's source state; the new-session form's role and kind rows render differently at accessibility sizes since the 15th.
