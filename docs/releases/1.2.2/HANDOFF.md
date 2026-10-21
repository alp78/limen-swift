# Limen iPhone 1.2.2 (6), the simplification of 15 October 2026

Written 15 October 2026 against Swift commit `ca3e6bc` (the Android 1.2 parity handoff) and Android `origin/main` at `91b0103`, the head after "Strip the sentence-long buttons, instruction text, lookup switch and controller block from the forms, put one-word keys at the bottom of each, and open the record from a hub door". The request is `_scratch/MACBOOK-IOS-SIMPLIFICATION-PROMPT.txt`. This is a removal pass over the forms the parity work had built; the data, archive, legal and export work of [the audit ledger](../../audits/2026-10-13/IMPLEMENTATION.md) is untouched.

The Android checkout at `/Users/aperi/DEV/ANDROID/limen` was fast-forwarded from `d81796d` to `91b0103` (three commits, a clean tree, no local change) so the generators could read the reference. Nothing in the Android repository or on the website was modified.

## What changed, screen by screen

New session form. The title stays at the top; the role, the kind, the identity fields, the address fields and the phone remain. At the bottom, one row with two keys, Brouillon (save glyph, outlined) and Valider (check glyph, filled), both disabled until the name is in; Brouillon creates the record, saves it and returns to the records list, Valider creates it and opens the hub. Gone: the "Démarrer un brouillon avec ces informations" key, the "Nouvel état des lieux · Entrée" transport key, the lookup switch with its "Facultatif : les adresses saisies sont envoyées à swisstopo" disclosure, the helper under the street field and the agency explanation under the company field. (The iPhone form never carried the "Seul votre nom est requis" line or the controller block.) The lookup-failed line, "Recherche d’adresse indisponible.", is shown as a status when swisstopo cannot be reached; `SwissAddressLookup.lookup` now reports that distinctly from an address it does not know. At accessibility type sizes the two keys stack, for the reason the three-way rows already stack.

Dossier. The object card has no switch and no disclosure; the lookup runs whenever the phone is online, and the info mark keeps the one line "Saisissez une adresse, puis choisissez la suggestion officielle." The participant notice panel, with its toggle, is gone; `details.participantNoticeShown` stays in the record, unread. The scope field is labelled "Motif", and the panel that groups one per rubric carries the same word. The add keys for meters, keys and badges, documents and follow-ups are plus glyphs whose accessible name is "Ajouter · <section>"; "Joindre un document" is "Joindre". The dossier has no key at its foot.

Hub. The object card keeps its canton flag and one key, COMPLÉTER; its sentence is gone. "Informations à compléter" is "Données manquantes", a small label over plain tappable lines of body text (44 points high for the thumb, no chevron), one line at a time with "Tout afficher (n)" for the rest. The bottom key "RELIRE LE CONSTAT" is gone; the third door, CONSTAT, sits beside INSPECTION and DOSSIER, same shape, check glyph, lead "Relecture, signatures et export", readout Non signé, En attente de signatures or Finalisé, opening the review or, once the record is locked, the export.

Masthead. No info mark and no sentence per step.

Inspection. No sentence above the room chips. A handover with no room to walk leaves the setup through its Motif and a Done key, as on Android, which the iPhone had no way to do before. On a room, the actions are one row: an ellipsis glyph opening the room actions, then up, down, clear findings and remove room as glyphs (the two destructive ones red, still behind their confirmation), and Pièce suivante with a forward glyph at the right end. When the open row is wider than the screen, which it is on every iPhone at the largest type sizes, `ViewThatFits` gives the primary key a line of its own rather than clipping it. The accessible names are the generated "EFFACER LES CONSTATS" and "RETIRER LA PIÈCE"; the confirmations keep their bodies.

Signature step. The "Saisissez toute réserve avant de signer" line is gone. "Impossible de tracer : papier / représentant" is "Signature impossible", "Copie HTML accessible" is "Copie HTML", "Aperçu complet du document" is "Aperçu". The review acknowledgement under the preview, an iPhone mechanism Android does not have, reads Valider with a check glyph instead of "J’ai relu le document complet"; Done in the bar only closes the sheet.

Records list. A record without an address is titled "Sans adresse", one line, ellipsised. A draft entry's chip reads FINALISER and opens the record at the signature step; a finalized entry's reads SORTIE and seeds the exit. The disabled "FINALISER L'ENTRÉE D'ABORD" chip is gone. An unreadable record's recovery key reads "Récupérer".

Data, backup and privacy. No lookup switch. The backup key reads SAUVEGARDER. The controller panel with its fields stays. The iPhone screen never had the archive-limit sentence or the repair toggle, so there was nothing to shorten.

