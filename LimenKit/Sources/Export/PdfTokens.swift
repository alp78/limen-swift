import Foundation

/// The printed record's design tokens, every one derived from the app's own: the Day palette,
/// the theme's type sizes, its radii and paddings. The document is drawn on a 1240 by 1754 unit
/// grid, A4 at 150 dpi, which the Pixel draws on as well, so these numbers are the contract
/// between the two ports.
///
/// Plain values: no font and no colour type, so the scale and the palette are tested without a
/// graphics context.
public enum PdfTokens {
    public static let width: CGFloat = 1240
    public static let height: CGFloat = 1754
    public static let margin: CGFloat = 90
    public static let foot: CGFloat = 60
    /// Where the body starts under the running header.
    public static let headerBottom: CGFloat = 130
    /// Where the body ends above the footer.
    public static let bottom: CGFloat = height - foot - 30

    /// Units per point. A point is 1/160 inch on the Android side (a dp) and a unit 1/150, so a
    /// one-to-one print would set the 15-point body at 6.75 pt; 1.6 sets it at 24 units, 11.5 pt,
    /// the size paper forms use, and carries every radius and padding up by the same factor.
    public static let unitsPerPoint: CGFloat = 1.6
    public static func dp(_ value: CGFloat) -> CGFloat { value * unitsPerPoint }

    // Type, from the theme's sizes.
    public static let display = dp(42)
    public static let title = dp(21)
    public static let bodyLarge = dp(16)
    public static let body = dp(15)
    public static let labelLarge = dp(13)
    public static let labelSmall = dp(12)
    public static let bodyLine = dp(21)
    public static let bodyLargeLine = dp(23)
    /// The line of a style the theme gives no line height.
    public static let line: CGFloat = 1.35
    // Tracking as an em fraction, the theme's letter spacing over the size; the kern takes it in
    // points, the fraction times the font size.
    public static let displayTrack: CGFloat = -0.5 / 42
    public static let labelLargeTrack: CGFloat = 0.3 / 13
    public static let labelSmallTrack: CGFloat = 0.2 / 12
    public static let chipTrack: CGFloat = 0.3 / 12

    // Shapes, from the theme's shapes and the radii the screens repeat.
    public static let panelRadius = dp(12)
    public static let bannerRadius = dp(14)
    public static let chipRadius = dp(10)
    public static let thumbRadius = dp(8)
    public static let pillRadius = dp(6)
    public static let badgeRadius: CGFloat = 8
    public static let border = dp(1.5)
    public static let panelPad = dp(16)
    public static let panelGap = dp(10)
    public static let labelGap = dp(8)
    public static let chipGap = dp(6)
    /// A card's padding in the annex: it leaves `AnnexPlate.maxWidth` for the photograph.
    public static let framePad: CGFloat = 20
    public static let pillHeight: CGFloat = 34
    public static let chipHeight: CGFloat = 34
    public static let badgeHeight: CGFloat = 32
    /// Room for a heading and the first rows under it, so a heading never ends a page.
    public static let headingNeed: CGFloat = 260

    // Colours, RGB.
    public static let paper: UInt32 = 0xFFFFFF
    public static let panel = LimenPalette.plateRaised
    public static let input = LimenPalette.input
    public static let edge = LimenPalette.plateEdge
    public static let navy = LimenPalette.navy
    public static let ink = LimenPalette.ink
    public static let inkDim = LimenPalette.inkDim
    public static let warning = LimenPalette.warning
    public static let warningOutline = LimenPalette.warningOutline
    public static let danger = LimenPalette.danger
    public static let dangerOutline = LimenPalette.dangerOutline
    public static let positive = LimenPalette.positive
    /// Lettering on the navy banner at the landing's 88 percent white, flattened in advance: an
    /// alpha on a colour would make the PDF context emit a transparency state for it.
    public static let onNavyDim: UInt32 = 0xE5E7EA

    /// The one family the record is set in, as the app is: the system face, San Francisco on the
    /// iPhone, which `UIFont.systemFont` names this way. Never a monospace: the screens use one
    /// for a readout or two, the paper for nothing.
    public static let family = ".AppleSystemUIFont"
}
