import LimenKit
import SwiftUI

/// The landing offers choices, not an identity gate or a partially exposed case list.
struct HomeScreen: View {
    @Environment(LimenModel.self) private var model

    var body: some View {
        switch model.homePage {
        case .landing:
            LandingScreen()
        case .newSession:
            NewSessionScreen(
                entryToSeed: model.entryToSeedId.flatMap { id in model.protocols.first { $0.id == id } },
                // Back to where the form was opened from: an exit seeded from the session list
                // used to drop the operator on the landing, two taps away from the list it came from.
                onBack: {
                    let fromSessions = model.entryToSeedId != nil
                    model.entryToSeedId = nil
                    model.homePage = fromSessions ? .sessions : .landing
                }
            )
        case .sessions:
            SessionsScreen(onBack: { model.homePage = .landing }, onSeedExit: { entry in
                model.entryToSeedId = entry.id
                model.homePage = .newSession
            })
        case .dataPrivacy:
            DataPrivacyScreen(onBack: { model.homePage = .landing })
        }
    }
}

private struct LandingScreen: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 600
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    HStack {
                        LangMenu(current: model.lang) { model.selectLang($0) }
                        Spacer()
                        ThemeToggle(dark: model.darkTheme, description: s.themeMode) { model.toggleTheme() }
                    }
                    if compact { Spacer().frame(height: 12) } else { Spacer() }
                    LimenMark(size: compact ? 88 : 172)
                    Spacer().frame(height: compact ? 10 : 20)
                    Text("LIMEN").font(LimenType.displayLarge).tracking(-0.5).foregroundStyle(colors.onInk)
                    Spacer().frame(height: 10)
                    Text(s.welcomeLead)
                        .font(LimenType.bodyLarge)
                        .foregroundStyle(colors.onInk.opacity(0.88))
                        .multilineTextAlignment(.center)
                    if compact { Spacer().frame(height: 18) } else { Spacer() }
                    LandingKey(label: s.startNewSession) {
                        model.entryToSeedId = nil
                        model.homePage = .newSession
                    }
                    Spacer().frame(height: 10)
                    LandingKey(label: s.allSessions) { model.requestHomePage(.sessions) }
                    Spacer().frame(height: 10)
                    LandingKey(label: s.dataAndPrivacy) { model.requestHomePage(.dataPrivacy) }
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 24)
                .readable()
                .frame(minHeight: compact ? nil : geometry.size.height)
            }
        }
        .background(colors.landing.ignoresSafeArea())
    }
}

private struct LandingKey: View {
    @Environment(\.limen) private var colors
    let label: String
    var enabled = true
    let onPress: () -> Void

    var body: some View {
        KeySurface(enabled: enabled, radius: 12, fillColor: colors.plate, outlineColor: colors.onInk, onPress: onPress) {
            Text(label)
                .font(LimenType.labelLarge)
                .tracking(0.3)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(enabled ? colors.ink : colors.disabledInk)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The masthead every home page but the landing carries: back, the title, the two controls.
struct PageMast: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    let title: String?
    var controls = true
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            IconKey(glyph: .back, label: s.back, onPress: onBack)
            if let title {
                Text(title).font(LimenType.titleMedium).foregroundStyle(colors.ink).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if controls {
                LangMenu(current: model.lang) { model.selectLang($0) }
                Spacer().frame(width: 4)
                ThemeToggle(dark: model.darkTheme, description: s.themeMode) { model.toggleTheme() }
            }
        }
    }
}

private struct SessionsScreen: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    let onBack: () -> Void
    let onSeedExit: (HandoverProtocol) -> Void

    @State private var query = ""
    @State private var filter = "all"

    private var filtered: [HandoverProtocol] {
        model.protocols.filter { record in
            let search = [record.address, record.place, record.handoverDate, SwissDate.display(record.handoverDate)] + record.parties.map(\.name)
            let matches = query.isBlank || search.contains { $0.localizedCaseInsensitiveContains(query) }
            return matches && (filter == "all" || (filter == "draft" && !record.isFinalized()) || (filter == "final" && record.isFinalized()) || record.kind.rawValue == filter)
        }
    }

