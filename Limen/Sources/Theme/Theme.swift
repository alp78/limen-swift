import LimenKit
import SwiftUI
import UIKit

/// The product palette sampled from the Limen identity system. Both schemes stay neutral grey,
/// while the mark's navy becomes the consistent outline and action colour.
struct LimenColors: Equatable {
    let plate: Color
    let plateRaised: Color
    let input: Color
    let plateEdge: Color
    let actionOutline: Color
    let action: Color
    /// The fixed navy field used by the home landing in both display modes.
    let landing: Color
    /// All lettering. A fact, never a status.
    let ink: Color
    let inkDim: Color
    /// Lettering on top of an `ink` fill: the active pill, the pressed key.
    let onInk: Color
    /// Signed, agreed, settled. The only colour in the instrument.
    let seal: Color
    /// Lettering on a `seal` fill.
    let onSeal: Color
    let warning: Color
    let warningOutline: Color
    let positive: Color
    let onPositive: Color
    let danger: Color
    let dangerOutline: Color
    let disabled: Color
    let disabledInk: Color
    let isDark: Bool

    /// The day values live in `LimenPalette`, which the printed record reads too, so the screen
    /// and the paper cannot drift: a navy changed there changes both.
    static let day = LimenColors(
        plate: Color(hex: LimenPalette.plate), plateRaised: Color(hex: LimenPalette.plateRaised), input: Color(hex: LimenPalette.input), plateEdge: Color(hex: LimenPalette.plateEdge),
        actionOutline: Color(hex: LimenPalette.navy), action: Color(hex: LimenPalette.navy), landing: Color(hex: LimenPalette.navy),
        ink: Color(hex: LimenPalette.ink), inkDim: Color(hex: LimenPalette.inkDim), onInk: .white,
        seal: Color(hex: LimenPalette.navy), onSeal: .white,
        warning: Color(hex: LimenPalette.warning), warningOutline: Color(hex: LimenPalette.warningOutline),
        positive: Color(hex: LimenPalette.positive), onPositive: .white,
        danger: Color(hex: LimenPalette.danger), dangerOutline: Color(hex: LimenPalette.dangerOutline),
        disabled: Color(hex: LimenPalette.plateRaised), disabledInk: Color(hex: LimenPalette.disabledInk), isDark: false
    )

    static let night = LimenColors(
        plate: Color(hex: 0x1C1F24), plateRaised: Color(hex: 0x2A2D33), input: Color(hex: 0x24272D), plateEdge: Color(hex: 0x3A3E46),
        actionOutline: Color(hex: 0x7C93C4), action: Color(hex: 0x4863A0), landing: Color(hex: 0x233350),
        ink: Color(hex: 0xF2F3F5), inkDim: Color(hex: 0xA7ADB8), onInk: .white,
        seal: Color(hex: 0x4863A0), onSeal: .white,
        warning: Color(hex: 0x3A2D1C), warningOutline: Color(hex: 0xFFB74D),
        positive: Color(hex: 0x57C778), onPositive: Color(hex: 0x102216),
        danger: Color(hex: 0x3B262A), dangerOutline: Color(hex: 0xFF7878),
        disabled: Color(hex: 0x2A2D33), disabledInk: Color(hex: 0xAFB8C6), isDark: true
    )
}

private struct LimenColorsKey: EnvironmentKey {
    static let defaultValue = LimenColors.day
}

private struct StrKey: EnvironmentKey {
    static let defaultValue = Str(.en)
}

/// True while a finalized record is on screen. Everything in it can be walked into and read;
/// nothing in it can be changed, because its evidence fingerprint was computed over exactly what
/// it holds now. The way to change a signed record is an amendment, which is a new draft.
///
/// Held in the environment rather than passed down: every field on every screen has to honour
/// it, and a parameter that forty call sites can forget is a parameter that forty call sites will.
private struct RecordLockedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var limen: LimenColors {
        get { self[LimenColorsKey.self] }
        set { self[LimenColorsKey.self] = newValue }
    }

    var str: Str {
        get { self[StrKey.self] }
        set { self[StrKey.self] = newValue }
    }

    var recordLocked: Bool {
        get { self[RecordLockedKey.self] }
        set { self[RecordLockedKey.self] = newValue }
    }
}

/// Clear sans hierarchy for field work, with monospaced figures where readings and dates need to
/// line up at a glance. The system face through `Font.custom(relativeTo:)`, the one form SwiftUI
/// scales live with the size setting, which is the sp contract Android's text had.
enum LimenType {
    private static func sans(_ size: CGFloat, _ weight: Font.Weight, like style: Font.TextStyle) -> Font {
        Font.custom(".AppleSystemUIFont", size: size, relativeTo: style).weight(weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular, like style: Font.TextStyle = .body) -> Font {
        Font.custom("Menlo", size: size, relativeTo: style).weight(weight)
    }

    static let displayLarge = sans(42, .bold, like: .largeTitle)
    static let titleMedium = sans(21, .bold, like: .title3)
    static let bodyLarge = sans(16, .regular, like: .body)
    static let bodyMedium = sans(15, .regular, like: .callout)
    static let bodySmall = sans(12, .regular, like: .caption)
    static let labelLarge = sans(13, .bold, like: .footnote)
    static let labelSmall = sans(12, .medium, like: .caption)
    static let key = sans(17, .semibold, like: .body)
    static let smallKey = sans(13, .semibold, like: .footnote)
    static let actionKey = sans(15, .semibold, like: .subheadline)
    static let chip = sans(12, .medium, like: .caption)
    static let doorTitle = sans(15, .bold, like: .subheadline)
    static let rowTitle = sans(14, .bold, like: .subheadline)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }

    /// `Color.White.copy(alpha).compositeOver(this)`: the Android lift and shade of the key face.
    func lifted(_ amount: Double) -> Color { blended(with: .white, amount) }
    func shaded(_ amount: Double) -> Color { blended(with: .black, amount) }

    private func blended(with other: Color, _ amount: Double) -> Color {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(.sRGB, red: Double(r1) + Double(r2 - r1) * amount, green: Double(g1) + Double(g2 - g1) * amount, blue: Double(b1) + Double(b2 - b1) * amount, opacity: Double(a1))
    }
}
