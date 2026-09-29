//
//  ScannerView.swift
//  NutriVision
//

import SwiftUI
import AVFoundation
import PhotosUI

struct ScannerView: View {
    var onClose: () -> Void
    var onConfirm: (DetectedFood) -> Void

    @State private var viewModel = ScannerViewModel()
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            background

            if let detection = viewModel.detection {
                boundingBoxOverlay(detection: detection)
            }

            VStack {
                topBar
                Spacer()
                if let detection = viewModel.detection {
                    detectionSheet(detection: detection)
                } else if viewModel.inputMode == .liveCamera {
                    scanningHint
                }
            }
        }
        .statusBarHidden(true)
        .animation(.snappy(duration: 0.25), value: viewModel.detection)
        .task {
            if viewModel.inputMode == .liveCamera {
                await viewModel.start()
            }
        }
        .onDisappear { viewModel.stop() }
        .onChange(of: photosPickerItem) { _, newItem in
            Task {
                guard let newItem,
                      let data = try? await newItem.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                pickedImage = image
                await viewModel.classifyPickedImage(image)
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        switch viewModel.inputMode {
        case .liveCamera:
            CameraPreviewView(session: viewModel.session)
                .ignoresSafeArea()
            if let message = viewModel.cameraErrorMessage {
                permissionMessage(message)
            }
        case .photoPicker:
            if let pickedImage {
                Image(uiImage: pickedImage)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            } else {
                photoPickerPrompt
            }
        }
    }

    private var topBar: some View {
        HStack {
            circularButton(systemImage: "xmark", action: onClose)
            Spacer()
            circularButton(
                systemImage: viewModel.inputMode == .liveCamera ? "photo.on.rectangle" : "camera",
                action: toggleInputMode
            )
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
    }

    private func circularButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.4), in: Circle())
        }
        .accessibilityLabel(systemImage == "xmark" ? "Close" : "Switch input")
    }

    private func toggleInputMode() {
        pickedImage = nil
        photosPickerItem = nil
        viewModel.setInputMode(viewModel.inputMode == .liveCamera ? .photoPicker : .liveCamera)
    }

    private func boundingBoxOverlay(detection: DetectedFood) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text(detection.isBarcodeScan ? detection.displayName : "\(detection.displayName) — \(detection.confidencePercent)%")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 6)
                .background(.black.opacity(0.55), in: Capsule())

            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.brandPrimary, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .frame(width: 220, height: 220)
        }
    }

    private var barcodeStatusText: String? {
        if viewModel.isLookingUpBarcode { return "Looking up product…" }
        return viewModel.barcodeMessage
    }

    private var scanningHint: some View {
        Text(barcodeStatusText ?? "Point your camera at food or a barcode")
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(.black.opacity(0.4), in: Capsule())
            .padding(.bottom, Theme.Spacing.xl)
    }

    private func detectionSheet(detection: DetectedFood) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, Theme.Spacing.sm)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(detection.isBarcodeScan ? "PRODUCT" : "DETECTED")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.6))
                    .tracking(1.2)
                Text(detection.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                if let nutrition = detection.nutrition {
                    Text("\(Int(nutrition.calories.rounded())) kcal · \(nutrition.servingSize)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                } else {
                    Text("No nutrition match found — edit manually")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                }
                if detection.isLowConfidence {
                    Label("Low confidence — please verify", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !detection.alternatives.isEmpty && !detection.isBarcodeScan {
                alternativesRow(detection: detection)
            }

            HStack {
                Button("Retake") {
                    viewModel.retake()
                    pickedImage = nil
                    photosPickerItem = nil
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)

                Spacer()

                Button {
                    onConfirm(detection)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.brandPrimary, in: Circle())
                }
                .accessibilityLabel("Confirm \(detection.displayName)")
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.75), in: UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.sheet, topTrailingRadius: Theme.Radius.sheet))
    }

    /// The classifier's runners-up, one tap away.
    ///
    /// A general-purpose ImageNet model gets the top guess wrong often enough
    /// that a cheap correction path is worth more to the user than any amount
    /// of polish on the primary reading. Candidates we can actually price are
    /// outlined in the brand colour, so it's obvious which ones pre-fill
    /// macros and which still need manual entry.
    private func alternativesRow(detection: DetectedFood) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("NOT QUITE? TRY")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.6))
                .tracking(1.2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(detection.alternatives) { candidate in
                        Button {
                            viewModel.selectAlternative(candidate)
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Text(candidate.displayName)
                                    .fontWeight(.medium)
                                Text("\(candidate.confidencePercent)%")
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.15), in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(Color.brandPrimary, lineWidth: candidate.hasNutrition ? 1 : 0)
                            }
                        }
                        .accessibilityLabel("Change detection to \(candidate.displayName)")
                        .accessibilityHint("\(candidate.confidencePercent) percent confidence")
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var photoPickerPrompt: some View {
        PhotosPicker(selection: $photosPickerItem, matching: .images) {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 40))
                Text("Choose a Photo")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.white)
        }
    }

    private func permissionMessage(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(Theme.Spacing.lg)
    }
}

private struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {}

    final class PreviewContainerView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

#Preview {
    ScannerView(onClose: {}, onConfirm: { _ in })
}
