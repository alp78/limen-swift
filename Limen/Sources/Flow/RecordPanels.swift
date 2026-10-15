import LimenKit
import QuickLook
import WebKit
import SwiftUI
import UniformTypeIdentifiers

struct LookupPreference: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.str) private var s
    @Environment(\.limen) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(label: s.onlineLookup, on: model.addressLookupEnabled) { model.setAddressLookupEnabled(!model.addressLookupEnabled) }
            Text(s.lookupDisclosure).font(LimenType.bodySmall).foregroundStyle(colors.inkDim)
        }
    }
}

struct ScopeNote: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.str) private var s
    let p: HandoverProtocol
    let key: String

    var body: some View {
        Field(label: s.scopeReason, value: p.details.scopeNotes[key] ?? "", singleLine: false) { value in
            model.edit { var next = $0; next.details.scopeNotes[key] = value; return next }
        }
    }
}

struct CompletePreviewPanel: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.str) private var s
    @Environment(\.limen) private var colors
    let p: HandoverProtocol
    @State private var showing = false
    @State private var accessible = false

    var body: some View {
        Panel(label: s.preview) {
            VStack(alignment: .leading, spacing: 8) {
                Text(s.translationNotice).font(LimenType.bodySmall).foregroundStyle(colors.inkDim)
                Field(label: s.understoodLanguage, value: p.details.understoodLanguage) { value in
                    model.edit { var next = $0; next.details.understoodLanguage = value; return next }
                }
                SmallKey(label: model.previewBusy ? s.working : s.preview, enabled: !model.previewBusy, stretch: true) {
                    showing = true
                    model.previewDocument(p)
                }.accessibilityIdentifier("preview-document")
                if let error = model.previewError { Text(error).font(LimenType.bodySmall).foregroundStyle(colors.dangerOutline) }
            }
        }
        .sheet(isPresented: $showing) {
            NavigationStack {
                VStack(spacing: 12) {
                    if let file = model.documentPreview {
                        PillRow(options: [(false, s.preview), (true, s.accessibleCopy)], current: accessible) { accessible = $0 }.padding(.horizontal)
                        if accessible, let html = model.documentPreviewHTML {
                            LocalDocumentView(url: html.url)
                        } else { PDFPreview(url: file.url) }
                        if !p.isFinalized() {
                            SmallKey(label: s.acknowledgeReview, stretch: true) { model.confirmReview(); showing = false }.accessibilityIdentifier("confirm-review").padding(.horizontal)
                        }
                    } else if let error = model.previewError {
                        Text(error).padding()
                    } else {
                        ProgressView(s.working)
                    }
                }
                .navigationTitle(p.isFinalized() ? s.preview : s.previewDraft)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(s.done) { showing = false } } }
            }
        }
    }
}

/// Secondary record detail is disclosed in named sections so the doorstep form stays navigable.
struct RecordDetailPanels: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.str) private var s
    @Environment(\.limen) private var colors
    @Environment(\.recordLocked) private var locked
    let p: HandoverProtocol

    var body: some View {
        VStack(spacing: 10) {
            Panel(label: s.actualTransfer) {
                DisclosureGroup(s.actualTransfer) {
                    VStack(spacing: 8) {
                        DateField(label: s.handoverDate, stored: p.details.actualTransferDate, fieldKey: "transfer.date") { value in edit { $0.actualTransferDate = value } }
                        TimeField(label: s.handoverTime, stored: p.details.actualTransferTime, fieldKey: "transfer.time") { value in edit { $0.actualTransferTime = value } }
                        Field(label: s.notificationClause, value: p.details.notificationClause, singleLine: false) { value in edit { $0.notificationClause = value } }
                        Field(label: s.notificationClause, value: p.details.notificationDays, keyboard: .numberPad) { value in edit { $0.notificationDays = value } }
                    }.padding(.top, 8)
                }
            }
            .id("transfer")
            Panel(label: s.scopeReason) {
                DisclosureGroup(s.scopeReason) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(DossierCard.allCases, id: \.self) { card in
                            Text(s.dossierCard(card)).font(LimenType.labelSmall).foregroundStyle(colors.ink)
                            ScopeNote(p: p, key: card.rawValue)
                        }
                    }.padding(.top, 8)
                }
            }
            .id("scope")
            DetailedMetersPanel(p: p).id("readings")
            AccessDevicesPanel(p: p)
            SupportingDocumentsPanel(p: p).id("documents")
            FollowUpsPanel(p: p).id("follow-up")
            Panel(label: s.privacyTitle) {
                DisclosureGroup(s.privacyTitle) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(s.privacyParagraphs.enumerated()), id: \.offset) { _, paragraph in Text(paragraph).font(LimenType.bodySmall).foregroundStyle(colors.ink) }
                        Text([p.controllerIdentity.organisation, p.controllerIdentity.contactName, p.controllerIdentity.email, p.controllerIdentity.phone].filter { !$0.isBlank }.joined(separator: " · ")).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                        Toggle(label: s.participantNotice, on: p.details.participantNoticeShown, enabled: !locked) { edit { $0.participantNoticeShown.toggle() } }
                    }.padding(.top, 8)
                }
            }
        }
    }

    private func edit(_ change: (inout RecordDetails) -> Void) {
        var details = p.details
        change(&details)
        model.edit { var next = $0; next.details = details; return next }
    }
}

