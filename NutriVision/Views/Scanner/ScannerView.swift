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
        ZStack {
            Text("Scan Food")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            HStack {
                circularButton(systemImage: "xmark", action: onClose)
                Spacer()
                if viewModel.inputMode == .liveCamera, viewModel.hasTorch, viewModel.cameraAuthorized {
                    circularButton(systemImage: viewModel.torchOn ? "flashlight.on.fill" : "flashlight.off.fill") {
                        viewModel.toggleTorch()
                    }
                } else if viewModel.inputMode == .photoPicker {
                    circularButton(systemImage: "camera", action: toggleInputMode)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
    }

    private func circularButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.4), in: Circle())
        }
        .accessibilityLabel(accessibilityName(for: systemImage))
    }

    private func accessibilityName(for systemImage: String) -> String {
        switch systemImage {
        case "xmark": "Close"
        case "flashlight.on.fill": "Turn torch off"
        case "flashlight.off.fill": "Turn torch on"
        default: "Switch input"
        }
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

    /// Corner brackets around the food the detector has locked onto.
    private func regionOverlay(_ region: FoodRegion) -> some View {
        GeometryReader { proxy in
            let rect = region.viewRect(in: proxy.size, imageSize: viewModel.frameSize)
            CornerBrackets()
                .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .overlay(alignment: .topLeading) {
                    Text(region.kind == .beverage ? "Beverage" : "Food")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.brandPrimary, in: Capsule())
                        .offset(x: 8, y: -22)
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .animation(.smooth(duration: 0.2), value: rect)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var captureBar: some View {
        HStack(alignment: .center) {
            sideButton(systemImage: "photo.on.rectangle.angled", title: "Photos", action: toggleInputMode)
                .frame(maxWidth: .infinity)

            Button {
                Task { await viewModel.captureAndAnalyze() }
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 80)
                    .background(viewModel.region != nil ? Color.brandPrimary : Color.brandPrimary.opacity(0.75), in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 4).padding(-7))
            }
            .disabled(viewModel.isAnalyzing || !viewModel.hasCapturableFrame)
            .accessibilityLabel("Capture and analyze food")

            sideButton(systemImage: "text.viewfinder", title: "Label") {
                Task { await viewModel.scanLabel() }
            }
            .disabled(viewModel.isAnalyzing || !viewModel.hasCapturableFrame)
            .accessibilityLabel("Scan nutrition label")
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.lg)
    }

    private func sideButton(systemImage: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 60, height: 60)
                    .background(.black.opacity(0.45), in: Circle())
                Text(title).font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.white)
        }
    }

    private var barcodeStatusText: String? {
        if viewModel.isLookingUpBarcode { return "Looking up product…" }
        return viewModel.statusMessage ?? viewModel.barcodeMessage
    }

    private var scanningHint: some View {
        let locked = viewModel.region != nil && barcodeStatusText == nil
        return HStack(spacing: Theme.Spacing.sm) {
            if locked {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
            }
            Text(barcodeStatusText ?? (locked ? "Got it — tap the shutter" : "Point your camera at food or a barcode"))
        }
        .font(locked ? .headline : .footnote)
        .multilineTextAlignment(.center)
        .foregroundStyle(.white.opacity(locked ? 1 : 0.8))
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 14)
        .background(.black.opacity(0.5), in: Capsule())
        .padding(.bottom, Theme.Spacing.md)
        .animation(.snappy, value: locked)
    }

    private func detectionSheet(detection: DetectedFood) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 44, height: 5)
                .padding(.top, Theme.Spacing.sm)

            HStack(spacing: Theme.Spacing.md) {
                Text(FoodEmoji.emoji(for: detection.displayName))
                    .font(.system(size: 34))
                    .frame(width: 64, height: 64)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(detection.isBarcodeScan ? "PRODUCT" : detection.isLabelScan ? "LABEL" : detection.isCloudEstimate ? "AI ESTIMATE" : "WE THINK IT'S")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .tracking(1.5)
                    Text(detection.displayName)
                        .font(.title.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    if !detection.isExact {
                        Label("\(detection.confidencePercent)% match", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.brandPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.brandPrimary.opacity(0.2), in: Capsule())
                    }
                }
                Spacer(minLength: 0)
            }

            nutritionSummary(detection: detection)

            if detection.isLowConfidence {
                Label("Low confidence — please verify", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if detection.isCloudEstimate {
                Label(detection.fromCache ? "Estimated · from your previous scan" : "Estimated by AI — adjust if needed",
                      systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if detection.estimate?.hiddenIngredientsFlag == true {
                Label(detection.estimate?.hiddenIngredientsNote ?? "May contain hidden oil, butter or sugar",
                      systemImage: "drop.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if detection.nutrition != nil {
                portionControl(detection: detection)
            }

            if !detection.alternatives.isEmpty && !detection.isExact {
                alternativesRow(detection: detection)
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    viewModel.retake()
                    pickedImage = nil
                    photosPickerItem = nil
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(.white.opacity(0.15), in: Circle())
                }
                .accessibilityLabel("Retake")

                Button {
                    onConfirm(detection)
                } label: {
                    Label("Add to log", systemImage: "checkmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(LinearGradient.brand, in: Capsule())
                        .shadow(color: Color.brandPrimary.opacity(0.5), radius: 12, y: 4)
                }
                .accessibilityLabel("Add \(detection.displayName) to log")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.sheet, topTrailingRadius: Theme.Radius.sheet)
                .fill(.ultraThinMaterial)
                .overlay(UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.sheet, topTrailingRadius: Theme.Radius.sheet).fill(.black.opacity(0.35)))
                .ignoresSafeArea(edges: .bottom)
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func nutritionSummary(detection: DetectedFood) -> some View {
        if let nutrition = detection.scaledNutrition {
            HStack(spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Int(nutrition.calories.rounded()))")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("kcal · \(nutrition.servingSize)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                macroChip("P", grams: nutrition.proteinGrams, color: .macroProtein)
                macroChip("C", grams: nutrition.carbsGrams, color: .macroCarbs)
                macroChip("F", grams: nutrition.fatGrams, color: .macroFat)
            }
            .padding(Theme.Spacing.md)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            Text("No nutrition match found — edit manually")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func macroChip(_ letter: String, grams: Double, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(letter).font(.subheadline.weight(.bold)).foregroundStyle(color)
            Text("\(Int(grams.rounded()))g").font(.headline).foregroundStyle(.white).monospacedDigit()
        }
        .frame(width: 60, height: 64)
        .background(color.opacity(0.25), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Portion override. The model's size guess is a starting point, so the
    /// user can scale every macro up or down without leaving the scanner.
    private func portionControl(detection: DetectedFood) -> some View {
        let scale = Binding<Double>(
            get: { viewModel.detection?.portionScale ?? 1 },
            set: { viewModel.detection?.portionScale = $0 }
        )
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("PORTION")
                    .font(.caption.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                if let bucket = detection.estimate?.portion {
                    Text("AI guessed: \(bucket.label)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Text("×\(scale.wrappedValue.formatted(.number.precision(.fractionLength(0...2))))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.12), in: Capsule())
            }
            HStack(spacing: Theme.Spacing.sm) {
                ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { preset in
                    let selected = abs(scale.wrappedValue - preset) < 0.001
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { scale.wrappedValue = preset }
                    } label: {
                        Text("\(preset.formatted(.number.precision(.fractionLength(0...1))))×")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(selected ? Color.brandPrimary : .white.opacity(0.12), in: Capsule())
                    }
                    .accessibilityLabel("\(preset.formatted()) times portion")
                }
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
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.6))
                .tracking(1.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(detection.alternatives) { candidate in
                        Button {
                            viewModel.selectAlternative(candidate)
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Text(FoodEmoji.emoji(for: candidate.displayName))
                                Text(candidate.displayName)
                                    .fontWeight(.medium)
                                Text("\(candidate.confidencePercent)%")
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.1), in: Capsule())
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
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
            Text("Camera access needed")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.8))
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brandPrimary)
            Button("Choose a photo instead") { toggleInputMode() }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
        }
        .foregroundStyle(.white)
        .padding(Theme.Spacing.lg)
        .accessibilityElement(children: .contain)
    }
}

/// Four L-shaped corners tracing a rectangle.
private struct CornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let arm = min(rect.width, rect.height) * 0.22
        var p = Path()
        for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0), (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                 (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0), (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
            p.move(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
            p.addLine(to: corner)
            p.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        }
        return p
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