    private var groupKeys: [String] { filtered.map(groupKey).distinct() }

    private func groupKey(_ record: HandoverProtocol) -> String {
        [record.address.ifBlank(s.noAddress), record.place, record.objectDetail].filter { !$0.isBlank }.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 10) {
            PageMast(title: s.allSessions, onBack: onBack)
            Field(label: s.searchRecords, value: query) { query = $0 }
            PillRow(options: [("all", s.allRecords), ("draft", s.draft), ("final", s.finalized), (Kind.entry.rawValue, s.entry), (Kind.exit.rawValue, s.exit)], current: filter) { filter = $0 }
            if model.libraryLoading { ProgressView(s.working) }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.unreadableRecords, id: \.id) { record in
                        Panel(label: s.unreadableRecord, warning: true) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(record.id).font(LimenType.bodySmall).textSelection(.enabled)
                                if record.hasRecovery { SmallKey(label: s.recover) { model.recoverRecord(record.id) } }
                            }
                        }
                    }
                    if filtered.isEmpty { Text(s.sessionsEmpty).font(LimenType.bodyLarge).foregroundStyle(colors.inkDim) }
                    ForEach(groupKeys, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group).font(LimenType.labelLarge).foregroundStyle(colors.inkDim).accessibilityAddTraits(.isHeader)
                            ForEach(filtered.filter { groupKey($0) == group }, id: \.id) { record in ProtocolCard(p: record, onSeedExit: onSeedExit) }
                        }
                    }
                }
            }
            .refreshable { model.refreshLibrary() }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .readable()
        .background(colors.plate.ignoresSafeArea())
        .task { model.refreshLibrary() }
    }
}

/// One dossier: what, where, when, and how far it got. Delete asks twice, quietly.
private struct ProtocolCard: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    let p: HandoverProtocol
    let onSeedExit: (HandoverProtocol) -> Void
    @State private var armed = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        // The status chip: the one place the seal colour is allowed to appear.
        let status: (String, Bool) = {
            if p.isFinalized(), p.isExported(), p.deliveryComplete() { return (s.copyDelivery, true) }
            if p.isFinalized(), p.isExported() { return (s.exported, true) }
            if p.isFinalized() { return (s.finalized, true) }
            if p.isSigned() { return (s.awaitingSignatures, false) }
            return (s.draft, false)
        }()
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Haptics.play(.key)
                model.openProtocol(p.id)
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.address.ifBlank(s.noAddress)).font(LimenType.titleMedium).fixedSize(horizontal: false, vertical: true).foregroundStyle(colors.ink)
                        Text([p.kind == .entry ? s.entry : s.exit, SwissDate.display(p.handoverDate), p.place].filter { !$0.isBlank }.joined(separator: " · "))
                            .font(LimenType.labelSmall).fixedSize(horizontal: false, vertical: true).foregroundStyle(colors.inkDim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(status.0.uppercased())
                        .font(LimenType.labelSmall)
                        .foregroundStyle(status.1 ? colors.onSeal : colors.inkDim)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(status.1 ? colors.seal : colors.input, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(colors.actionOutline, lineWidth: 1))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 6) {
                if p.kind == .entry {
                    let canCreateExit = p.isFinalized()
                    Chip(label: canCreateExit ? s.exitFromThis : s.finalizeEntryFirst, dim: !canCreateExit, enabled: canCreateExit) { onSeedExit(p) }
                }
                Spacer()
                Chip(label: armed ? s.sure : s.delete, active: armed, tick: armed ? .reject : .key, destructive: true) {
                    if armed { model.deleteProtocol(p.id) } else { armed = true }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(colors.plateRaised)
        .clipShape(shape)
        .overlay(shape.strokeBorder(colors.actionOutline, lineWidth: 1.5))
        .onChange(of: p.id) { _, _ in armed = false }
    }
}
