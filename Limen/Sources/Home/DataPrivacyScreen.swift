import LimenKit
import SwiftUI
import UniformTypeIdentifiers

private enum ArchiveAction: Identifiable {
    case export, `import`
    var id: Int { self == .export ? 0 : 1 }
}

struct DataPrivacyScreen: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    let onBack: () -> Void
    @State private var showLicences = false
    @State private var archiveAction: ArchiveAction?
    @State private var pendingRestore: URL?
    @State private var picking = false
    // Deliberately not persisted anywhere: a backup password is the one thing in this app that
    // must not go near saved state. The cost is retyping it after a rotation.
    @State private var password = ""
    @State private var confirmation = ""
    @State private var plainConfirmation = false
    @State private var sharing: ExportedFile?

    var body: some View {
        if showLicences {
            LicencesView { showLicences = false }
        } else {
            page
        }
    }

    private var page: some View {
        let controller = model.controllerIdentity
        return VStack(spacing: 0) {
            PageMast(title: s.dataAndPrivacy, controls: false, onBack: onBack)
            Spacer().frame(height: 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Panel(label: s.privacyTitle) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(s.privacyParagraphs.enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                            }
                        }
                    }
                    Panel(label: s.libraryProtection) {
                        Toggle(label: s.libraryProtection, on: model.libraryProtectionEnabled) { model.setLibraryProtectionEnabled(!model.libraryProtectionEnabled) }
                    }
                    Panel(label: s.controllerTitle) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(s.controllerBody).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                            Field(label: s.organisation, value: controller.organisation, onChange: update { $0.organisation = $1 })
                            Field(label: s.controllerContact, value: controller.contactName, onChange: update { $0.contactName = $1 })
                            Field(label: s.street, value: controller.street, onChange: update { $0.street = $1 })
                            WeightedRow(weights: [0.38, 0.62]) {
                                Field(label: s.postalCode, value: controller.postalCode, onChange: update { $0.postalCode = $1 })
                                Field(label: s.city, value: controller.city, onChange: update { $0.city = $1 })
                            }
                            HStack(alignment: .top, spacing: 8) {
                                Field(label: s.email, value: controller.email, keyboard: .emailAddress, onChange: update { $0.email = $1 })
                                Field(label: s.phoneNumber, value: controller.phone, keyboard: .phonePad, onChange: update { $0.phone = $1 })
                            }
                        }
                    }
                    Panel(label: s.licencesTitle) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(s.licencesBody).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                            SmallKey(label: s.openLicences, stretch: true) { showLicences = true }
                        }
                    }
                    Panel(label: s.backupTitle) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(s.backupBody).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                            ArchiveScopePicker()
                            WeightedRow(weights: [1, 1]) {
                                SmallKey(label: s.createBackup, enabled: !model.archiveBusy, stretch: true) {
                                    password = ""
                                    confirmation = ""
                                    archiveAction = .export
                                }
                                SmallKey(label: s.restoreBackup, enabled: !model.archiveBusy, stretch: true) { picking = true }
                            }
                            SmallKey(label: s.plainArchive, enabled: !model.archiveBusy, stretch: true) { plainConfirmation = true }
                            if model.archiveBusy {
                                Text(s.working).font(LimenType.bodySmall).foregroundStyle(colors.inkDim)
                            } else if model.archiveFailed {
                                Text(s.archiveFailed).font(LimenType.bodySmall).foregroundStyle(colors.dangerOutline)
                            } else if let exported = model.archiveExported {
                                Text(model.archiveProtected ? s.archiveSaved(exported.displayName) : s.archiveSavedOpen(exported.displayName))
                                    .font(LimenType.bodySmall)
                                    .foregroundStyle(model.archiveProtected ? colors.seal : colors.warningOutline)
                                SmallKey(label: s.share, stretch: true) { sharing = exported }
                            } else if let imported = model.archiveImported {
                                Text(s.archiveRestored(imported)).font(LimenType.bodySmall).foregroundStyle(colors.seal)
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            Spacer().frame(height: 16)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .readable()
        .background(colors.plate.ignoresSafeArea())
        .fileImporter(isPresented: $picking, allowedContentTypes: [.zip, .data]) { result in
            switch result {
            case .success(let url):
                pendingRestore = url
                password = ""
                archiveAction = .import
            case .failure(let error):
                let failure = error as NSError
                if failure.domain != NSCocoaErrorDomain || failure.code != NSUserCancelledError {
                    model.evidenceError = error.localizedDescription
                }
            }
        }
        .sheet(item: $sharing) { file in ShareSheet(url: file.url) }
        .confirmDialog($plainConfirmation, body: s.plainArchiveWarning) { model.exportArchive(password: "") }
        .alert(archiveAction == .export ? s.protectBackup : s.unlockBackup, isPresented: Binding(get: { archiveAction != nil }, set: { if !$0 { archiveAction = nil } })) {
            // This export path always requires a nonempty, matching password. Plain export has
            // its own explicit warning and confirmation. A plain archive can be restored with
            // an empty password, while an encrypted one is authenticated by the archive reader.
            let isExport = archiveAction == .export
            let valid = !isExport || (!password.isEmpty && password == confirmation)
            SecureField(s.backupPassword, text: $password)
            if isExport {
                SecureField(s.confirmBackupPassword, text: $confirmation)
            }
            Button(isExport ? s.createBackup : s.restoreBackup) {
                if isExport {
                    model.exportArchive(password: password)
                } else if let url = pendingRestore {
                    model.importArchive(url, password: password)
                }
                archiveAction = nil
                pendingRestore = nil
                password = ""
                confirmation = ""
            }
            .disabled(!valid)
            Button(s.cancel, role: .cancel) {
                archiveAction = nil
                pendingRestore = nil
                password = ""
                confirmation = ""
            }
        } message: {
            Text(archiveAction == .export ? s.backupPasswordBody : s.restorePasswordBody)
        }
    }

    private func update(_ change: @escaping (inout ControllerIdentity, String) -> Void) -> (String) -> Void {
        { value in
            var next = model.controllerIdentity
            change(&next, value)
            model.updateController(next)
        }
    }
}

