import CoreTransferable
import AVFoundation
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
    @State private var ownerId = ""
    @State private var ownerRevision: Int64 = -1
    @State private var intake: Task<Void, Never>?
    @State private var cameraRequest: Task<Void, Never>?
    @State private var cameraDenied = false

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            IconKey(glyph: .camera, label: s.photo, stretch: !compact, onPress: openCamera)
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
            CameraCapture { result in
                showCamera = false
                switch result {
                case .captured(let url):
                    if ownerId == model.working?.id, ownerRevision == model.working?.contentRevision, !model.contentLocked { onFile(url, .camera) } else { try? FileManager.default.removeItem(at: url) }
                case .failed(let error):
                    if ownerId == model.working?.id {
                        model.evidenceError = error == .tooLarge ? s.photoTooLarge : s.cameraProcessingFailed
                    }
                case .cancelled: break
                }
            }
            .ignoresSafeArea()
        }
        .alert(s.photo, isPresented: $cameraDenied) {
            Button(s.cancel, role: .cancel) {}
            Button(s.cameraSettings) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        } message: { Text(s.cameraPermissionDenied) }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            let owner = model.working?.id
            let revision = model.working?.contentRevision
            intake?.cancel()
            intake = Task {
                do {
                    guard let picked = try await item.loadTransferable(type: ImportedPhoto.self) else { return }
                    guard !Task.isCancelled, owner == model.working?.id, revision == model.working?.contentRevision, !model.contentLocked else {
                        try? FileManager.default.removeItem(at: picked.url)
                        return
                    }
                    onFile(picked.url, .gallery)
                } catch { model.evidenceError = error.localizedDescription }

            }
        }
        .onDisappear { intake?.cancel(); cameraRequest?.cancel() }
    }

    private func openCamera() {
        guard !model.contentLocked, let record = model.working else { return }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { model.evidenceError = s.cameraOpenFailed; return }
        ownerId = record.id
        ownerRevision = record.contentRevision
        cameraRequest?.cancel()
        cameraRequest = Task {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            if status == .restricted { model.evidenceError = s.cameraRestricted; return }
            let allowed: Bool
            if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) } else { allowed = status == .authorized }
            guard !Task.isCancelled, model.working?.id == record.id, model.working?.contentRevision == record.contentRevision, !model.contentLocked else { return }
            if allowed { showCamera = true } else { cameraDenied = true }
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

/// Each capture owns one slot and one encoding task. Dismantling cancels that operation only.
struct CameraCapture: UIViewControllerRepresentable {
    enum Failure: Error, Sendable { case unreadable, tooLarge, processing }
    enum Outcome { case captured(URL), cancelled, failed(Failure) }
    let onResult: (Outcome) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }
    static func dismantleUIViewController(_ uiViewController: UIImagePickerController, coordinator: Coordinator) {
        coordinator.cancel()
        uiViewController.delegate = nil
    }

    @MainActor final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onResult: (Outcome) -> Void
        private var encodingTask: Task<Void, Never>?
        private var operation: UUID?

        init(onResult: @escaping (Outcome) -> Void) { self.onResult = onResult }

        func cancel() {
            operation = nil
            encodingTask?.cancel()
            encodingTask = nil
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            cancel()
            guard let image = info[.originalImage] as? UIImage, let bitmap = image.cgImage else {
                onResult(.failed(.unreadable)); return
            }
            // Match PhotoDecode.bounds before encoding; the system supplies the source bitmap.
            guard bitmap.width > 0, bitmap.height > 0, bitmap.width <= 32_768, bitmap.height <= 32_768,
                  Int64(bitmap.width) * Int64(bitmap.height) <= 80_000_000 else {
                onResult(.failed(.tooLarge)); return
            }
            // Property-list bytes cross the actor boundary instead of an unsafe Any dictionary.
            // Preserve the camera's EXIF metadata and orientation beside its original bitmap.
            let metadata: Data
            do {
                metadata = try PropertyListSerialization.data(fromPropertyList: (info[.mediaMetadata] as? [String: Any]) ?? [:], format: .binary, options: 0)
            } catch { onResult(.failed(.processing)); return }
            let slot = AppFiles.captures.appendingPathComponent("cap-\(UUID().uuidString).jpg")
            let token = UUID()
            operation = token
            let worker = Task.detached(priority: .userInitiated) {
                try Self.encode(bitmap, metadata: metadata, to: slot)
            }
            encodingTask = Task {
                let result = await withTaskCancellationHandler {
                    await worker.result
                } onCancel: { worker.cancel() }
                guard !Task.isCancelled, operation == token else {
                    if case .success(let url) = result { try? FileManager.default.removeItem(at: url) }
                    return
                }
                operation = nil
                encodingTask = nil
                switch result {
                case .success(let url): onResult(.captured(url))
                case .failure(let error): onResult(.failed(error as? Failure ?? .processing))
                }
            }
        }

        nonisolated private static func encode(_ bitmap: CGImage, metadata: Data, to slot: URL) throws -> URL {
            var completed = false
            defer { if !completed { try? FileManager.default.removeItem(at: slot) } }
            try Task.checkCancellation()
            guard var properties = try PropertyListSerialization.propertyList(from: metadata, format: nil) as? [String: Any] else { throw Failure.processing }
            properties[kCGImageDestinationLossyCompressionQuality as String] = 0.92
            // Encode directly to our private file; never build an unbounded JPEG NSMutableData.
            guard let destination = CGImageDestinationCreateWithURL(slot as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw Failure.processing }
            CGImageDestinationAddImage(destination, bitmap, properties as CFDictionary)
            try Task.checkCancellation()
            guard CGImageDestinationFinalize(destination) else { throw Failure.processing }
            try Task.checkCancellation()
            let bytes = try slot.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes > 0 else { throw Failure.processing }
            guard Int64(bytes) <= EvidenceValidation.maxIntakeBytes else { throw Failure.tooLarge }
            try EvidenceValidation.validatePhoto(slot)
            try Task.checkCancellation()
            completed = true
            return slot
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            cancel()
            onResult(.cancelled)
        }
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
    var evidence: PhotoEvidence?
    var fileURL: URL?
    let onRemove: () -> Void
    @State private var image: CGImage?
    @State private var showing = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let file = fileURL ?? model.photoDir()?.appendingPathComponent(name)
        VStack(alignment: .trailing, spacing: 6) {
            Button { showing = true } label: {
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
            .accessibilityLabel("\(s.open) · \(name)")
            }
            .buttonStyle(.plain)
            // Deletion has its own target below the image, leaving every pixel available for opening.
            if !locked, image != nil {
                KeySurface(radius: 8, fillColor: colors.danger, outlineColor: colors.dangerOutline, tick: .reject, accessibilityLabel: s.delete, onPress: onRemove) {
                    Image(systemName: ButtonGlyph.delete.symbol).font(.system(size: 18)).foregroundStyle(colors.dangerOutline).frame(width: 44, height: 44)
                }
                .frame(width: 44, height: 44)
            }
        }
        .fullScreenCover(isPresented: $showing) {
            if let file { PhotoViewer(url: file, evidence: evidence) }
        }
        // Decoded off the main thread, through the same upright decoder the exported annex prints from.
        .task(id: file) {
            guard let file else { return }
            image = await Task.detached { PhotoDecode.sampled(file, targetWidth: 320) }.value
        }
    }
}

