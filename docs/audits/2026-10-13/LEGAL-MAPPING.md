# iOS legal implementation mapping

Engineering source review: 14 October 2026, Europe/Zurich. Android baseline `eb5c03800a9e749155db718136c9418a58c0d11c`; intervening fixes reviewed against `d81796d07ada38aa6e7955d31cf297fe02cac010`. This document adds current iOS evidence; it does not rewrite the Android audit or certify legal compliance.

## Source register

- **F**: [Code of Obligations, official 1 January 2026 consolidated PDF](https://www.fedlex.admin.ch/filestore/fedlex.data.admin.ch/eli/cc/27/317_321_377/20260101/fr/pdf-a/fedlex-data-admin-ch-eli-cc-27-317_321_377-20260101-fr-pdf-a.pdf), arts. 256/256a, 257e/257g, 267/267a and 270. Inspected the official text. The federal baseline separates delivery/maintenance, access to a prior return record, defect reporting, ordinary wear, security and initial-rent challenge. The app records observations and attributed positions, not an adjudication. A condition report is not an official initial-rent form, automatic bank release or proof of formal notification. The model has no automatic ten-day or two/three-working-day notice date; `Clocks.agreedPlanningDate` requires an entered clause, period and actual possession transfer. A planning date does not replace immediate reporting duties. These conclusions also apply outside the targeted canton additions below.
- **I**: [BWO/OFL initial-rent overview](https://www.bwo.admin.ch/fr/formule-officielle-loyer-initial), linked [September 2026 PDF](https://www.bwo.admin.ch/dam/fr/sd-web/lp4WEVqxdXWN/2026-09-16_F_Verzeichnis%20Formularpflicht%20Anfangsmietzins_Kantonale%20Gesetze%20und%20Leerwohnungsziffer.pdf). The actual document says 2026 despite its stale 2022 metadata title. Seven canton-wide duties and NE/VD local conditions match the reference. Missing or non-2026 lease-conclusion dates remain `VerifyCurrent`; the handover date does not substitute for conclusion.
- **A**: [BWO authority directory](https://www.bwo.admin.ch/dam/de/sd-web/tzHM7tFgxwhW/20260114_Schlichtungsbeh%C3%B6rden.pdf). Internal revision is **8 July 2026**, despite the January filename. It lists competent regional/cantonal routes and explicitly distinguishes qualified electronic filing under CPC 130(2). Limen exports do not submit a case. Users must consult the linked competent authority for address, current formalities and filing method.
- **NE**: [LI-CO 224.1, art. 4](https://rsn.ne.ch/DATA/program/books/rsne/htm/224.1.htm), [implementing order 224.2, art. 2](https://rsn.ne.ch/DATA/program/books/rsne/htm/224.2.htm), and [2026 LVAL order 846.02](https://rsn.ne.ch/DATA/program/books/rsne/htm/846.02.htm). The second source explicitly connects the form duty to municipalities subject to LVAL. The dated order, effective 1 January 2026, specifies Laténa 4/5 and La Grande Béroche 3/4/5, the other listed municipalities 2–5; half rooms are excluded. The separate legal room category is independent of inspection-room count. Unrecognised locality names stay unresolved rather than imply exemption. Interpretation of dwelling classification in a concrete lease remains an external legal question.
- **VD**: [2026 district guidance](https://www.vd.ch/territoire-et-construction/logement/politique-du-logement/penurie-de-logements), [cantonal tenancy page](https://www.vd.ch/territoire-et-construction/logement/droit-du-bail), and [official RULV](https://www.vd.ch/fileadmin/user_upload/themes/vie_privee/logement/fichiers_pdf/rulv.pdf). Aigle is the 2026 district exception; other named districts trigger the form check. The tenancy page confirms extension through 30 June 2032, citing the federal April/June 2026 orders. RULV arts. 1, 2, 5, 35–37 distinguish entry/return, copies, security proof/handling, both parties' liability insurance and key return. The model preserves 1 July 2020–30 June 2026 and 1 July 2026–30 June 2032 profiles. Actual applicability, contractual exceptions and notice/return dates require case-specific review.
- **FR**: [LABLF 222.3.1 official PDF](https://bdlf.fr.ch/api/fr/versions/7153/pdf_file), art. 26: cash/securities received by landlord/representative must be deposited within ten days in the tenant's name at an eligible bank with a seat/branch in the canton. The check records the actual situation and evidence, including non-applicability for different instruments; selecting a marketed guarantee is not certification. Art. 27 additionally places form notification no later than delivery of the property.
- **GE**: [LGFL I 4 10](https://silgeneve.ch/legis/data/rsg_i4_10.htm), arts. 1, 3 and 6: tenant's bank choice, blocked deposit, ten-day handling after receipt, two depositary certificates; residential simple guarantee at tenant's request with ability to change to a blocked deposit. Do not infer that every insurance product fits that category.
- **TI**: [cantonal tenancy implementation law 222.100](https://www3.ti.ch/CAN/RLeggi/public/index.php/raccolta-leggi/legge/num/153), arts. 6–13: ten-day handling of received cash/values in a tenant-named local bank deposit, substitute guarantees, depositary receipt in two copies, and optional municipal expert on a party's/authority's request. An expert is not a required participant in every record.

The supplied [OFCOM signature explanation URL](https://www.bakom.admin.ch/fr/23-quelle-est-la-valeur-legale-des-signatures-electroniques) returned navigation without its article body in this audit's retrieval. That specific explanation could not be independently re-read. The official authority directory does explicitly require qualified signing for electronic procedural submissions. No drawn mark, local file hash, recorded time, refusal or typed outcome is described as verified identity, trusted time or a qualified signature.

## Shared implementation and output mapping

`LegalOverlay.swift` resolves the versioned classification from object canton, lease-conclusion date, handover date and locality/category. `LegalOverlayRecord.notes[requirement]` gives every unresolved or exceptional check its own reason. A confirmed unresolved initial-form classification also needs a specific explanation. The old shared note is accepted only under the explicit `ch-tenancy-2026.1` resolver.

`RecordDetails` stores actual transfer, clause/period, follow-up recipient/method/date, classified supporting documents and source references. `RecordContent.extraContent` supplies these selected details to preview/PDF/HTML; the export's existing legal section supplies statuses and explanations. Neither a receipt flag nor an unchecked box proves service/compliance. Deposit receipt/deposit dates, holder/institution and exceptions are entered in the requirement's note and supporting deposit documents; Android 1.2 has no separate structured fields for all those facts. This is a usability limitation, not a hidden schema addition.

New finalizations carry `LegalSnapshot` with rule/profile/classification/requirements/sources. Current iOS snapshots explicitly record review date `2026-10-14`; Android's default snapshot date remains `2026-10-13`. iOS source lists additionally include the federal code, authority directory and NE 224.2 connection. This is an intentional provenance difference in supported data. Old finalized bytes are not enriched or assigned participant IDs. Finalized records without snapshots select their historical resolver; never-retained historic PDF bytes cannot be recreated by claiming the current renderer is the same.

`invalidatedLegalRequirements(next:)` links changed inputs to affected checks. Deposit changes reset deposit checks; room category resets the initial-form check; locality resets initial-form/timing; property/canton changes require all checks again. Unrelated insurance/form confirmations survive deposit edits. This is tested as model behaviour; read the main implementation ledger for runtime integration status.

## All 26 cantons

For every row, **F + A** applies and means federal/lease facts, actual transfer, individual positions, responsible authority routing and manual verification of local timing/submission formalities. **I** is the dated initial-rent snapshot. N means no form duty listed by that snapshot, not absence of other cantonal law. The shared fixture `everyCantonHasDatedInitialFormAndCommonAuthorityGuidance` iterates every row and tests required/conditional/not-required, missing-year, other-year and source routing. The relevant resolved overlay, check status/reason and snapshot are part of PDF/HTML selection.

| Canton | 2026 form | Additional source/check |
|---|---|---|
| AG | N | F, A, I |
| AI | N | F, A, I |
| AR | N | F, A, I |
| BE | R | F, A, I |
| BL | N | F, A, I |
| BS | R | F, A, I |
| FR | R | FR deposit; incorporated Romand terms |
| GE | R | GE deposit; incorporated Romand terms |
| GL | N | F, A, I |
| GR | N | F, A, I |
| JU | N | Expressly incorporated Romand terms |
| LU | R | F, A, I |
| NE | C | NE locality/category; incorporated terms |
| NW | N | F, A, I |
| OW | N | F, A, I |
| SG | N | F, A, I |
| SH | N | F, A, I |
| SO | N | F, A, I |
| SZ | N | F, A, I |
| TG | N | F, A, I |
| TI | N | TI deposit; optional expert |
| UR | N | F, A, I |
| VD | C | VD district, dated RULV checks |
| VS | N | Expressly incorporated Romand terms |
| ZG | R | F, A, I |
| ZH | R | F, A, I |

Additional fixtures in `ParityRulesTests`: NE category/misspelling/nonfinite boundaries; VD known/unknown/Aigle; FR/GE/TI none/unknown/insurance triggers; independent per-check reasons; frozen/legacy nonmutation; dependency-specific invalidation. `LegalProfileTests` cover both RULV start/end boundaries. `ClocksTests.planningDateRequiresActualTransferAndRecordedClause` replaces the automatic ten-day assumption.

Remaining legal release review: professional Swiss tenancy review of source interpretation, locality/category edge cases and applicability; current authority submission practice for an actual case; native review of consequential EN/FR/DE/IT/RM wording, especially Romansh. The common source directory is a routing aid, not an independently audited form/deadline inventory for every municipality. No statutory canton-specific handover form is invented. Engineering tests and successful export cannot certify these matters.

## Translation and generator provenance

`tools/strings.py` reads current Android `Strings.kt` and `RecordStrings.kt`: 339 core members and 47 extension members. Computed getters, call-member access, nullable enum functions and enum branches are supported; unsupported syntax fails. `tools/ios-strings.json` overrides Files destination text in all five languages. Shared legal/business translations retain their Android provenance. The two iOS destination translations are editorial changes in this work, not claimed native review.

Executed locally: `LIMEN_ANDROID=/Users/aperi/DEV/ANDROID/limen python3 tools/strings.py --check` passed, 386 members; `python3 -m unittest discover -s tools -p 'test_strings.py'` passed 3 tests. Focused SwiftLint on the added/changed model, legal, residual and regression files passed. Swift test execution/results are recorded by the integrating agent in the main ledger; their existence here alone is not a passing result.
