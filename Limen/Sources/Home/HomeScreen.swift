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
            ScrollView(compact ? .vertical : []) {
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
                    LandingKey(label: s.allSessions, enabled: !model.protocols.isEmpty) { model.homePage = .sessions }
                    Spacer().frame(height: 10)
                    LandingKey(label: s.dataAndPrivacy) { model.homePage = .dataPrivacy }
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
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
                Text(title).font(LimenType.titleMedium).foregroundStyle(colors.ink).lineLimit(1).minimumScaleFactor(0.7)
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

    var body: some View {
        VStack(spacing: 0) {
            PageMast(title: s.allSessions, onBack: onBack)
            Spacer().frame(height: 14)
            if model.protocols.isEmpty {
                Text(s.sessionsEmpty).font(LimenType.bodyLarge).foregroundStyle(colors.inkDim)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.protocols, id: \.id) { p in
                            ProtocolCard(p: p, onSeedExit: onSeedExit)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .readable()
        .background(colors.plate.ignoresSafeArea())
        .onChange(of: model.protocols.isEmpty) { _, empty in if empty { onBack() } }
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
                        Text(p.address.ifBlank(s.noAddress)).font(LimenType.titleMedium).lineLimit(1).foregroundStyle(colors.ink)
                        Text([p.kind == .entry ? s.entry : s.exit, SwissDate.display(p.handoverDate), p.place].filter { !$0.isBlank }.joined(separator: " · "))
                            .font(LimenType.labelSmall).lineLimit(1).foregroundStyle(colors.inkDim)
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
