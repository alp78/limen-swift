# PDF and HTML output inspection

Performed 14 October 2026 on the synthetic outputs produced by the current iOS export tests. This is a local raster/source inspection, not a physical paper inspection, native-language sign-off or human assistive-technology session.

## Rendering defect found and corrected

The initial PDFKit rasters exposed upside-down text glyphs even though PDF text extraction succeeded. The Core Graphics page was already transformed to the top-down coordinate system expected by UIKit `NSString.draw`; an extra per-line vertical flip inverted the glyphs and put section text through its separator rules. `PdfSheet.text` now draws directly in the page's established coordinates.

A new regression renders a known asymmetric glyph through the actual PDF renderer into a bitmap and checks that its dark pixels occupy the expected region above the baseline, with none below it. This is independent of successful PDF text extraction. The same test verifies that long unbroken hashes/URLs wrap within their column while retaining all characters. Existing wrapping already satisfied that bound; no token omission or ellipsis was added.

The synthetic rich record was also corrected to associate its two existing ink files with its new participant IDs and give the third participant an explicit refusal. This avoids an inconsistent test fixture that both displayed an unmatched legacy signature and called the corresponding newly identified participant unsigned. This was fixture repair, not a production identity migration.

## Executed checks

Final command:

```sh
xcodebuild -workspace Limen.xcworkspace -scheme AllTests \
  -destination 'platform=iOS Simulator,id=6F9172CC-DF86-4F05-9EB3-42E8E287668F' \
  -derivedDataPath ./DD-final -collect-test-diagnostics never \
  -only-testing:LimenTests/ExportTests \
  -resultBundlePath /tmp/limen-pdf-final.xcresult test
```

**Seven export tests passed.** The [retained log](evidence/pdf-final-tests.log) includes the pixel-orientation regression, five-language readable output, shared PDF/HTML content and escaping, draft status/missing individual outcomes/unknown deposit, tampered evidence rejection, role/kind matrix and model session test. This focused result supplements the earlier 19 app tests and four bundle tests; it does not imply the complete app suite was rerun by this reviewer after the pixel test was added.

The updated files are retained for [English](evidence/documents/synthetic-en.pdf), [French](evidence/documents/synthetic-fr.pdf), [German](evidence/documents/synthetic-de.pdf), [Italian](evidence/documents/synthetic-it.pdf) and [Romansh](evidence/documents/synthetic-rm.pdf), with matching `.html` files in the same directory. Synthetic testimony contains no personal records. Artificial epoch values and an escaped script-shaped reservation deliberately exercise the evidence and escaping paths; these are not real events or executable markup.

## Visual observations

PDFKit rasterized every page locally. All five documents contain four A4 pages; every MediaBox measures approximately **595.276 × 841.89 points**, as recorded in [page metrics](evidence/documents/pdf-page-metrics.txt). The four-page overviews were examined for every language: [EN](evidence/documents/overview-en.png), [FR](evidence/documents/overview-fr.png), [DE](evidence/documents/overview-de.png), [IT](evidence/documents/overview-it.png), [RM](evidence/documents/overview-rm.png). Representative full-size raster checks include [English page 1](evidence/documents/raster-en-1.png), [German page 2](evidence/documents/raster-de-2.png) and [Romansh page 3](evidence/documents/raster-rm-3.png).

- Text and photograph/signature images are upright. Headers clear their rules. No clipped essential label, signer caption, long address, finding, independent position, reservation, fingerprint or photo hash was observed in these samples.
- The long German and Romansh scope headings fit the available width. The bank name/account wrap across multiple lines and continue onto page 2. Page 4 contains the release instructions and the complete synthetic photograph with a numbered caption/hash.
- The three participant outcomes remain distinct: two synthetic drawn-ink images and one explicitly labelled refusal. The claim and independent normal-wear position both remain visible. The HTML-shaped reservation prints literally in the PDF.
- Page numbering remains `1 / 4` through `4 / 4`, with the same evidence reference on each page. The sparse final page is a consequence of keeping the photograph and instructions readable; no evidence was omitted to reduce the page count.
- At A4 scale, the current 26-unit body/section/value type corresponds to about **12.48 pt**, 23-unit labels to **11.04 pt**, 22-unit small text to **10.56 pt**, and the 40-unit title to **19.20 pt**. These are computed physical point sizes, not a claim that a paper print was tested with a reader.

## HTML inspection and limits

All five companion files were parsed and checked: correct `lang`, one `h1`, 21 `h2` sections, three embedded images with nonempty identifying alternatives, no script/iframe/object/embed or inline event handlers, and escaped test testimony. Results are retained in [html-structure-check.json](evidence/documents/html-structure-check.json). The shared export test checks the selected facts in both outputs; entered English/French testimony remains unchanged when labels change language.

These checks establish neither a complete semantic description of each photograph nor a VoiceOver reading experience. The PDF remains an untagged graphics PDF. Actual browser/assistive reading, full pre-sign focus/heading navigation, magnification, physical printing and native review of all five languages remain separate validation work. The shared schema still provides a PDF digest only; a restored HTML companion must not be described as authenticated by that PDF digest.
