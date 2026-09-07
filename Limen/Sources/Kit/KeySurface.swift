import LimenKit
import SwiftUI

/// The shared action surface. The visual depth is deliberately part of the control itself: a
/// lighter top, the palette colour through its face, and a darker lower edge. On touch the face
/// travels down into that edge, making the pressed state legible without changing Limen's
/// approved palette.
struct KeySurface<Content: View>: View {
    @Environment(\.limen) private var colors
    var active = false
    var enabled = true
    var radius: CGFloat = 12
    var fillColor: Color?
    var outlineColor: Color?
    var tick: Tick = .key
    var accessibilityLabel: String?
    let onPress: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        let fill: Color = !enabled && !active ? colors.disabled : (fillColor ?? (active ? colors.action : colors.input))
        // Neutral keys stay neutral in both schemes. Using the action outline here was the
        // source of the stray light-blue lower rule on dark secondary buttons.
        let outline: Color = !enabled && !active ? colors.plateEdge : (outlineColor ?? (active ? colors.action : colors.plateEdge))
        Button {
            Haptics.play(tick)
            onPress()
        } label: {
            content()
        }
        .buttonStyle(KeyStyle(fill: fill, outline: outline, radius: radius, enabled: enabled, dark: colors.isDark))
        .disabled(!enabled)
        .modifier(OptionalLabel(label: accessibilityLabel))
    }
}

/// Only when a label is given: an empty accessibility label erases the text the button carries.
private struct OptionalLabel: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label { content.accessibilityLabel(label) } else { content }
    }
}

private struct KeyStyle: ButtonStyle {
    let fill: Color
    let outline: Color
    let radius: CGFloat
    let enabled: Bool
    let dark: Bool

    func makeBody(configuration: Configuration) -> some View {
        // A smaller lower edge in night mode keeps the visible face the same weight as an active
        // blue key, without the light lower rule that made neutral keys look shorter.
        let depth: CGFloat = !enabled || dark ? 2 : 3
        let pressed = configuration.isPressed && enabled
        let topLight = fill.lifted(dark ? 0.18 : 0.30)
        let lowerTone = fill.shaded(dark ? 0.18 : 0.12)
        let edge = fill.shaded(enabled ? 0.16 : 0.08)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        // The face is a background of the label, never a sibling: a shape beside the label in a
        // stack takes every point it is offered, and the key grew to fill its row.
        configuration.label
            .offset(y: pressed ? depth : 0)
            .padding(.bottom, depth)
            .frame(minWidth: 48, minHeight: 48)
            .background {
                ZStack {
                    shape.fill(edge)
                    VStack(spacing: 0) {
                        shape
                            .fill(LinearGradient(stops: [.init(color: topLight, location: 0), .init(color: fill, location: 0.36), .init(color: lowerTone, location: 1)], startPoint: .top, endPoint: .bottom))
                            // A full stroke includes a horizontal rule at the lower face edge. On
                            // dark fills it read as a stray line, so the night treatment relies on the edge.
                            .overlay(dark ? nil : shape.strokeBorder(outline, lineWidth: 1))
                        Color.clear.frame(height: depth)
                    }
                    .offset(y: pressed ? depth : 0)
                }
            }
            .clipShape(shape)
            .contentShape(shape)
        .animation(.easeOut(duration: 0.09), value: pressed)
    }
}

/// Universal controls use the familiar glyph instead of repeating a text label.
enum ButtonGlyph {
    case add, remove, delete, edit, camera, gallery, back, next, confirm, cancel, clear, share, open, calendar, clock

    var symbol: String {
        switch self {
        case .add: return "plus"
        case .remove: return "minus"
        case .delete: return "trash"
        case .edit: return "pencil"
        case .camera: return "camera"
        case .gallery: return "photo.on.rectangle"
        case .back: return "arrow.backward"
        case .next: return "arrow.forward"
        case .confirm: return "checkmark"
        case .cancel: return "xmark"
        case .clear: return "arrow.counterclockwise"
        case .share: return "square.and.arrow.up"
        case .open: return "arrow.up.forward.square"
        case .calendar: return "calendar"
        case .clock: return "clock"
        }
    }
}

struct IconKey: View {
    @Environment(\.limen) private var colors
    let glyph: ButtonGlyph
    let label: String
    var enabled = true
    var destructive = false
    var fillColor: Color?
    var outlineColor: Color?
    var tint: Color?
    // A destructive key rejects by default. Leaving this to each call site meant six of the twelve
    // delete and clear keys felt like an ordinary press, which is the one thing .reject exists to
    // prevent. Pass it explicitly to override, as the armed two-stage delete on the home screen
    // does. Optional rather than defaulted, because a Swift default cannot read another property.
    var tick: Tick?
    var stretch = false
    let onPress: () -> Void

    var body: some View {
        let resolvedFill = destructive ? colors.danger : fillColor
        let resolvedOutline = destructive ? colors.dangerOutline : outlineColor
        let resolvedTint = destructive ? colors.dangerOutline : tint
        let resolvedTick = tick ?? (destructive ? .reject : .key)
        KeySurface(enabled: enabled, radius: 12, fillColor: resolvedFill, outlineColor: resolvedOutline, tick: resolvedTick, accessibilityLabel: label, onPress: onPress) {
            Image(systemName: glyph.symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(enabled ? (resolvedTint ?? colors.ink) : colors.disabledInk)
                .frame(width: 20, height: 20)
                .frame(maxWidth: stretch ? .infinity : nil)
                .padding(14)
        }
        .frame(maxWidth: stretch ? .infinity : nil)
    }
}

/// A transport-sized primary action.
struct BigKey: View {
    @Environment(\.limen) private var colors
    let label: String
    var active = true
    var tick: Tick = .key
    var enabled = true
    let onPress: () -> Void

