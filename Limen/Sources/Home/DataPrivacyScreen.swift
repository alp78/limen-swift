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
    @State private var archiveAction: ArchiveAction?
    @State private var pendingRestore: URL?
    @State private var picking = false
    // Deliberately not persisted anywhere: a backup password is the one thing in this app that
    // must not go near saved state. The cost is retyping it after a rotation.
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        let controller = model.controllerIdentity
        VStack(spacing: 0) {
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
                    Panel(label: s.controllerTitle) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(s.controllerBody).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                            Field(label: s.organisation, value: controller.organisation, onChange: update { $0.organisation = $1 })
                            Field(label: s.controllerContact, value: controller.contactName, onChange: update { $0.contactName = $1 })
                            Field(label: s.street, value: controller.street, onChange: update { $0.street = $1 })
                            HStack(alignment: .top, spacing: 8) {
                                Field(label: s.postalCode, value: controller.postalCode, onChange: update { $0.postalCode = $1 }).frame(width: 120)
                                Field(label: s.city, value: controller.city, onChange: update { $0.city = $1 })
                            }
                            HStack(alignment: .top, spacing: 8) {
                                Field(label: s.email, value: controller.email, keyboard: .emailAddress, onChange: update { $0.email = $1 })
                                Field(label: s.phoneNumber, value: controller.phone, keyboard: .phonePad, onChange: update { $0.phone = $1 })
                            }
                        }
                    }
                    Panel(label: s.backupTitle) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(s.backupBody).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                            HStack(spacing: 8) {
                                SmallKey(label: s.createBackup, enabled: !model.archiveBusy, stretch: true) {
                                    password = ""
                                    confirmation = ""
                                    archiveAction = .export
                                }
                                SmallKey(label: s.restoreBackup, enabled: !model.archiveBusy, stretch: true) { picking = true }
                            }
                            if model.archiveBusy {
                                Text(s.working).font(LimenType.bodySmall).foregroundStyle(colors.inkDim)
                            } else if model.archiveFailed {
                                Text(s.archiveFailed).font(LimenType.bodySmall).foregroundStyle(colors.dangerOutline)
                            } else if let exported = model.archiveExported {
                                Text(s.archiveSaved(exported.displayName)).font(LimenType.bodySmall).foregroundStyle(colors.seal)
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
        .background(colors.plate.ignoresSafeArea())
        .fileImporter(isPresented: $picking, allowedContentTypes: [.zip, .data]) { result in
            if case .success(let url) = result {
                pendingRestore = url
                password = ""
                archiveAction = .import
            }
        }
        .alert(archiveAction == .export ? s.protectBackup : s.unlockBackup, isPresented: Binding(get: { archiveAction != nil }, set: { if !$0 { archiveAction = nil } })) {
            SecureField(s.backupPassword, text: $password)
            if archiveAction == .export {
                SecureField(s.confirmBackupPassword, text: $confirmation)
            }
            Button(archiveAction == .export ? s.createBackup : s.restoreBackup) {
                let isExport = archiveAction == .export
                let valid = !password.isBlank && (!isExport || (password.count >= 12 && password == confirmation))
                if valid {
                    if isExport {
                        model.exportArchive(password: password)
                    } else if let url = pendingRestore {
                        model.importArchive(url, password: password)
                    }
                }
                archiveAction = nil
                pendingRestore = nil
                password = ""
                confirmation = ""
            }
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