/// The third-party notice, read from the repo's NOTICE, which the app target carries as a bundle
/// resource rather than a second copy under the sources: Apache-2.0 section 4(d) asks for it to
/// travel with the distribution, and two hand-maintained copies of a licence notice drift apart.
///
/// Verbatim and unlocalized on purpose: a licence text that has been translated or reflowed is no
/// longer the licence text. It scrolls both ways because the notice is written to a fixed column a
/// phone is narrower than.
///
/// Its own screen rather than a panel: the notice is several thousand characters and the privacy
/// page is already a scrolling column, which cannot hold a second one.
///
/// Not capped at the readable width, unlike every other screen. NOTICE is a preformatted
/// monospace document that already needs a horizontal scroll on a phone, so narrowing it on a
/// tablet would take away the one thing the extra width is good for here.
private struct LicencesView: View {
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    let onBack: () -> Void

    /// Read once for the life of the process. The body runs again on every scroll, theme change
    /// and rotation, and this was a file read plus a decode of the whole notice each time.
    private static let notice: String = Bundle.main.url(forResource: "NOTICE", withExtension: nil)
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""

    var body: some View {
        let notice = Self.notice.isEmpty ? s.licencesMissing : Self.notice
        VStack(spacing: 0) {
            PageMast(title: s.licencesTitle, controls: false, onBack: onBack)
            Spacer().frame(height: 14)
            ScrollView([.vertical, .horizontal]) {
                Text(notice)
                    .font(LimenType.mono(11))
                    .foregroundStyle(colors.ink)
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(.bottom, 24)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(colors.plate.ignoresSafeArea())
    }
}

private struct ArchiveScopePicker: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.str) private var s

    var body: some View {
        DisclosureGroup(s.allSessions) {
            VStack(spacing: 8) {
                SmallKey(label: s.selectAll) { model.archiveSelection = [] }
                ForEach(model.protocols, id: \.id) { record in
                    let included = model.archiveSelection.isEmpty || model.archiveSelection.contains(record.id)
                    Toggle(label: "\(record.address.ifBlank(s.noAddress)) · \(SwissDate.display(record.handoverDate))", on: included, enabled: model.protocols.count > 1) {
                        if model.archiveSelection.isEmpty { model.archiveSelection = Set(model.protocols.map(\.id)) }
                        if included {
                            if model.archiveSelection.count > 1 { model.archiveSelection.remove(record.id) }
                        } else { model.archiveSelection.insert(record.id) }
                    }
                }
            }.padding(.top, 8)
        }
    }
}
