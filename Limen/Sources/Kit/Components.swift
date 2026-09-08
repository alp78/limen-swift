import LimenKit
import SwiftUI

/// The house info affordance: anything that needs explaining lives behind this, never in small
/// print. The mark comes from the symbol set, like every other control in the app.
struct InfoTip: View {
    @Environment(\.limen) private var colors
    let tip: Tip
    var target: CGFloat = 40
    @State private var open = false

    var body: some View {
        Button {
            Haptics.play(.key)
            open = true
        } label: {
            // Forty points of target around an eighteen point mark: the padding is transparent,
            // so the panel looks the same and a thumb can still hit it.
            Image(systemName: "info.circle")
                .font(.system(size: 18))
                .foregroundStyle(colors.actionOutline)
                .frame(width: target, height: target)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tip.lead)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(tip.lead).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                ForEach(Array(tip.bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                        Text(bullet).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                    }
                }
            }
            .padding(16)
            .frame(idealWidth: 320, maxWidth: 360)
            .presentationCompactAdaptation(.popover)
            .presentationBackground(colors.plateRaised)
        }
    }
}

/// What a key just opened. When a control reveals fields, the fields wash once with a neutral
/// highlight and a marker runs down their left edge, then both settle: the eye follows the change
/// to where it went instead of hunting for what moved.
///
/// Deliberately ONE treatment rather than a colour per option. In this instrument colour is a
/// statement, and the seal means signed; painting the bank fields blue and the insurance fields
/// amber would say those states differ in kind, which they do not.
struct Revealed<Key: Equatable, Content: View>: View {
    @Environment(\.limen) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let key: Key
    @ViewBuilder let content: () -> Content
    @State private var progress: Double = 1

    var body: some View {
        content()
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.actionOutline.opacity(0.08 * progress))
            .overlay(alignment: .topLeading) {
                // The marker: full height at the start, retracting upward as the wash fades.
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 1.2)
                        .fill(colors.actionOutline.opacity(0.6 * progress))
                        .frame(width: 2.4, height: geometry.size.height * progress)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onChange(of: key, initial: true) { _, _ in
                progress = 1
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.7)) { progress = 0 }
            }
    }
}

/// A raised panel with its stamped label; findings can use the warning treatment.
struct Panel<Content: View>: View {
    @Environment(\.limen) private var colors
    let label: String
    var info: Tip?
    var warning = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                Text(label).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                if let info { InfoTip(tip: info) }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(warning ? colors.warning : colors.plateRaised)
        .clipShape(shape)
        .overlay(shape.strokeBorder(warning ? colors.warningOutline : colors.actionOutline, lineWidth: 1.5))
    }
}

/// The language menu: one compact key showing the current language, the five spelled out behind
/// it. Each name is written in its own language, so it never needs translating and is findable by
/// someone lost in the wrong one.
struct LangMenu: View {
    @Environment(\.limen) private var colors
    let current: Lang
    let onSelect: (Lang) -> Void

