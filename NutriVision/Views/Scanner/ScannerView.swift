//
//  ScannerView.swift
//  NutriVision
//

import SwiftUI
import AVFoundation
import PhotosUI
import SwiftData

struct ScannerView: View {
    var onClose: () -> Void
    var onConfirm: (DetectedFood) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ScannerViewModel()
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            background

            if viewModel.detection == nil, viewModel.inputMode == .liveCamera, let region = viewModel.region {
                regionOverlay(region)
            } else if let detection = viewModel.detection {
                boundingBoxOverlay(detection: detection)
            }

            VStack {
                topBar
                Spacer()
                if let detection = viewModel.detection {
                    detectionSheet(detection: detection)
                } else if viewModel.inputMode == .liveCamera {
                    scanningHint
                    captureBar
                }
            }

            if viewModel.isAnalyzing {
                ProgressView("Analyzing…")
                    .padding(Theme.Spacing.lg)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.lockCount)
        .sensoryFeedback(.success, trigger: viewModel.detection?.id)
        .statusBarHidden(true)
        .animation(.snappy(duration: 0.25), value: viewModel.detection)
        .task {
            viewModel.attach(modelContext: modelContext)
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
            Text(detection.isExact ? detection.displayName : "\(detection.displayName) — \(detection.confidencePercent)%")
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

    /// Crisp box around the food the detector has locked onto.
    private func regionOverlay(_ region: FoodRegion) -> some View {
        GeometryReader { proxy in
            let rect = region.viewRect(in: proxy.size, imageSize: viewModel.frameSize)
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.brandPrimary, lineWidth: 3)
                .overlay(alignment: .topLeading) {
                    Text(region.kind == .beverage ? "Beverage" : "Food")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.brandPrimary, in: Capsule())
                        .offset(x: 8, y: -12)
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .animation(.smooth(duration: 0.2), value: rect)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var captureBar: some View {
        HStack(spacing: Theme.Spacing.xl) {
            Button {
                Task { await viewModel.scanLabel() }
            } label: {
                Label("Label", systemImage: "text.viewfinder")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(.black.opacity(0.45), in: Capsule())
            }
            .accessibilityLabel("Scan nutrition label")

            Button {
                Task { await viewModel.captureAndAnalyze() }
            } label: {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .background(Circle().fill(viewModel.region != nil ? Color.brandPrimary : .white.opacity(0.85)).padding(6))
                    .frame(width: 72, height: 72)
            }
            .accessibilityLabel("Capture and analyze food")
        }
        .disabled(viewModel.isAnalyzing || !viewModel.hasCapturableFrame)
        .padding(.bottom, Theme.Spacing.lg)
    }

    private var barcodeStatusText: String? {
        if viewModel.isLookingUpBarcode { return "Looking up product…" }
        return viewModel.statusMessage ?? viewModel.barcodeMessage
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
                Text(detection.isBarcodeScan ? "PRODUCT" : detection.isLabelScan ? "LABEL" : detection.isCloudEstimate ? "AI ESTIMATE" : "DETECTED")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.6))
                    .tracking(1.2)
                Text(detection.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                if let nutrition = detection.scaledNutrition {
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
                if detection.isCloudEstimate {
                    Label(detection.fromCache ? "Estimated · from your previous scan" : "Estimated by AI — adjust if needed",
                          systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                if detection.estimate?.hiddenIngredientsFlag == true {
                    Label(detection.estimate?.hiddenIngredientsNote ?? "May contain hidden oil, butter or sugar",
                          systemImage: "drop.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if detection.nutrition != nil {
                portionControl(detection: detection)
            }

            if !detection.alternatives.isEmpty && !detection.isExact {
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

    /// Portion override. The model's size guess is a starting point, so the
    /// user can scale every macro up or down without leaving the scanner.
    private func portionControl(detection: DetectedFood) -> some View {
        let scale = Binding<Double>(
            get: { viewModel.detection?.portionScale ?? 1 },
            set: { viewModel.detection?.portionScale = $0 }
        )
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("PORTION")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                if let bucket = detection.estimate?.portion {
                    Text("AI guessed: \(bucket.label)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Text("×\(scale.wrappedValue.formatted(.number.precision(.fractionLength(0...2))))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            Slider(value: scale, in: 0.25...3, step: 0.05)
                .tint(Color.brandPrimary)
                .accessibilityLabel("Portion size multiplier")
        }
        .sensoryFeedback(.selection, trigger: Int((scale.wrappedValue * 4).rounded()))
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
