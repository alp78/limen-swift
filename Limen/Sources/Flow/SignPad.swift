import LimenKit
import SwiftUI
import UIKit

/// The ink pad, Signet's proven capture brought over: quadratic-midpoint smoothing, a tap that
/// registers as a dot (the crossing of a t never becomes a drag), a baseline guide, and an
/// alpha-bounding-box trim before the PNG leaves the pad. Always dark ink on white, whatever the
/// theme: the paper the signature is drawn on is white.
///
/// A full-screen cover, not a box in the page: signing is modal, nothing behind it can be
/// touched while it is up, and the header and the keys take what they need while the pad takes
/// what is left, which is what keeps it usable in landscape.
private struct InkStroke {
    var points: [CGPoint]
}

/// In PIXELS, as Android's INK_WIDTH is: Compose's Canvas and its bitmap both count pixels, so a 9
/// there is a pen line about 3.5 dp wide. Drawn in points here it was a marker three times as wide
/// on a 3x screen, and rendered onto a 1x bitmap it reached the paper at a third of the resolution.
/// The pad divides by the display scale on screen and renders the PNG at that scale, so both the
/// line and the bitmap are Android's.
private let inkWidthPixels: CGFloat = 9
private let inkColor = Color(hex: 0x15181D)

struct SignPadOverlay: View {
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    @Environment(\.displayScale) private var displayScale
    let title: String
    let meaning: String
    let onKeep: (Data) -> Void
    let onCancel: () -> Void
    @State private var strokes: [InkStroke] = []
    @State private var live: [CGPoint] = []
    @State private var padSize: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(LimenType.titleMedium).foregroundStyle(colors.ink)
            Spacer().frame(height: 8)
            // The one line that belongs above the ink, at reading size, never in small print.
            Text(meaning).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
            Spacer().frame(height: 14)
            GeometryReader { geometry in
                // The largest 2.1:1 rectangle that fits, by width in portrait and by height in landscape.
                let width = min(geometry.size.width, geometry.size.height * 2.1)
                let size = CGSize(width: width, height: width / 2.1)
                ZStack {
                    Canvas { context, canvasSize in
                        // The baseline the hand expects on paper.
                        var guide = Path()
                        guide.move(to: CGPoint(x: canvasSize.width * 0.07, y: canvasSize.height * 0.72))
                        guide.addLine(to: CGPoint(x: canvasSize.width * 0.93, y: canvasSize.height * 0.72))
                        context.stroke(guide, with: .color(Color(hex: 0xD9D9D9)), lineWidth: 2)
                        let ink = StrokeStyle(lineWidth: inkWidthPixels / displayScale, lineCap: .round, lineJoin: .round)
                        for stroke in strokes { context.stroke(inkPath(stroke.points), with: .color(inkColor), style: ink) }
                        if !live.isEmpty { context.stroke(inkPath(live), with: .color(inkColor), style: ink) }
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(colors.actionOutline, lineWidth: 1.5))
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                // A drag the system cancels (a call, a banner, the cover moving)
                                // never reaches onEnded, and SwiftUI has no onCancelled to clear
                                // `live` the way Android's onDragCancel does. A new drag has a new
                                // start point, so a start that is not the one `live` began with
                                // means the last stroke was cut short: it is dropped, as Android
                                // drops it, rather than joined to this one by a straight line.
                                if live.isEmpty || live.first != value.startLocation { live = [value.startLocation] }
                                live.append(value.location)
                            }
                            .onEnded { _ in
                                // Dots: a tap ends with one point, and initials have dots.
                                if !live.isEmpty { strokes.append(InkStroke(points: live)) }
                                live = []
                            }
                    )
                    .frame(width: size.width, height: size.height)
                    .onChange(of: size, initial: true) { _, now in padSize = now }
                    .accessibilityLabel(s.signaturePad)
                    .accessibilityValue(strokes.isEmpty && live.isEmpty ? s.signaturePadEmpty : s.signaturePadHasInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer().frame(height: 12)
            HStack(spacing: 8) {
                IconKey(glyph: .clear, label: s.clearInk, destructive: true, stretch: true) {
                    strokes = []
                    live = []
                }
                IconKey(glyph: .cancel, label: s.cancel, stretch: true, onPress: onCancel)
                // Keeping the ink is one of the two moments that end something, so it is felt
                // differently from the keys that only move you along.
                IconKey(glyph: .confirm, label: s.saveInk, enabled: !strokes.isEmpty && padSize.width > 0, fillColor: colors.action, outlineColor: colors.action, tint: colors.onInk, tick: .confirm, stretch: true) {
                    if let png = renderStrokes(strokes, size: padSize, scale: displayScale) { onKeep(png) }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.plate.ignoresSafeArea())
    }
}

private func inkPath(_ points: [CGPoint]) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)
    if points.count == 1 {
        // A dot: a stub so something renders.
        path.addLine(to: CGPoint(x: first.x + 0.1, y: first.y))
        return path
    }
    var prev = first
    for p in points.dropFirst() {
        let mid = CGPoint(x: (prev.x + p.x) / 2, y: (prev.y + p.y) / 2)
        path.addQuadCurve(to: mid, control: prev)
        prev = p
    }
    path.addLine(to: prev)
    return path
}

/// Replays the ink onto a transparent bitmap and trims it to what was actually written.
private func renderStrokes(_ strokes: [InkStroke], size: CGSize, scale: CGFloat) -> Data? {
    guard !strokes.isEmpty, size.width > 0, size.height > 0 else { return nil }
    let format = UIGraphicsImageRendererFormat()
    // The pad's own pixel grid, as Android's createBitmap(size.width, size.height) is.
    format.scale = scale
    format.opaque = false
    let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
        let cg = context.cgContext
        cg.setStrokeColor(UIColor(red: 0x15 / 255, green: 0x18 / 255, blue: 0x1D / 255, alpha: 1).cgColor)
        cg.setLineWidth(inkWidthPixels / scale)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        for stroke in strokes {
            cg.addPath(inkPath(stroke.points).cgPath)
            cg.strokePath()
        }
    }
    guard let cgImage = image.cgImage, let trimmed = trim(cgImage) else { return nil }
    return UIImage(cgImage: trimmed).pngData()
}

/// The alpha bounding box, with a little air, so the PNG is the signature and not the pad.
private func trim(_ image: CGImage) -> CGImage? {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height)
    // The context keeps the pointer and writes through it in draw(), so the array's storage has
    // to be pinned for both calls. `&pixels` handed to the initialiser alone is only promised to
    // hold for that one call; the draw that followed wrote into memory Swift no longer vouched for.
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drawn else { return nil }
    var minX = width, minY = height, maxX = -1, maxY = -1
    for y in 0..<height {
        for x in 0..<width where pixels[y * width + x] != 0 {
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
    }
    if maxX < 0 { return nil }
    let pad = 12
    let rect = CGRect(x: max(minX - pad, 0), y: max(minY - pad, 0), width: min(maxX + pad, width - 1) - max(minX - pad, 0) + 1, height: min(maxY + pad, height - 1) - max(minY - pad, 0) + 1)
    return image.cropping(to: rect)
}