    var body: some View {
        Menu {
            ForEach(Lang.allCases, id: \.self) { lang in
                Button {
                    Haptics.play(.key)
                    onSelect(lang)
                } label: {
                    if lang == current {
                        Label(lang.ownName, systemImage: "checkmark")
                    } else {
                        Text(lang.ownName)
                    }
                }
            }
        } label: {
            Text("\(current.rawValue.uppercased()) ▾")
                .font(LimenType.chip)
                .tracking(0.3)
                .foregroundStyle(colors.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
        }
        .buttonStyle(MenuKeyStyle(fill: colors.input, edge: colors.input.shaded(0.16), dark: colors.isDark))
        .accessibilityLabel(current.ownName)
    }
}

/// The key face for a menu's label, which cannot be a KeySurface because the menu owns the tap.
private struct MenuKeyStyle: ButtonStyle {
    let fill: Color
    let edge: Color
    let dark: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        configuration.label
            .padding(.bottom, dark ? 2 : 3)
            .background {
                ZStack(alignment: .top) {
                    shape.fill(edge)
                    shape.fill(LinearGradient(colors: [fill.lifted(dark ? 0.18 : 0.30), fill, fill.shaded(dark ? 0.18 : 0.12)], startPoint: .top, endPoint: .bottom))
                        .padding(.bottom, dark ? 2 : 3)
                }
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Compact mode control: the system's own track and thumb shape, with the sun or the moon in it.
struct ThemeToggle: View {
    @Environment(\.limen) private var colors
    let dark: Bool
    let description: String
    let onToggle: () -> Void

    var body: some View {
        Button {
            // The switch is the one control on the screen that is not a KeySurface, so the weight
            // comes from here. It names the state the press lands in, as every other switch does.
            Haptics.play(dark ? .toggleOff : .toggleOn)
            onToggle()
        } label: {
            ZStack(alignment: dark ? .trailing : .leading) {
                Capsule().fill(dark ? colors.action : colors.plateEdge).frame(width: 52, height: 32)
                ZStack {
                    Circle().fill(dark ? colors.onInk : colors.plate).frame(width: 26, height: 26)
                    Image(systemName: dark ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(dark ? colors.action : Color(hex: 0x07204A))
                }
                .padding(3)
            }
            .animation(.easeOut(duration: 0.15), value: dark)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(description)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(dark ? "1" : "0")
    }
}

/// The fixed Limen seal, drawn from the supplied SVG master.
struct LimenMark: View {
    var size: CGFloat = 30

    var body: some View {
        Image("limen-seal")
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A bundled Drymos-source flag used only to identify a canton beside readable text.
struct CantonFlag: View {
    @Environment(\.limen) private var colors
    let canton: SwissCanton?
    var label: String?
    var size: CGFloat = 20

    var body: some View {
        if let canton {
            let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
            Image("flag-\(canton.code.lowercased())")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: size, height: size)
                .background(colors.input)
                .clipShape(shape)
                .overlay(shape.strokeBorder(colors.plateEdge, lineWidth: 1))
                .accessibilityLabel(label ?? "")
                .accessibilityHidden(label == nil)
        }
    }
}

/// The object canton, with the complete flag grid one tap away.
struct CantonPicker: View {
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let selected: SwissCanton?
    let onSelect: (SwissCanton) -> Void
    @State private var open = false

    var body: some View {
        KeySurface(enabled: !locked, radius: 10, accessibilityLabel: s.selectCanton, onPress: { open = true }) {
            HStack(spacing: 10) {
                CantonFlag(canton: selected, size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.cantonLabel).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                    Text(selected.map(s.canton) ?? s.selectCanton)
                        .font(LimenType.bodyMedium)
                        .foregroundStyle(colors.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down").foregroundStyle(colors.inkDim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $open) {
            CantonGrid(selected: selected) { canton in
                onSelect(canton)
                open = false
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(colors.plateRaised)
        }
    }
}

private struct CantonGrid: View {
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    let selected: SwissCanton?
    let onSelect: (SwissCanton) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(s.selectCanton).font(LimenType.titleMedium).foregroundStyle(colors.ink)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(SwissCanton.allCases, id: \.self) { canton in
                        KeySurface(active: canton == selected, radius: 12, accessibilityLabel: s.canton(canton), onPress: { onSelect(canton) }) {
                            VStack(spacing: 4) {
                                CantonFlag(canton: canton, size: 26)
                                Text(canton.code)
                                    .font(LimenType.labelSmall.weight(.bold))
                                    .foregroundStyle(canton == selected ? colors.onInk : colors.ink)
                            }
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                        }
                        .frame(height: 64)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
    }
}

/// Asked before anything recorded is thrown away, and never for anything reversible.
struct ConfirmDialog: ViewModifier {
    @Environment(\.str) private var s
    @Binding var shown: Bool
    let body: String
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.alert(s.areYouSure, isPresented: $shown) {
            // Both answers are RoomActionKeys on Android and press like any key: the destructive
            // key that raised this question already played the refusal, and the question itself
            // is only answered. A system alert's buttons carry no tick of their own.
            Button(s.yes) {
                Haptics.play(.key)
                onConfirm()
            }
            Button(s.no, role: .cancel) { Haptics.play(.key) }
        } message: {
            Text(body)
        }
    }
}

extension View {
    func confirmDialog(_ shown: Binding<Bool>, body: String, onConfirm: @escaping () -> Void) -> some View {
        modifier(ConfirmDialog(shown: shown, body: body, onConfirm: onConfirm))
    }
}

struct DismissibleItemRow<Content: View>: View {
    @Environment(\.str) private var s
    let onRemove: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 6) {
            content().frame(maxWidth: .infinity, alignment: .leading)
            IconKey(glyph: .delete, label: s.delete, destructive: true, tick: .reject, onPress: onRemove)
        }
    }
}

/// A passing message, the Android toast: shown low on the screen, gone on its own.
struct NoticeBar: View {
    @Environment(\.limen) private var colors
    let text: String

    var body: some View {
        Text(text)
            .font(LimenType.bodyMedium)
            .foregroundStyle(colors.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.plateRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
    }
}
