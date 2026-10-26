import PDFKit
import SwiftUI

/// The exported document, read in place: what ACTION_VIEW handed to a PDF app.
struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        #if DEBUG
        Self.made += 1
        #endif
        Self.openAtRequestedPage(view)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
            Self.openAtRequestedPage(uiView)
        }
    }

    #if DEBUG
    /// The document views this process has made, counted so the store walk can ask for a page on
    /// a later preview only.
    @MainActor private static var made = 0
    #endif

    /// Under the Debug identity only, `LIMEN_PREVIEW_FIND` in the launch environment names a text
    /// and the preview opens on the first page that carries it: the store walk shoots the annex's
    /// first photograph page by naming its file, which the legend prints and nothing else does.
    /// The page count is not known to the test, and a swipe count would change with every record.
    /// `LIMEN_PREVIEW_FIND_FROM` is the first preview of the process it applies to, so one launch
    /// shoots the cover on one preview and the annex on the next. The walk used to relaunch the app
    /// with the variable between the two, and on the iPhone the relaunch lost the step it was on.
    private static func openAtRequestedPage(_ view: PDFView) {
        #if DEBUG
        let from = ProcessInfo.processInfo.environment["LIMEN_PREVIEW_FIND_FROM"].flatMap(Int.init) ?? 1
        guard Bundle.main.bundleIdentifier == "dev.peringer.limen.audit",
              made >= from,
              let wanted = ProcessInfo.processInfo.environment["LIMEN_PREVIEW_FIND"], !wanted.isEmpty,
              let document = view.document,
              let page = document.findString(wanted, withOptions: []).first?.pages.first else { return }
        // After the view has laid out: a destination set before that is reset by autoScales.
        DispatchQueue.main.async { view.go(to: PDFDestination(page: page, at: CGPoint(x: 0, y: page.bounds(for: .mediaBox).height))) }
        #endif
    }
}