private struct DetailedMetersPanel: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let p: HandoverProtocol

    var body: some View {
        Panel(label: s.meters) {
            DisclosureGroup("\(s.meters) (\(p.details.readings.count))") {
                VStack(spacing: 12) {
                    ForEach(p.details.readings, id: \.id) { reading in MeterDetail(p: p, reading: reading) }
                    if !locked {
                        SmallKey(label: "+ \(s.meters)", stretch: true) {
                            model.edit { var next = $0; next.details.readings.append(MeterReading(id: UUID().uuidString)); return next }
                        }
                    }
                }.padding(.top, 8)
            }
        }
    }
}

private struct MeterDetail: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let p: HandoverProtocol
    let reading: MeterReading

    var body: some View {
        VStack(spacing: 8) {
            Field(label: s.meters, value: reading.label) { value in update { $0.label = value } }
            Field(label: s.identifier, value: reading.identifier) { value in update { $0.identifier = value } }
            WeightedRow(weights: [2, 1]) {
                Field(label: s.reading, value: reading.value, keyboard: .decimalPad) { value in update { $0.value = value } }
                Field(label: s.unit, value: reading.unit) { value in update { $0.unit = value } }
            }
            DateField(label: s.handoverDate, stored: reading.date, fieldKey: "meter.\(reading.id).date") { value in update { $0.date = value } }
            TimeField(label: s.handoverTime, stored: reading.time, fieldKey: "meter.\(reading.id).time") { value in update { $0.time = value } }
            Field(label: s.remarks, value: reading.note, singleLine: false) { value in update { $0.note = value } }
            EvidencePhotos(photos: reading.photos, add: { url, source in model.attachMeterPhoto(reading.id, source: url, photoSource: source) }, remove: { name in model.removeMeterPhoto(reading.id, name: name) })
            if !locked { SmallKey(label: s.delete) { model.edit { var next = $0; next.details.readings.removeAll { $0.id == reading.id }; return next } } }
        }
    }

    private func update(_ change: (inout MeterReading) -> Void) {
        var value = reading
        change(&value)
        model.edit { var next = $0; if let index = next.details.readings.firstIndex(where: { $0.id == reading.id }) { next.details.readings[index] = value }; return next }
    }
}

private struct AccessDevicesPanel: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let p: HandoverProtocol

    var body: some View {
        Panel(label: s.accessDevices) {
            DisclosureGroup("\(s.accessDevices) (\(p.details.accessDevices.count))") {
                VStack(spacing: 12) {
                    ForEach(p.details.accessDevices, id: \.id) { device in
                        VStack(alignment: .leading, spacing: 8) {
                            Field(label: s.accessDevices, value: device.label) { value in update(device) { $0.label = value } }
                            Field(label: s.identifier, value: device.identifier) { value in update(device) { $0.identifier = value } }
                            Text(s.expected)
                            Stepper(count: device.expected) { value in update(device) { $0.expected = value } }.disabled(locked)
                            Text(s.transferred)
                            Stepper(count: device.transferred) { value in update(device) { $0.transferred = value } }.disabled(locked)
                            Field(label: s.remarks, value: device.note, singleLine: false) { value in update(device) { $0.note = value } }
                            if !locked { SmallKey(label: s.delete) { model.edit { var next = $0; next.details.accessDevices.removeAll { $0.id == device.id }; return next } } }
                        }
                    }
                    if !locked { SmallKey(label: "+ \(s.accessDevices)", stretch: true) { model.edit { var next = $0; next.details.accessDevices.append(AccessDevice(id: UUID().uuidString)); return next } } }
                }.padding(.top, 8)
            }
        }
    }

    private func update(_ device: AccessDevice, _ change: (inout AccessDevice) -> Void) {
        var value = device
        change(&value)
        model.edit { var next = $0; if let index = next.details.accessDevices.firstIndex(where: { $0.id == device.id }) { next.details.accessDevices[index] = value }; return next }
    }
}

