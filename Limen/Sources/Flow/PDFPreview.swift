import PDFKit
import SwiftUI

/// The exported document, read in place: what ACTION_VIEW handed to a PDF app.
struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url { uiView.document = PDFDocument(url: url) }
    }
}
