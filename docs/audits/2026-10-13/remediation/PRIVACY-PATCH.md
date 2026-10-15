# Proposed website privacy update

Prepared 14 October 2026 for review. [privacy-source.patch](privacy-source.patch) changes only the five canonical `src/content/legal/limen/{en,fr,de,it,rm}.mdx` pages. It has **not** been applied to the website repository or deployed. The proposed date and version wording must be reconciled with the actual release before publication.

## Source and version scope

The local website checkout is `/Users/aperi/DEV/peringer`, clean at `2f992a6e6b5900c79a1efd096b3cdd50a5555cff`. Its English/German/Italian/Romansh notices are dated 1 October and French 7 October. Contrary to the state anticipated by the Windows handoff, the Android 1.2 update is not present in those working files. That update is available read-only in `ANDROID/limen/docs/audits/2026-10-13/remediation/privacy-source.patch`.

This proposal is directly applicable to the actual website checkout. It incorporates the Android audit's version-specific paragraph and adds the verified iPhone 1.2 behaviour. It preserves the distinction that earlier Android **and earlier iPhone versions** start address suggestions automatically. It does not describe every iPhone version as having the new default-off control. It also replaces the unsupported promise of identical PDFs across platforms with a version-specific introduction.

Do not apply both audit patches in sequence. If the Android proposal has already been integrated elsewhere, review this patch against that newer source and retain its older-version distinction. The earlier Android patch also has a different French description line from this checkout; that unrelated French description is preserved here.

## Proposed disclosures

The five language versions describe optional, default-off swisstopo suggestions; the recipient, typed query and manual offline entry; the explicit unprotected ZIP choice; password-protected archive encryption; supporting evidence and exact retained PDF/HTML copies; Files destinations; scoped backup contents; last-good recovery and retained originals; whole-record deletion versus already shared copies; private staging cleanup; and the participant's route to the recorded controller for access, correction or deletion requests.

The iPhone wording distinguishes private records/evidence/recovery/exports excluded from system backups from ordinary preferences that can contain reusable contact defaults, recent-input recovery values and the open-record identifier. It describes the library/settings authentication gate without claiming it hides the current shared handover or encrypts exports. The camera and optional Face ID descriptions are distinguished from selected-photo/document access. OS file protection is separate from archive encryption.

The implementation basis is recorded in [PRIVACY-AND-RELEASE.md](../PRIVACY-AND-RELEASE.md), [IMPLEMENTATION.md](../IMPLEMENTATION.md), [CROSS-PLATFORM.md](../CROSS-PLATFORM.md) and [RUNTIME-BOUNDARIES.md](../RUNTIME-BOUNDARIES.md). These disclosures do not assert that a signature trace is a qualified electronic signature or that recording a party's position determines liability.

## Translation provenance and review

Existing prose outside the targeted paragraphs remains unchanged, including the previously revised French text. The historical `sourceHash: 8080a521ed2dfb0c` remains intact in all four translations. Its accompanying comments now explicitly identify it as the **historical base**, not a claim that a translation provider translated the new English text.

The new and adapted paragraphs are **Codex-authored drafts**. The Android supplement follows the retained Android audit proposal; the iPhone additions follow the inspected Swift implementation. Frontmatter comments identify the draft authorship and pending review in every language. No established provider has been silently replaced, no new provider hash is fabricated, and no native-language or professional legal review is claimed. Native Romansh and consequential legal wording require external review before publication. Existing source defects outside these changes have not been disguised as reviewed translations.

A second source review found no material discrepancy between the five proposed notices and the implemented scope, backup, recovery, controller-contact or library-gate behaviour. That review identified existing Romansh `cudesch` wording in the third-party-code paragraph as an item for native correction; it is unchanged historical prose, not a reviewed new translation. This cross-check does not supply native or professional certification.

## Local verification

`git apply --check` passed against the clean website checkout. Source SHA-256 values were checked again afterward; `git status --porcelain=v1` remained empty. The [manifest](privacy-source-manifest.json) records the website commit and SHA-256 for each original and proposed file.

All five proposed MDX bodies compiled with the website's installed `@mdx-js/mdx`. Its existing copy and structure auditors reported zero findings when run over the five proposed files in `/tmp/limen-privacy-proposal`. This is syntax and house-style verification, not a full website build, native-language validation or legal approval.

The applicability check can be repeated without changing the website:

```sh
git -C /Users/aperi/DEV/peringer apply --check \
  /Users/aperi/DEV/SWIFT/limen/docs/audits/2026-10-13/remediation/privacy-source.patch
git -C /Users/aperi/DEV/peringer status --porcelain=v1
```

The store privacy declaration, swisstopo retention assessment, native/professional review and publication decision remain external gates documented in the release notes. A successful patch check is not publication approval.
