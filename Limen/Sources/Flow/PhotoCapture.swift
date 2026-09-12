import ImageIO
import LimenKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The two ways a photograph reaches a record, held together so a defect and a supplied object
/// take one the same way: the system camera, and the system picker.
///
/// The picker needs no permission and hands back the original bytes; the camera on iOS needs
/// the one permission this app asks for, and its picture is written as a JPEG into the cache
/// slot the record then moves it out of.
struct PhotoIntakeKeys: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.str) private var s
    var compact = false
    let onFile: (URL, PhotoSource) -> Void
    @State private var showCamera = false
    @State private var picked: PhotosPickerItem?

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            IconKey(glyph: .camera, label: s.photo, stretch: !compact) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showCamera = true
                } else {
                    model.show(s.cameraOpenFailed)
                }
            }
            PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                Image(systemName: ButtonGlyph.gallery.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 20, height: 20)
                    .frame(maxWidth: compact ? nil : .infinity)
                    .padding(14)
            }
            .buttonStyle(PickerKeyStyle())
            .accessibilityLabel(s.gallery)
            .frame(maxWidth: compact ? nil : .infinity)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { url in
                showCamera = false
                if let url { onFile(url, .camera) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            Task {
                // The original bytes, whatever they are: a HEIC stays a HEIC, as the Android
                // picker's stream was copied verbatim. A copy that fails part way is dropped.
                guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else { return }
                let slot = AppFiles.captures.appendingPathComponent("pick\(Int64(Date().timeIntervalSince1970 * 1000)).jpg")
                do {
                    try data.write(to: slot)
                    onFile(slot, .gallery)
                } catch {
                    try? FileManager.default.removeItem(at: slot)
                }
            }
        }
    }
}

/// The picker's label wears the same key face as the camera beside it.
private struct PickerKeyStyle: ButtonStyle {
    @Environment(\.limen) private var colors

    func makeBody(configuration: Configuration) -> some View {
        let fill = colors.input
        let depth: CGFloat = colors.isDark ? 2 : 3
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        configuration.label
            .foregroundStyle(colors.ink)
            .offset(y: configuration.isPressed ? depth : 0)
            .padding(.bottom, depth)
            .frame(minWidth: 48, minHeight: 48)
            .background {
                ZStack {
                    shape.fill(fill.shaded(0.16))
                    VStack(spacing: 0) {
                        shape.fill(LinearGradient(stops: [.init(color: fill.lifted(colors.isDark ? 0.18 : 0.30), location: 0), .init(color: fill, location: 0.36), .init(color: fill.shaded(colors.isDark ? 0.18 : 0.12), location: 1)], startPoint: .top, endPoint: .bottom))
                            .overlay(colors.isDark ? nil : shape.strokeBorder(colors.plateEdge, lineWidth: 1))
                        Color.clear.frame(height: depth)
                    }
                    .offset(y: configuration.isPressed ? depth : 0)
                }
            }
            .clipShape(shape)
        .animation(.easeOut(duration: 0.09), value: configuration.isPressed)
    }
}

/// The system camera. Old slots are swept rather than reused: a fixed name plus a camera crash
/// equals a stale photo silently attached to the wrong finding.
struct CameraCapture: UIViewControllerRepresentable {
    let onResult: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onResult: (URL?) -> Void

        init(onResult: @escaping (URL?) -> Void) { self.onResult = onResult }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let dir = AppFiles.captures
            for old in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                try? FileManager.default.removeItem(at: old)
            }
            // Written through ImageIO with the capture's own tags rather than re-encoded from the
            // UIImage: jpegData() emits a bare JPEG, and the EXIF the camera recorded, the moment of
            // capture above all, was lost from an evidence photograph. Android keeps it because the
            // camera app writes the EXTRA_OUTPUT file itself; here the picker hands the tags over
            // beside the pixels, and the orientation tag among them describes this very bitmap.
            guard let image = info[.originalImage] as? UIImage, let cgImage = image.cgImage else {
                onResult(nil)
                return
            }
            var properties = (info[.mediaMetadata] as? [String: Any]) ?? [:]
            properties[kCGImageDestinationLossyCompressionQuality as String] = 0.92
            let slot = dir.appendingPathComponent("cap\(Int64(Date().timeIntervalSince1970 * 1000)).jpg")
            // The dictionary and the bitmap are read here, on the main thread the delegate arrives
            // on, and nothing else touches either afterwards: the picker is done with them and this
            // is the only reference. The JPEG encode of a twelve-megapixel capture is tens of
            // milliseconds of the main thread otherwise, and it happens while the picker is
            // dismissing, which is exactly when the animation cannot afford it.
            nonisolated(unsafe) let bitmap = cgImage
            nonisolated(unsafe) let tags = properties
            // Only ever called back on the main actor, which is where it came from.
            nonisolated(unsafe) let report = onResult
            Task.detached {
                let encoded = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(encoded, UTType.jpeg.identifier as CFString, 1, nil) else {
                    await MainActor.run { report(nil) }
                    return
                }
                CGImageDestinationAddImage(destination, bitmap, tags as CFDictionary)
                // length, not existence: a camera that reports success without a picture, or a full
                // disk, would leave a zero-byte file that the evidence hash then refused outright.
                guard CGImageDestinationFinalize(destination), encoded.length > 0 else {
                    await MainActor.run { report(nil) }
                    return
                }
                do {
                    try (encoded as Data).write(to: slot)
                    await MainActor.run { report(slot) }
                } catch {
                    try? FileManager.default.removeItem(at: slot)
                    await MainActor.run { report(nil) }
                }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onResult(nil) }
    }
}

/// A small look at one photo, and the way to take it back off the record.
struct PhotoThumb: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let name: String
    var size: CGFloat = 84
    let onRemove: () -> Void
    @State private var image: CGImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let file = model.photoDir()?.appendingPathComponent(name)
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(image, scale: 1, orientation: .up, label: Text(name)).resizable().scaledToFill()
                } else {
                    // The same square, empty, so nothing jumps when the picture arrives.
                    Color.clear
                }
            }
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(colors.actionOutline, lineWidth: 1.5))
            .accessibilityLabel(name)
            // On a finalized record the photograph is evidence the fingerprint covers, so the
            // square is a picture and nothing else. 44 points: a destructive key a thumb can hit.
            if !locked, image != nil {
                KeySurface(radius: 8, fillColor: colors.danger, outlineColor: colors.dangerOutline, tick: .reject, accessibilityLabel: s.delete, onPress: onRemove) {
                    Image(systemName: ButtonGlyph.delete.symbol).font(.system(size: 18)).foregroundStyle(colors.dangerOutline).frame(width: 44, height: 44)
                }
                .frame(width: 44, height: 44)
                .padding(3)
            }
        }
        // Decoded off the main thread, through the same upright decoder the exported annex prints from.
        .task(id: file) {
            guard let file else { return }
            image = await Task.detached { PhotoDecode.sampled(file, targetWidth: 320) }.value
        }
    }
}
