# Privacy and release preparation

Reviewed 14 October 2026. These are local implementation notes and draft publication answers. No App Store, TestFlight, website, price, country, account or export-compliance setting was submitted or changed.

## Implemented data flow

Address suggestions default to off. The disclosure identifies swisstopo and explains that typed addresses are sent for suggestions; manual entry remains available. Both address forms check the preference before starting a request and ignore cancelled/disabled results. The URL session remains ephemeral. A local preference is not permission to send the rest of a handover.

Records, originals, recovery copies and retained PDF/HTML pairs live in Application Support, excluded from device backup. Support and private cache staging use first-unlock Data Protection so background saves remain possible. That protection is an OS storage property, not the password-based archive cipher. The optional library/settings authentication gate uses device-owner authentication and does not hide the currently shared handover.

Unreferenced originals remain private until their whole record is deleted, because last-good recovery can still refer to them. Recovery preserves the unreadable original. Scoped archives select records and their referenced evidence and retained exports; they do not include unused originals or the recovery directory. Deleting a record does not retract copies already shared or published into Files.

Final PDF/HTML exports and backup files are published only after private staging succeeds. Files displays the app's Documents container, with the export subfolder Limen. Exact private copies support reopening even after public copies move. Startup removes abandoned private operation staging before new operations begin.

Preferences contain UI choices, operator/contact defaults, the open record ID and last-valid input recovery values. They use UserDefaults and have the OS's normal preference storage and backup behaviour; the Application Support exclusion is not a claim that every preference is excluded. A participant's request to the operator may require removing reusable contact defaults as well as deleting a record. This is an explicit retention limitation for future policy wording.

## System resources and manifest

The camera and optional Face ID purpose strings are supplied in en/fr/de/it/rm InfoPlist.strings and included by the app resource glob. iOS selects system permission language from its app/device language configuration, independently of the in-app document-language choice. PhotosPicker still uses user-selected access, without requesting full photo-library permission.

The app manifest declares UserDefaults for app-owned preferences. The app and LimenKit manifests declare file-metadata access for the app container and explicitly picked documents, corresponding to the actual file-size/attribute checks. The unused system-uptime call was removed from undo token generation. These entries were checked against [Apple's required-reason documentation](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype). The build still has complete concurrency checking; the manifest is not a substitute for runtime/network inspection.

## Draft App Privacy answer

No analytics, advertising, developer account, developer-operated record server or tracking SDK is present in the inspected sources. On-device record processing and the user's chosen exports must be distinguished from the optional address query sent to swisstopo. Before a declaration is submitted, the operator must establish the service's retention and treatment of those queries against [Apple's collection definitions and disclosure guidance](https://developer.apple.com/app-store/app-privacy-details/). Do not claim a blanket service-provider exemption from the fact that a government service receives the request.

The checked-in manifest's no-tracking/no-declared-collected-data arrays describe the app implementation; they do not certify all facts needed for a store declaration. A network capture under the intended opt-in workflow and review of swisstopo retention remain separate evidence to retain.

## Draft localized store copy

[Store-copy draft](remediation/store-copy-draft.json) supplies updated descriptions and release notes in English, French, German and Italian, with a separate Romansh announcement draft. New wording is explicitly Codex-authored and unreviewed; no historical translation-provider claim is reused. Each description is below 4,000 characters. Apple's [current localization reference](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations), checked 14 October 2026, lists German with English (U.K.), French and Italian for Switzerland. Romansh is not listed as an App Store metadata locale; in-app/document support remains separate. No primary language, public name, price or territory change was made.

## Draft export-compliance answer

Limen implements standard AES-256-GCM archive encryption with PBKDF2-HMAC-SHA256, beyond operating-system HTTPS. The existing omission of ITSAppUsesNonExemptEncryption is retained. The owner must answer Apple's upload questions using the applicable exemption and jurisdictional facts; this implementation does not assert a legal exemption. No upload occurred.

## Draft 1.2 release notes

Record several tenants and landlords independently, distinguish agencies and mandates, and review the complete document before signing. Keep disputed claims and each participant's position separate. Add identified meters, access devices, supporting documents, scope explanations and later follow-up in amendments. Reopen exact PDF and accessible HTML copies. Address lookup is optional, backups can be scoped, and save failures and recovery copies are visible.

The dated canton checks now include local NE/VD inputs and targeted FR/GE/TI deposit guidance, with historical snapshots preserved. Guidance does not replace professional Swiss tenancy advice. Native Romansh review and representative assistive-technology user validation are still required before claims of reviewed translation or universal accessibility.

## Proposed website companion patch

The reviewable [five-language source patch](remediation/privacy-source.patch) targets the actual clean PERINGER checkout at `2f992a6e6b5900c79a1efd096b3cdd50a5555cff`. It incorporates the retained Android 1.2 audit proposal and adds explicit iPhone 1.2 disclosures while preserving earlier-version behaviour. The local website still has the October 1/7 source pages, so this is one combined patch against those files, not a claim that the Android proposal or the iPhone update is already live.

The patch covers default-off address suggestions, explicit plain archives, PDF/HTML copies, supporting evidence and recovery retention, Files destinations, private staging and backup exclusions, ordinary preference backups, the participant's controller contact route, and the scope of the optional library/settings gate. [PRIVACY-PATCH.md](remediation/PRIVACY-PATCH.md) records the exact source, translation provenance, hashes, applicability check and remaining native/professional review. All five proposed MDX bodies compiled; the website copy/structure checks found no issues in those five files. The website checkout remains unchanged.

The historical translation hashes are preserved and the new Codex-authored paragraphs are explicitly marked as unreviewed drafts. Before publication, reconcile the proposed date/version with the release and complete the external reviews. Store screenshots should reflect the preview and participant flows; do not describe drawn ink as a qualified electronic signature, a tenant response as a determination of liability, or a handover copy as automatic formal notice. No website or store submission was made.