private struct SupportingDocumentsPanel: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let p: HandoverProtocol
    @State private var title = ""
    @State private var kind: DocumentKind = .other
    @State private var reference = ""
    @State private var importing = false
    @State private var owner = ""
    @State private var opened: ExportedFile?

    var body: some View {
        Panel(label: s.attachments) {
            DisclosureGroup("\(s.attachments) (\(p.details.attachments.count))") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(p.details.attachments, id: \.id) { document in
                        Text(document.title.ifBlank(s.documentKind(document.kind)))
                        if !document.externalReference.isBlank { Text(document.externalReference).textSelection(.enabled) }
                        if !document.file.isBlank {
                            SmallKey(label: s.open) {
                                if let url = model.documentURL(document) { opened = ExportedFile(url: url, displayName: document.title, bytes: document.bytes) }
                            }
                        }
                        if !locked { SmallKey(label: s.delete) { model.edit { var next = $0; next.details.attachments.removeAll { $0.id == document.id }; return next } } }
                    }
                    if !locked {
                        Field(label: s.documentTitle, value: title) { title = $0 }
                        PillRow(options: DocumentKind.allCases.map { ($0, s.documentKind($0)) }, current: kind) { kind = $0 }
                        SmallKey(label: s.addDocument, stretch: true) { owner = p.id; importing = true }
                        Field(label: s.externalReference, value: reference) { reference = $0 }
                        SmallKey(label: s.add, enabled: !reference.isBlank) {
                            model.edit { var next = $0; next.details.attachments.append(SupportingDocument(id: UUID().uuidString, kind: kind, title: title, externalReference: reference)); return next }
                            reference = ""; title = ""
                        }
                    }
                }.padding(.top, 8)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image]) { result in
            guard owner == model.working?.id, !model.contentLocked else { return }
            switch result {
            case .success(let url):
                model.importDocument(source: url, kind: kind, title: title)
                title = ""
            case .failure(let error):
                model.evidenceError = error.localizedDescription
            }
        }
        .sheet(item: $opened) { file in DocumentPreview(file: file) }
    }
}

private struct FollowUpsPanel: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let p: HandoverProtocol

    var body: some View {
        Panel(label: s.followUps) {
            DisclosureGroup("\(s.followUps) (\(p.details.followUps.count))") {
                VStack(spacing: 12) {
                    ForEach(p.details.followUps, id: \.id) { followUp in
                        VStack(spacing: 8) {
                            Field(label: s.defectText, value: followUp.description, singleLine: false) { value in update(followUp) { $0.description = value } }
                            DateField(label: s.discoveredOn, stored: followUp.discoveredDate, fieldKey: "followup.\(followUp.id).discovered") { value in update(followUp) { $0.discoveredDate = value } }
                            DateField(label: s.notifiedOn, stored: followUp.notifiedDate, fieldKey: "followup.\(followUp.id).notified") { value in update(followUp) { $0.notifiedDate = value } }
                            Field(label: s.parties, value: followUp.recipient) { value in update(followUp) { $0.recipient = value } }
                            Field(label: s.deliveryDetail, value: followUp.method) { value in update(followUp) { $0.method = value } }
                            DateField(label: s.fixDeadline, stored: followUp.deadline, fieldKey: "followup.\(followUp.id).deadline") { value in update(followUp) { $0.deadline = value } }
                            Toggle(label: s.done, on: followUp.done, enabled: !locked) { update(followUp) { $0.done.toggle() } }
                            if !locked { SmallKey(label: s.delete) { model.edit { var next = $0; next.details.followUps.removeAll { $0.id == followUp.id }; return next } } }
                        }
                    }
                    if !locked { SmallKey(label: "+ \(s.followUps)", stretch: true) { model.edit { var next = $0; next.details.followUps.append(FollowUp(id: UUID().uuidString)); return next } } }
                }.padding(.top, 8)
            }
        }
    }

    private func update(_ item: FollowUp, _ change: (inout FollowUp) -> Void) {
        var value = item
        change(&value)
        model.edit { var next = $0; if let index = next.details.followUps.firstIndex(where: { $0.id == item.id }) { next.details.followUps[index] = value }; return next }
    }
}

