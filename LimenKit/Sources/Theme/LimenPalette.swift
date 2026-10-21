import Foundation

/// The Day palette as plain RGB values. The SwiftUI theme reads them for the screen and the
/// printed record reads them for the paper, so the two cannot drift: a navy changed here changes
/// both. Plain integers on purpose, because the document's tokens are tested without a graphics
/// context and the kit imports nothing from SwiftUI. The values are Android's `LimenPalette`,
/// which its Compose theme reads the same way.
public enum LimenPalette {
    public static let plate: UInt32 = 0xF6F7F9
    public static let plateRaised: UInt32 = 0xE7E9EE
    public static let input: UInt32 = 0xEFF1F4
    public static let plateEdge: UInt32 = 0xD7DAE0
    /// The mark's navy: action, outline, landing and seal are one colour by day.
    public static let navy: UInt32 = 0x233350
    public static let ink: UInt32 = 0x1A1D23
    public static let inkDim: UInt32 = 0x5B6472
    public static let warning: UInt32 = 0xFCEBD2
    public static let warningOutline: UInt32 = 0x835000
    public static let positive: UInt32 = 0x287A42
    public static let danger: UInt32 = 0xFDE8E8
    public static let dangerOutline: UInt32 = 0xC94242
    public static let disabledInk: UInt32 = 0xA7ADB8
}