    var body: some View {
        KeySurface(active: active && enabled, enabled: enabled, radius: 12, tick: tick, onPress: onPress) {
            Text(label)
                .font(LimenType.key)
                .tracking(0.8)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(active && enabled ? colors.onInk : (enabled ? colors.ink : colors.disabledInk))
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The transport keys' smaller sibling, outlined for secondary actions.
struct SmallKey: View {
    @Environment(\.limen) private var colors
    let label: String
    var tick: Tick = .key
    var enabled = true
    var stretch = false
    let onPress: () -> Void

    var body: some View {
        KeySurface(enabled: enabled, radius: 10, tick: tick, onPress: onPress) {
            Text(label)
                .font(LimenType.smallKey)
                .tracking(0.4)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(enabled ? colors.ink : colors.disabledInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .frame(maxWidth: stretch ? .infinity : nil)
        }
        .frame(maxWidth: stretch ? .infinity : nil)
    }
}

/// One small choice: the pills, chips and state markers all press like this.
struct Chip: View {
    @Environment(\.limen) private var colors
    let label: String
    var active = false
    var dim = true
    var tick: Tick = .key
    var enabled = true
    var destructive = false
    var selectionState: Bool?
    var stretch = false
    let onPress: () -> Void

    var body: some View {
        let destructiveFill: Color? = destructive ? (active ? colors.dangerOutline : colors.danger) : nil
        let ink: Color = {
            if destructive && active { return colors.onInk }
            if destructive { return colors.dangerOutline }
            if active { return colors.onInk }
            if !enabled { return colors.disabledInk }
            return dim ? colors.inkDim : colors.ink
        }()
        KeySurface(active: active && !destructive, enabled: enabled, radius: 10, fillColor: destructiveFill, outlineColor: destructive ? colors.dangerOutline : nil, tick: tick, onPress: onPress) {
            Text(label)
                .font(LimenType.chip)
                .tracking(0.3)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: stretch ? .infinity : nil)
        }
        .frame(maxWidth: stretch ? .infinity : nil)
        .accessibilityAddTraits(selectionState == true ? .isSelected : [])
    }
}

/// A row of options as pills, the house selector: languages, protocol styles, deposit kinds.
struct PillRow<T: Hashable>: View {
    let options: [(T, String)]
    let current: T
    var dense = false
    var enabled = true
    let onSelect: (T) -> Void

    var body: some View {
        FlowRow(spacing: dense ? 5 : 6) {
            ForEach(options, id: \.0) { value, label in
                Chip(label: label, active: value == current, enabled: enabled && value != current, selectionState: value == current) { onSelect(value) }
            }
        }
    }
}

/// Compose's FlowRow: rows of chips that wrap when the width runs out.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: width == .infinity ? maxX : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// A count with its two keys: keys are counted, never typed, at the door.
struct Stepper: View {
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    let count: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            IconKey(glyph: .remove, label: s.decrease, enabled: count >= 1) { if count >= 1 { onChange(count - 1) } }
            Text(String(count))
                .font(LimenType.mono(17))
                .foregroundStyle(colors.ink)
                .padding(.horizontal, 14)
            IconKey(glyph: .add, label: s.increase) { onChange(count + 1) }
        }
    }
}

/// A labelled switch for persistent on/off choices.
struct Toggle: View {
    @Environment(\.limen) private var colors
    let label: String
    let on: Bool
    var dense = false
    var enabled = true
    let onPress: () -> Void

    var body: some View {
        // Pressing a switch that is on turns it off, so the weight names the state it lands in.
        KeySurface(enabled: enabled, radius: 10, tick: on ? .toggleOff : .toggleOn, accessibilityLabel: label, onPress: onPress) {
            HStack {
                Text(label)
                    .font(LimenType.chip)
                    .tracking(0.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(colors.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: on ? .trailing : .leading) {
                    Capsule().fill(on ? colors.action : colors.plateEdge).frame(width: 42, height: 24)
                    Circle().fill(on ? colors.onInk : colors.inkDim).frame(width: 18, height: 18).padding(3)
                }
                .animation(.easeOut(duration: 0.15), value: on)
            }
            .padding(.horizontal, dense ? 10 : 13)
            .padding(.vertical, dense ? 7 : 9)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(on ? "1" : "0")
    }
}

/// The one prominent action a place offers, coloured for what it does.
struct RoomActionKey: View {
    let label: String
    let fill: Color
    let outline: Color
    let text: Color
    var glyph: ButtonGlyph?
    var stretch = true
    let onPress: () -> Void

    var body: some View {
        KeySurface(radius: 10, fillColor: fill, outlineColor: outline, onPress: onPress) {
            HStack(spacing: 8) {
                if let glyph {
                    Image(systemName: glyph.symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(text)
                }
                Text(label)
                    .font(LimenType.labelLarge)
                    .tracking(0.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(text)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: stretch ? .infinity : nil)
        }
        .frame(maxWidth: stretch ? .infinity : nil)
    }
}