Date and time fields. "Rétablir la dernière date valide" and "Rétablir la dernière heure valide" are undo glyphs with those sentences as their accessible names, word for word Android's inline strings.

Legal panel. "Trouver l’autorité de conciliation compétente" is "Autorité de conciliation" in the generated strings. The iPhone panel links every dated source of the snapshot by host name and has never shown that key; nothing visible changed there.

## The strings

`Str.swift` was regenerated from the reference head: 381 declarations (335 core, 46 extensions), 2 iOS overrides, against 386 before. Removed: `stepLead`, `tipStep`, `hubClose`, `objectPreflightBody`, `chooseRoomsPresentBody`, `reservationBeforeSign`, `agencyRoleExplanation`, `onlineLookup`, `lookupDisclosure`. Added: `validate`, `stepRecord`, `hubRecordLead`, `reason`. Shortened: `noAddress`, `exitFromThis`, `finalizeEntryFirst`, `stillMissing`, `completeObjectAndCanton`, `createBackup`, `clearRoom`, `removeRoom`, `recover`, `addDocument`, `nextRoom`, `unableToDraw`, `accessibleCopy`, `preview`, `conciliation`, `lookupFailed`. `addressLookupHint` is back to its 1.1.2 text and feeds only the object panel's info tip. The privacy paragraph about swisstopo is back to the 1.1.2 wording, automatic lookup, in all five languages, which is what the published notices at peringer.ch/legal/limen/privacy/ have said since 15 October.

The iOS-only copy in `PlatformCopy.swift` lost `participantNotice`, `revertInput` and `acknowledgeReview` and gained the three inline Android strings the screens needed: `restoreLastValidDate`, `restoreLastValidTime` and `showAll`.

## Data and records

Nothing in the record format changed; `make check-generated` is clean. The `addressLookupEnabled` preference is no longer read or written; a value 1.2.0 (5) may have stored is left unread, as Android leaves its own `onlineAddresses`, and no migration runs. The legacy fixtures, the golden fingerprint and the crypto interoperability suites ran unchanged, see below.

## The sweep

Searched: every `Text(s.…)` in the app sources whose English is a sentence, every visible key label of more than two words, every literal label, and every `Toggle` near the word lookup. No toggle gates the lookup. What is left, and why:

- Sentences that are statuses or results, not instructions: `addressSearching`, `lookupFailed`, `working`, `sessionsEmpty`, `saveFailed`, `finalizationFailed`, `archiveFailed`, `amendFailed`, `invalidInput` (the error line under a field, iOS only).
- Sentences that are legal or factual statements Android 1.2.2 still shows in the same place: `estimateNotice`, `vaudPreviousExitReport`, `infoDeposit`, `translationNotice`, `infoOneSided`, `inkEvidenceNotice`, `deliverySelfDeclared`, `deliveryChangedBody`, `exportBlocked`, `controllerBody`, `licencesBody`, `backupBody`, `foreignAddressHint`, `tenantExitAddressHint`. Each is reached through the same `s.` name on Android at `91b0103`.
- iOS runtime texts with no Android counterpart: `cameraPermissionDenied`, `cameraRestricted`, `cameraProcessingFailed`, `photoTooLarge`, `plainArchiveWarning`, the camera and Files boundaries the audit added.
- Keys of more than two words that Android 1.2.2 keeps verbatim: COMPARE DEPOSIT OPTIONS (`compareKey`), USE SELECTED ROOMS (`useSelectedRooms`), SAVE AS DRAFT (`saveAsDraft`), ADD A CATEGORY (`addCategory`), "Add a kind of key" (`addKeyKind`), DATA, BACKUP & PRIVACY (`dataAndPrivacy`).
- Keys that are iOS only: "Create unencrypted archive" (`plainArchive`), the explicit plain-archive path the audit chose over Android's toggle inside the password dialog, three words and left as the audit decided; the toggle label `libraryProtection`, a sentence on Android too, worded for the iOS gate's scope.
- Accessible names of glyph keys, which are not visible labels: "Restore last valid date", "Restore last valid time", "Clear delivery record", "Note a defect", PICK A DATE, PICK A TIME.
- Literal labels built from a word and a count or a rubric: "+ Contract", "+ Tenant", "+ Front door key", "✓ Object" on the dossier rail, "Tout afficher (3)", "100%".

## Version

`Project.swift` carries MARKETING_VERSION 1.2.2 and CURRENT_PROJECT_VERSION 6: the name follows Android, the build number is this project's own sequence (4 uploaded, 5 archived and never uploaded, so 6). `BundleTests` asserts the pair in the built bundle. Nothing was uploaded to TestFlight or App Store Connect, no version was created there, and the five-language release notes are prepared, not uploaded, in [RELEASE-NOTES.md](RELEASE-NOTES.md). Corrected 21 October 2026: later on 15 October the owner uploaded build 6 (delivery `217c7844-67da-40c7-ac78-68e7bea2f70d`), Apple processed it as valid, and on 16 October it went to the Owner and Agencies groups and into Beta App Review; [the 1.2.5 handoff](../1.2.5/HANDOFF.md) carries the record.

