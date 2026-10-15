# Swiss market and research assessment

Reviewed 14 October 2026. This is a product assessment from source inspection and the engineering checks recorded in this audit. Competitor descriptions below are their published claims, not products personally tested. No interviews, conversion rate, willingness-to-pay estimate or unaided-completion percentage has been measured.

## Likely fit

An occasional tenant or private landlord benefits from a quick draft, independent statements, offline evidence capture, a complete review before signing, and an export that can be opened again without an account. Five document languages and explicit unresolved checks are useful Swiss distinctions. The main adoption barrier is still learning the form while the other party waits. Putting every advanced field on the initial screen would undermine the quick start.

A small professional operator is the strongest pilot audience: repeatable readings, identified participants, attachments, entry-to-exit comparison and private copies can replace an improvised paper/photo workflow. The operator must own backups, device loss planning and retention. There is no multi-user office coordination, central rights administration, work-order integration or portfolio synchronisation.

A large agency should assess Limen as a limited local capture tool, not as its operating platform. The missing integrations, shared administration and centrally managed recovery are substantive differences. Local-only operation is a privacy and offline benefit with an operational cost, not automatic enterprise readiness.

## Current first-party comparison

| Product | Published offer | Consequence for Limen |
| --- | --- | --- |
| [Wohnungsprotokoll](https://www.wohnungsapp.ch/) | iOS/Android capture, photos, signing, branding and PDF delivery; advertises CHF 3 per export or CHF 20/month and says export needs a connection; lists German/English | Offline export and five languages are meaningful differences. Its signature/legal claims have not been independently certified here. |
| [Tayo Checks](https://www.tayo-software.com/checks) | Offline room workflow, configurable templates, annotated photos, entry/exit comparison, report delivery and anomaly-to-ticket handling | Limen needs a reliable simple handover journey; competing on agency workflow breadth would require a different product investment. |
| [AXimmo/Axept](https://www.axept.ch/onlinemagazin/aximmo-digitale-wohnungsabnahme-effizient-und-einfach) | Describes Tayo Checks connected with AbaImmo property-management data | Integration and avoiding repeated office entry are material professional advantages. |
| [ImmoPad](https://immopad.com/agences-immobilieres/) and [offers](https://immopad.com/tarifs/) | Offline inspections, configurable reports, work follow-up, technical visits and subscriptions selected by professional needs | Limen's narrower local ownership and evidence model are easier to explain than a claim to equivalent workflow breadth. No current price was inferred from old promotions. |

The historical Limen price of CHF 15 and Switzerland-only rollout were not confirmed as a live offer. The public Apple listing URL for app 6817920270 was inaccessible to this lookup, and search did not establish a current listing. An earlier session preflight reported 1.1.2 build 4 on the phone, while the later pre-install query reported no production bundle; [VERIFICATION.md](VERIFICATION.md) preserves that distinction. Those facts do not establish App Store availability, paid agreement status, current price or TestFlight approval. No store state was changed.

## Usability judgement and proposed study

The source-level improvements remove several concrete obstacles: a name can start a draft; raw invalid dates survive navigation; completion issues lead back to relevant areas; a tenant's disagreement no longer erases the other party's claim; and exact copies can be reopened. Advanced readings, access devices, attachments and follow-ups use disclosure sections. This is a more coherent sequence, but the enlarged dossier and repeated review after changing signed content still need observation with real users. Engineering tests do not measure whether the wording is understood or the product feels pleasant.

Recruit six to eight Swiss participants spanning an occasional tenant, private landlord, small agency operator, French/German/Italian use, and someone who regularly uses VoiceOver or another assistive technology. Include a native Romansh reviewer separately. Use invented parties and addresses. Allow 45 minutes each, obtain consent for observation, and do not use real tenancy disputes.

1. Begin from an empty app and record an entry with two tenants and an agency representative for the actual landlord.
2. Record existing wear and a disputed claim, inspect a photo, enter and correct an impossible date, and explain one unavailable document.
3. Pass the phone to each participant: locate their reservation, read the whole preview and record an appropriate signature or alternative outcome.
4. Finalize, export, reopen a saved copy, record delivery, then explain whether delivery means formal service.
5. Start an exit from the entry, identify prior evidence without turning it into a new finding, and create an amendment.
6. Back up only that record and describe the difference between a password-protected archive, a plain archive and the library access gate.

Measure unaided completion, time and taps, help requests, incorrect party assignments, misunderstood liability/deadline statements, accidental edits, ability to find evidence, and recovery after interruption. Record device, language and text size. Use neutral prompts; do not teach the path first. Investigate errors before setting a completion target. No population moving statistic is used as a count of payable household handovers.

## Observed engineering usability findings

The empty-form automated simulator journey reached two genuinely drawn test signatures, finalization and the opened document in 118.293 seconds after the fixes. This is XCTest wall time with scripted input and synthetic facts; it is not a human completion time, comprehension measure or success rate. The test exposed excessive scrolling from always-open optional contacts, hidden keyboard actions, and a hard-to-reach start control. Optional contacts now disclose on demand; essential actions reflow and the start action adapts to available height. The complete review adds a deliberate reading step and supports both PDF and structured HTML.

The workflow has clearer divisions between dossier facts, inspection, review, signatures and copies. It remains a substantial legal/evidence form: long legal checks and the new optional detail sections can demand considerable navigation. The automated flow does not establish that a first-time tenant knows what to enter, whether an agency accepts the record operationally, or whether the current information density feels pleasant. A large-library performance benchmark and the moderated role/assistive-technology sessions above are still needed. No customer interview or willingness-to-pay result is inferred from the implemented features.