/// The original stays on disk; inspection uses a bounded upright decode and native zoom/pan.
struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.str) private var s
    @Environment(\.limen) private var colors
    let url: URL
    let evidence: PhotoEvidence?
    @State private var image: UIImage?
    @State private var zoom: CGFloat = 1

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(s.originalEvidence).font(LimenType.titleMedium).foregroundStyle(colors.ink).accessibilityAddTraits(.isHeader)
                Spacer()
                IconKey(glyph: .cancel, label: s.done) { dismiss() }
            }
            if let image { ZoomablePhoto(image: image, zoom: $zoom).accessibilityLabel(url.lastPathComponent) } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            HStack {
                IconKey(glyph: .remove, label: s.decrease, enabled: zoom > 1) { zoom = max(1, zoom / 2) }
                SmallKey(label: "\(Int(zoom * 100))%") { zoom = 1 }
                IconKey(glyph: .add, label: s.increase, enabled: zoom < 8) { zoom = min(8, zoom * 2) }
            }
            if let evidence {
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(evidence.source == .gallery ? s.gallery : evidence.source == .camera ? s.photo : s.toVerify)
                        if evidence.capturedEpochMs > 0 { Text("\(s.capturedOn): \(moment(evidence.capturedEpochMs))") }
                        if evidence.importedEpochMs > 0 { Text("\(s.importedOn): \(moment(evidence.importedEpochMs))") }
                        if !evidence.sha256.isBlank { Text("SHA-256: \(evidence.sha256)").textSelection(.enabled) }
                    }.font(LimenType.bodySmall).foregroundStyle(colors.ink)
                }.frame(maxHeight: 150)
            }
        }
        .padding(16)
        .background(colors.plate.ignoresSafeArea())
        .task(id: url) {
            let decoded = await Task.detached { PhotoDecode.sampled(url, targetWidth: 4096) }.value
            image = decoded.map { UIImage(cgImage: $0) }
        }
    }

    private func moment(_ ms: Int64) -> String {
        Date(timeIntervalSince1970: Double(ms) / 1000).formatted(date: .numeric, time: .shortened)
    }
}

private struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage
    @Binding var zoom: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(zoom: $zoom) }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = PhotoScrollView()
        scroll.imageView = context.coordinator.imageView
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 8
        scroll.delegate = context.coordinator
        scroll.addSubview(context.coordinator.imageView)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let view = context.coordinator.imageView
        view.image = image
        view.contentMode = .scaleAspectFit
        if scroll.zoomScale == 1 { view.frame = scroll.bounds; scroll.contentSize = scroll.bounds.size }
        if abs(scroll.zoomScale - zoom) > 0.01 { scroll.setZoomScale(zoom, animated: false) }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        let zoom: Binding<CGFloat>
        init(zoom: Binding<CGFloat>) { self.zoom = zoom }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) { zoom.wrappedValue = scale }
    }
}

private final class PhotoScrollView: UIScrollView {
    weak var imageView: UIImageView?
    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale == 1 { imageView?.frame = bounds; contentSize = bounds.size }
    }
}

private struct ImportedPhoto: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let attributes = try FileManager.default.attributesOfItem(atPath: received.file.path)
            guard let size = attributes[.size] as? NSNumber, size.int64Value > 0, size.int64Value <= 32 * 1024 * 1024 else {
                throw CocoaError(.fileReadTooLarge)
            }
            let suffix = received.file.pathExtension.isEmpty ? "image" : received.file.pathExtension
            let destination = AppFiles.captures.appendingPathComponent("pick-\(UUID().uuidString).\(suffix)")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return ImportedPhoto(url: destination)
        }
    }
}