## Verification

All on 15 October 2026 from the working tree described above, under the Debug identity `dev.peringer.limen.audit` for every simulator and journey run, and under `dev.peringer.limen` only for the installed Release IPA.

- Generators, lint, whitespace. `make check-generated` clean (381 declarations, schema unchanged, the generator's three unit tests), SwiftLint 0 violations, `git diff --check` clean. The project does not build with warnings as errors; the one warning in the build log is the AppIntents metadata note every build prints, and no source warning was introduced. [check-generated.log](evidence/check-generated.log), [simulator-build.log](evidence/simulator-build.log), [build-chain-status.log](evidence/build-chain-status.log).
- Unit suites, iPhone 17 Pro / iOS 26.5 simulator. 144 kit tests in 20 suites, 25 app tests in 5 suites and 4 bundle tests pass, the legacy fixtures, the golden fingerprint and the archive interoperability among them. [unit-tests.log](evidence/unit-tests.log).
- UI, iPhone 18 Pro / iOS 27 simulator. The French screenshot journey written for this pass (`SimplificationShotsTest`, 99.8 s), both smokes, the empty-form journey to drawn signatures and the opened PDF, the agency standalone exit with its amendment, the invalid-date relaunch with its undo key, the three runtime boundaries and the `testMainHandoverScreens` audit: 10 of 11 pass. The failure is the landlord entry-then-seeded-exit journey, open since the parity pass; it now gets past the legal note it used to stop at and fails at the "No physical keys" chip the driver expects on the seeded exit's dossier.
- UI, iPhone 17 Pro / iOS 26.5 simulator. All 18 language walks pass: the five default walks, the five large, the five largest accessibility, the English landscape, the Romansh largest landscape and the Romansh signature-only case. [simulator-ui-cases.log](evidence/simulator-ui-cases.log).
- The store-screenshot walks fail, and were broken before this pass by the parity commit: their card lookup matched the list's "Exit" filter chip before the card (corrected here to match the scene's street), and past that the seeded store scene cannot finalize under the 1.2 parties rule, because its landlord is represented without a mandate text, so "Name both tenant and landlord / agency" stays listed and FINALIZE RECORD stays disabled. The scene's wording is the owner's; the fixture was left as it is, and the walk now prints the screen tree when that wait fails. The store screenshots of 1.1.2 are what the listing still shows.
- Release artifact. `DD-release/Limen-1.2.2-6.xcarchive` (a gitignored build product): 1.2.2 (6), `dev.peringer.limen`, iOS 17.0, team KDSZB7N44K, exported development-signed for the phone and app-store-connect for the record, neither uploaded; hashes and sizes in [archive-metadata-2026-10-15.json](evidence/archive-metadata-2026-10-15.json), statuses in [archive-chain-status.log](evidence/archive-chain-status.log).
- Physical iPhone 17 (iPhone18,3), iOS 26.6.2. The development IPA installed over 1.2.0 (5) through devicectl with its data kept (no uninstall), and `InstalledReleaseSmokeTest`'s read-only flow passed against `dev.peringer.limen` in 7.5 s, screenshots in [evidence/installed-release-smoke/](evidence/installed-release-smoke/). The French journey then ran on the phone under the audit identity from a `build-for-testing` bundle and passed in 116.9 s; its nine screenshots are in [shots/iphone17-ios26.6.2/](shots/iphone17-ios26.6.2/) and the simulator's in [shots/simulator-iphone18pro-ios27/](shots/simulator-iphone18pro-ios27/). The form fits one screen at the default type size on both devices, so the top and bottom frames are the same picture. [phone-ui-cases.log](evidence/phone-ui-cases.log), [phone-install.log](evidence/phone-install.log).
- Not run. The iPad matrix, the small-screen landscape walks and the photo-viewer journeys, which this pass does not touch; the Java direction of the archive exchange; the iOS 17 minimum runtime, still not installed on this Mac.
- External, as before. Professional Swiss tenancy review, native Romansh review, assistive-technology sessions.

## Git handover

Not executed. One line, one message, no body, no attribution:

```
cd /Users/aperi/DEV/SWIFT/limen && git add CLAUDE.md Project.swift Limen LimenKit LimenKitTests LimenTests LimenUITests docs && git commit -m "Follow Android 1.2.2: strip the audit-era forms to glyph-and-word keys, open the record from a hub door, drop the lookup switch, and hand over 1.2.2 (6) verified on the simulators and the iPhone" && git push
```