struct EvidencePhotos: View {
    @Environment(\.recordLocked) private var locked
    let photos: [PhotoEvidence]
    let add: (URL, PhotoSource) -> Void
    let remove: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            if !locked { PhotoIntakeKeys(onFile: add) }
            ScrollView(.horizontal) {
                HStack { ForEach(photos, id: \.file) { evidence in PhotoThumb(name: evidence.file, evidence: evidence) { remove(evidence.file) } } }
            }
        }
    }
}

struct DocumentPreview: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.str) private var s
    let file: ExportedFile

    var body: some View {
        NavigationStack {
            LocalDocumentView(url: file.url)
                .navigationTitle(file.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(s.done) { dismiss() } } }
        }
    }
}

struct CompletionIssueKey: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.str) private var s
    @Environment(\.limen) private var colors
    let p: HandoverProtocol
    let issue: FinalizationIssue

    var body: some View {
        Button(action: open) {
            HStack {
                Text(s.finalizationIssue(issue)).font(LimenType.bodyMedium).foregroundStyle(colors.ink).multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.forward").foregroundStyle(colors.inkDim)
            }.padding(.vertical, 8).frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func open() {
        switch issue {
        case .noRooms, .rooms:
            model.goTo(.inspection)
            if let room = p.rooms.first(where: { !$0.inspected && (p.details.scopeNotes[$0.id] ?? "").isBlank }) { model.openRoom(room.id) }
        case .objects: model.goTo(.objects)
        case .defectText:
            if let defect = p.defects.first(where: { $0.text.isBlank }) { model.editDefect(defect.id) }
        case .recordOutcomes, .unilateralReason: model.goTo(.sign)
        case .parties: openDossier("parties")
        case .keys: openDossier(p.carries(.keys) ? "card-Keys" : "scope")
        case .dossier:
            if let defect = p.defects.first(where: { RecordInputValidation.invalidOptionalDate($0.fixDeadline) || p.details.estimates[$0.id]?.isValid == false }) {
                model.editDefect(defect.id)
            } else { openDossier(CompletionRules.incompleteDossierTarget(p)) }
        default: openDossier("object")
        }
    }

    private func openDossier(_ target: String) {
        model.dossierTarget = target
        model.goTo(.dossier)
    }
}

struct ExportHistoryPanel: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.str) private var s
    let p: HandoverProtocol
    @State private var preview: ExportedFile?
    @State private var share: ExportedFile?

    var body: some View {
        if !p.exportHistory.isEmpty {
            Panel(label: s.exported) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(p.exportHistory.enumerated()), id: \.offset) { _, copy in
                        Text(copy.name).font(LimenType.bodyMedium)
                        Text("\(copy.language) · \(copy.deliveryRevision) · \(Date(timeIntervalSince1970: Double(copy.epochMs) / 1000).formatted(date: .numeric, time: .shortened))").font(LimenType.bodySmall)
                        WeightedRow(weights: [1, 1]) {
                            SmallKey(label: s.open) { if let file = retained(copy) { preview = file } }
                            SmallKey(label: s.share) { if let file = retained(copy) { share = file } }
                        }
                    }
                }
            }
            .sheet(item: $preview) { file in DocumentPreview(file: file) }
            .sheet(item: $share) { file in ShareSheet(url: file.url) }
        }
    }

    private func retained(_ copy: ExportCopy) -> ExportedFile? {
        model.openExport(copy)
        guard let file = model.exported else { model.show(s.openFileFailed); return nil }
        return file
    }
}

private struct LocalDocumentView: View {
    let url: URL
    var body: some View {
        if url.pathExtension.lowercased() == "html" { StructuredDocumentView(url: url) } else if url.pathExtension.lowercased() == "pdf" { PDFPreview(url: url) } else { LocalQuickLook(url: url) }
    }
}

private struct StructuredDocumentView: UIViewRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        if view.url != url { view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()) }
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        let url: URL
        init(url: URL) { self.url = url }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            let target = navigationAction.request.url
            return target?.isFileURL == true && target?.path == url.path ? .allow : .cancel
        }
    }
}

private struct LocalQuickLook: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
    }
}
