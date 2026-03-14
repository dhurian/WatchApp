//
//  WatchPhotoReader.swift
//  WatchApp
//

import SwiftUI
import AVFoundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - WatchPhotoReaderView

struct WatchPhotoReaderView: View {
    @EnvironmentObject var manager: TimeEntryManager
    @Binding var selectedWatch: Watch?
    @Environment(\.dismiss) private var dismiss

    @State private var phase: ReaderPhase = .capture
    @State private var capturedImage: UIImage? = nil
    @State private var capturedAt: Date? = nil
    @State private var isProcessing = false
    @State private var watchHour: Int = 0
    @State private var watchMinute: Int = 0
    @State private var watchSecond: Int = 0
    @State private var ocrAttempted = false
    @State private var ocrSucceeded = false
    @State private var debugLog: [String] = []
    @State private var showingFullscreenPhoto = false

    enum ReaderPhase { case capture, entry, confirm }

    var body: some View {
        NavigationStack {
            switch phase {
            case .capture: cameraPhase
            case .entry:   entryPhase
            case .confirm: confirmPhase
            }
        }
    }

    // MARK: - Camera Phase

    private var cameraPhase: some View {
        ZStack {
            CameraReaderView { image, timestamp in
                capturedImage = image
                capturedAt = timestamp
                watchHour   = Calendar.current.component(.hour,   from: timestamp)
                watchMinute = Calendar.current.component(.minute, from: timestamp)
                watchSecond = Calendar.current.component(.second, from: timestamp)
                phase = .entry
                tryOCR(on: image)
            }
            VStack {
                Spacer()
                VStack(spacing: 6) {
                    Text("Frame the watch face")
                        .font(.subheadline).fontWeight(.semibold)
                    Text("Good lighting and focus improve detection")
                        .font(.caption).opacity(0.85)
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(.black.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 140)
            }
        }
        .ignoresSafeArea()
        .navigationTitle("Read Watch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.foregroundStyle(.white)
            }
        }
    }

    // MARK: - Entry Phase

    private var entryPhase: some View {
        VStack(spacing: 0) {
            // Tappable photo with OCR status badge
            if let img = capturedImage {
                Button { showingFullscreenPhoto = true } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        if isProcessing {
                            ProgressView()
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .padding(12)
                        } else if ocrSucceeded {
                            Label("Time read — tap to verify", systemImage: "checkmark.circle.fill")
                                .font(.caption2).fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.green.opacity(0.85))
                                .clipShape(Capsule())
                                .padding(12)
                        } else if ocrAttempted {
                            Label("Tap to zoom and read manually", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.caption2).fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.orange.opacity(0.85))
                                .clipShape(Capsule())
                                .padding(12)
                        } else {
                            Label("Tap to enlarge", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.caption2).fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.black.opacity(0.5))
                                .clipShape(Capsule())
                                .padding(12)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal).padding(.top, 12)
                .fullScreenCover(isPresented: $showingFullscreenPhoto) {
                    ZoomablePhotoView(image: img)
                }
            }

            // Phone time reference
            if let t = capturedAt {
                HStack {
                    Image(systemName: "iphone").foregroundStyle(.secondary)
                    Text("Phone time:").foregroundStyle(.secondary)
                    Text(t, format: .dateTime.hour().minute().second())
                        .monospacedDigit().fontWeight(.semibold)
                    Spacer()
                }
                .font(.subheadline)
                .padding(.horizontal).padding(.top, 10)
            }

            Divider().padding(.vertical, 8)

            Text("Set Watch Time").font(.headline)
            Text("Tap photo to zoom in and verify the hands")
                .font(.caption).foregroundStyle(.secondary).padding(.bottom, 4)

            HStack(spacing: 0) {
                Picker("Hour", selection: $watchHour) {
                    ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)) }
                }
                .pickerStyle(.wheel).frame(maxWidth: .infinity)
                Text(":").font(.title).foregroundStyle(.secondary)
                Picker("Minute", selection: $watchMinute) {
                    ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)) }
                }
                .pickerStyle(.wheel).frame(maxWidth: .infinity)
                Text(":").font(.title).foregroundStyle(.secondary)
                Picker("Second", selection: $watchSecond) {
                    ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)) }
                }
                .pickerStyle(.wheel).frame(maxWidth: .infinity)
            }
            .frame(height: 150)

            Spacer()

            HStack(spacing: 16) {
                Button {
                    capturedImage = nil; capturedAt = nil
                    ocrAttempted = false; ocrSucceeded = false
                    debugLog = []
                    phase = .capture
                } label: {
                    Label("Retake", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.orange)

                Button { phase = .confirm } label: {
                    Label("Continue", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24).padding(.bottom, 32)
        }
        .navigationTitle("Set Watch Time")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    // MARK: - Confirm Phase

    private var confirmPhase: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64)).foregroundStyle(.green)
                .padding(.top, 40)

            Text("Ready to Save").font(.title2).fontWeight(.semibold)

            if let recorded = capturedAt {
                let watchTime = WatchTime(hour: watchHour, minute: watchMinute,
                                         second: watchSecond, secondsConfident: true)
                VStack(spacing: 0) {
                    summaryRow(label: "Phone time",
                               value: recorded.formatted(.dateTime.hour().minute().second()),
                               color: .primary)
                    Divider().padding(.horizontal)
                    summaryRow(label: "Watch time", value: watchTime.displayString, color: .green)
                    Divider().padding(.horizontal)
                    let delta = watchTimeDelta(recorded: recorded, watchTime: watchTime)
                    summaryRow(label: "Difference", value: formattedDelta(delta),
                               color: abs(delta) < 1 ? .green : .orange)
                }
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }

            Spacer()

            VStack(spacing: 12) {
                Button { saveEntry() } label: {
                    Label("Save Entry", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent).tint(.blue).padding(.horizontal)

                Button { phase = .entry } label: {
                    Text("Go Back").foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 32)
        }
        .navigationTitle("Confirm")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func summaryRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().fontWeight(.semibold).foregroundStyle(color)
        }
        .padding(.horizontal).padding(.vertical, 12)
    }

    // MARK: - OCR Pipeline

    private func tryOCR(on image: UIImage) {
        isProcessing = true
        ocrAttempted = false
        ocrSucceeded = false
        debugLog = []

        guard let cgImage = image.cgImage else {
            isProcessing = false; ocrAttempted = true
            debugLog = ["X No CGImage"]
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var log: [String] = ["--- OCR Pipeline ---"]

            let croppedCG = self.cropToSalientRegion(cgImage) ?? cgImage
            log.append("Crop: \(croppedCG.width)x\(croppedCG.height)")

            let uiCropped = UIImage(cgImage: croppedCG)
            let preprocessed = self.preprocessForOCR(uiCropped) ?? uiCropped
            guard let finalCG = preprocessed.cgImage else {
                DispatchQueue.main.async {
                    self.isProcessing = false; self.ocrAttempted = true
                    self.debugLog = ["X Preprocess failed"]
                }
                return
            }

            let request = VNRecognizeTextRequest { req, _ in
                let candidates = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(3).first?.string }
                log.append("OCR: \(candidates.joined(separator: " | "))")

                DispatchQueue.main.async {
                    self.ocrAttempted = true
                    if let time = self.parseWatchTime(from: candidates) {
                        log.append("OK OCR: \(time.displayString)")
                        self.isProcessing = false
                        self.watchHour   = time.hour
                        self.watchMinute = time.minute
                        self.watchSecond = time.second
                        self.ocrSucceeded = true
                        self.debugLog = log
                    } else {
                        log.append("No time from OCR, trying hand detection")
                        self.debugLog = log
                        self.tryHandDetection(on: UIImage(cgImage: finalCG), log: log)
                    }
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.minimumTextHeight = 0.015
            try? VNImageRequestHandler(cgImage: finalCG, options: [:]).perform([request])
        }
    }

    private func cropToSalientRegion(_ cgImage: CGImage) -> CGImage? {
        let saliencyRequest = VNGenerateObjectnessBasedSaliencyImageRequest()
        try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([saliencyRequest])
        let w = CGFloat(cgImage.width); let h = CGFloat(cgImage.height)
        let cropRect: CGRect
        if let result = saliencyRequest.results?.first as? VNSaliencyImageObservation,
           let obj = result.salientObjects?.first {
            let box = obj.boundingBox; let pad: CGFloat = 0.10
            let ex = CGRect(x: max(0, box.minX - pad), y: max(0, box.minY - pad),
                            width: min(1, box.width + pad * 2), height: min(1, box.height + pad * 2))
            cropRect = CGRect(x: ex.minX * w, y: (1 - ex.maxY) * h,
                              width: ex.width * w, height: ex.height * h)
        } else {
            let m: CGFloat = 0.125
            cropRect = CGRect(x: w * m, y: h * m, width: w * (1 - m * 2), height: h * (1 - m * 2))
        }
        return cgImage.cropping(to: cropRect)
    }

    private func preprocessForOCR(_ image: UIImage) -> UIImage? {
        guard let ci = CIImage(image: image) else { return nil }
        let ctx = CIContext()
        let cc = CIFilter.colorControls()
        cc.inputImage = ci; cc.saturation = 0; cc.contrast = 1.5; cc.brightness = 0.05
        let sharp = CIFilter.unsharpMask()
        sharp.inputImage = cc.outputImage ?? ci; sharp.radius = 2.0; sharp.intensity = 1.0
        guard let out = sharp.outputImage,
              let cg = ctx.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func parseWatchTime(from strings: [String]) -> WatchTime? {
        let joined = strings.joined(separator: " ")
        let patterns: [(String, Bool)] = [
            (#"(\d{1,2}):(\d{2}):(\d{2})"#, true),
            (#"(\d{1,2})\.(\d{2})\.(\d{2})"#, true),
            (#"(\d{1,2}):(\d{2})"#, false),
            (#"(\d{1,2})\.(\d{2})"#, false),
        ]
        for (pattern, hasSeconds) in patterns {
            if let t = matchTime(in: joined, pattern: pattern, hasSeconds: hasSeconds) { return t }
        }
        return nil
    }

    private func matchTime(in text: String, pattern: String, hasSeconds: Bool) -> WatchTime? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ i: Int) -> Int? {
            guard let r = Range(match.range(at: i), in: text) else { return nil }
            return Int(text[r])
        }
        guard let h = group(1), let m = group(2), h < 24, m < 60 else { return nil }
        let s = hasSeconds ? (group(3) ?? 0) : 0
        guard s < 60 else { return nil }
        return WatchTime(hour: h, minute: m, second: s, secondsConfident: hasSeconds)
    }

    // MARK: - Hand Detection Pipeline

    private func tryHandDetection(on image: UIImage, log: [String]) {
        var log = log
        log.append("--- Hand Detection ---")

        guard let cgImage = image.cgImage else {
            DispatchQueue.main.async {
                self.isProcessing = false
                log.append("X No CGImage for hand detection")
                self.debugLog = log
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let w = CGFloat(cgImage.width); let h = CGFloat(cgImage.height)
            let center = CGPoint(x: w / 2, y: h / 2)
            log.append("Size: \(Int(w))x\(Int(h))")

            // High-contrast greyscale to make hands stand out
            let ciImage = CIImage(cgImage: cgImage)
            let ctx = CIContext()
            let cc = CIFilter.colorControls()
            cc.inputImage = ciImage; cc.saturation = 0; cc.contrast = 3.0; cc.brightness = -0.15
            guard let processedCI = cc.outputImage,
                  let processedCG = ctx.createCGImage(processedCI, from: processedCI.extent) else {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    log.append("X Preprocess failed")
                    self.debugLog = log
                }
                return
            }

            // Contour detection — finds outlines of all shapes including hands
            let contourRequest = VNDetectContoursRequest()
            contourRequest.contrastAdjustment = 3.0
            do {
                try VNImageRequestHandler(cgImage: processedCG, options: [:]).perform([contourRequest])
            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    log.append("X Contour error: \(error.localizedDescription)")
                    self.debugLog = log
                }
                return
            }

            guard let obs = contourRequest.results?.first as? VNContoursObservation else {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    log.append("X No contours found")
                    self.debugLog = log
                }
                return
            }
            log.append("Contours: \(obs.contourCount)")

            // Filter for hand-like shapes: elongated, passes near center
            var handCandidates: [(angle: Double, length: Double)] = []

            for i in 0..<obs.contourCount {
                guard let contour = try? obs.contour(at: i) else { continue }
                // normalizedPoints returns [simd_float2]; Vision Y is flipped
                let pts: [CGPoint] = contour.normalizedPoints.map {
                    CGPoint(x: CGFloat($0.x) * w, y: (1 - CGFloat($0.y)) * h)
                }
                guard pts.count >= 4 else { continue }

                let xs = pts.map(\.x); let ys = pts.map(\.y)
                let minX = xs.min()!; let maxX = xs.max()!
                let minY = ys.min()!; let maxY = ys.max()!
                let bboxW = maxX - minX; let bboxH = maxY - minY
                let length = max(bboxW, bboxH)
                let thickness = min(bboxW, bboxH) + 1

                // Must be elongated and long enough to be a hand
                guard length > w * 0.08 else { continue }
                guard thickness / length < 0.35 else { continue }

                // Bounding box center must be near image center
                let bboxCX = (minX + maxX) / 2
                let bboxCY = (minY + maxY) / 2
                let dist = hypot(bboxCX - center.x, bboxCY - center.y)
                guard dist < w * 0.25 else { continue }

                // Tip = point furthest from center
                let tip = pts.max(by: {
                    hypot($0.x - center.x, $0.y - center.y) <
                    hypot($1.x - center.x, $1.y - center.y)
                })!
                let dx = Double(tip.x - center.x)
                let dy = Double(tip.y - center.y)
                var angle = atan2(dx, -dy) // clockwise from 12 o'clock
                if angle < 0 { angle += .pi * 2 }
                handCandidates.append((angle: angle, length: length))
            }

            log.append("Candidates: \(handCandidates.count)")
            for c in handCandidates {
                log.append("  \(String(format: "%.1f", c.angle * 180 / .pi))deg len:\(Int(c.length))")
            }

            guard handCandidates.count >= 2 else {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    log.append("X Need 2+ hands, found \(handCandidates.count)")
                    self.debugLog = log
                }
                return
            }

            // Sort longest to shortest: second > minute > hour
            let sorted = handCandidates.sorted { $0.length > $1.length }
            let angles = sorted.map(\.angle)

            guard let time = self.timeFromAngles(Array(angles.prefix(3))) else {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    log.append("X Angle conversion failed")
                    self.debugLog = log
                }
                return
            }

            log.append("OK Time: \(time.displayString)")
            DispatchQueue.main.async {
                self.isProcessing = false
                self.watchHour   = time.hour
                self.watchMinute = time.minute
                self.watchSecond = time.second
                self.ocrSucceeded = true
                self.debugLog = log
            }
        }
    }

    private func timeFromAngles(_ angles: [Double]) -> WatchTime? {
        guard angles.count >= 2 else { return nil }
        let twoPi = Double.pi * 2
        // Sorted longest to shortest: [0]=second, [1]=minute, [2]=hour
        // If only 2: [0]=minute, [1]=hour
        let minuteAngle = angles.count >= 3 ? angles[1] : angles[0]
        let hourAngle   = angles.count >= 3 ? angles[2] : angles[1]
        let minute = Int((minuteAngle / twoPi) * 60) % 60
        let hourFraction = (hourAngle / twoPi) * 12
        var hour = Int(hourFraction) % 12
        if minute >= 30 && hourFraction.truncatingRemainder(dividingBy: 1) < 0.5 {
            hour = (hour + 1) % 12
        }
        var second = 0; var confident = false
        if angles.count >= 3 {
            second = Int((angles[0] / twoPi) * 60) % 60
            confident = true
        }
        guard hour >= 0, hour < 12, minute >= 0, minute < 60 else { return nil }
        return WatchTime(hour: hour, minute: minute, second: second, secondsConfident: confident)
    }

    // MARK: - Helpers

    private func watchTimeDelta(recorded: Date, watchTime: WatchTime) -> Double {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: recorded)
        comps.hour = watchTime.hour; comps.minute = watchTime.minute; comps.second = watchTime.second
        guard let wDate = Calendar.current.date(from: comps) else { return 0 }
        return wDate.timeIntervalSince(recorded)
    }

    private func formattedDelta(_ delta: Double) -> String {
        if abs(delta) < 1 { return "  0 s (in sync)" }
        let sign = delta >= 0 ? "+" : "-"
        return "\(sign)\(String(format: "%.0f", abs(delta))) s"
    }

    private func saveEntry() {
        guard let recorded = capturedAt, let watch = selectedWatch else { return }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: recorded)
        comps.hour = watchHour; comps.minute = watchMinute; comps.second = watchSecond
        if let watchDate = Calendar.current.date(from: comps) {
            manager.add(TimeEntry(recorded: recorded, custom: watchDate, watchID: watch.id))
        }
        dismiss()
    }
}

// MARK: - WatchTime

struct WatchTime {
    let hour: Int
    let minute: Int
    let second: Int
    let secondsConfident: Bool
    var displayString: String { String(format: "%02d:%02d:%02d", hour, minute, second) }
}

// MARK: - ZoomablePhotoView

struct ZoomablePhotoView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            ZoomableScrollView {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white, .black.opacity(0.5))
                    .padding(20)
            }
        }
    }
}

struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 8.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .black
        scrollView.delegate = context.coordinator

        let hosted = UIHostingController(rootView: content)
        hosted.view.backgroundColor = .clear
        scrollView.addSubview(hosted.view)
        hosted.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosted.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hosted.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hosted.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hosted.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hosted.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            hosted.view.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
        context.coordinator.hostedView = hosted.view

        // Double-tap to zoom in/out
        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, UIScrollViewDelegate {
        weak var hostedView: UIView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { hostedView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // Keep content centered when smaller than scroll view
            guard let view = hostedView else { return }
            let offsetX = max((scrollView.bounds.width  - view.frame.width)  / 2, 0)
            let offsetY = max((scrollView.bounds.height - view.frame.height) / 2, 0)
            scrollView.contentInset = UIEdgeInsets(top: offsetY, left: offsetX, bottom: offsetY, right: offsetX)
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            if scrollView.zoomScale > 1.0 {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                let point = recognizer.location(in: hostedView)
                let zoomRect = CGRect(x: point.x - 50, y: point.y - 50, width: 100, height: 100)
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }
    }
}

// MARK: - CameraReaderView

struct CameraReaderView: UIViewControllerRepresentable {
    let onCapture: (UIImage, Date) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> CameraReaderViewController {
        let vc = CameraReaderViewController()
        vc.onCapture = onCapture
        return vc
    }
    func updateUIViewController(_ vc: CameraReaderViewController, context: Context) {}
    class Coordinator: NSObject {}
}

// MARK: - CameraReaderViewController

class CameraReaderViewController: UIViewController {
    var onCapture: ((UIImage, Date) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "watchreader.session")
    private var photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var captureTimestamp = Date()
    private var flashMode: AVCaptureDevice.FlashMode = .auto
    private let shutterButton = UIButton()
    private let flashButton = UIButton()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupUI()
        setupSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.sync { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.inputs.forEach  { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }
            self.session.commitConfiguration()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            let types: [AVCaptureDevice.DeviceType] = [
                .builtInTripleCamera, .builtInDualWideCamera,
                .builtInDualCamera, .builtInWideAngleCamera
            ]
            guard let device = AVCaptureDevice.DiscoverySession(
                    deviceTypes: types, mediaType: .video, position: .back
                  ).devices.first,
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration(); return
            }
            self.session.addInput(input)
            let output = AVCapturePhotoOutput()
            guard self.session.canAddOutput(output) else {
                self.session.commitConfiguration(); return
            }
            self.session.addOutput(output)
            self.photoOutput = output
            self.session.commitConfiguration()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let layer = AVCaptureVideoPreviewLayer(session: self.session)
                layer.videoGravity = .resizeAspectFill
                layer.frame = self.view.bounds
                self.view.layer.insertSublayer(layer, at: 0)
                self.previewLayer = layer
            }
            self.session.startRunning()
        }
    }

    private func setupUI() {
        let guide = UIView()
        guide.translatesAutoresizingMaskIntoConstraints = false
        guide.layer.borderColor = UIColor.white.withAlphaComponent(0.7).cgColor
        guide.layer.borderWidth = 1.5
        guide.layer.cornerRadius = 999
        guide.isUserInteractionEnabled = false
        view.addSubview(guide)
        NSLayoutConstraint.activate([
            guide.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            guide.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            guide.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.72),
            guide.heightAnchor.constraint(equalTo: guide.widthAnchor)
        ])

        flashButton.translatesAutoresizingMaskIntoConstraints = false
        flashButton.setImage(icon("bolt.badge.automatic", size: 22), for: .normal)
        flashButton.tintColor = .yellow
        flashButton.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        flashButton.layer.cornerRadius = 22
        flashButton.addTarget(self, action: #selector(toggleFlash), for: .touchUpInside)
        view.addSubview(flashButton)
        NSLayoutConstraint.activate([
            flashButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            flashButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            flashButton.widthAnchor.constraint(equalToConstant: 44),
            flashButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.backgroundColor = .white
        shutterButton.layer.cornerRadius = 36
        shutterButton.layer.borderWidth = 4
        shutterButton.layer.borderColor = UIColor.systemGray3.cgColor
        shutterButton.addTarget(self, action: #selector(takePhoto), for: .touchUpInside)
        view.addSubview(shutterButton)
        NSLayoutConstraint.activate([
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            shutterButton.widthAnchor.constraint(equalToConstant: 72),
            shutterButton.heightAnchor.constraint(equalToConstant: 72)
        ])
    }

    private func icon(_ name: String, size: CGFloat) -> UIImage? {
        UIImage(systemName: name,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .medium))
    }

    @objc private func toggleFlash() {
        switch flashMode {
        case .auto:
            flashMode = .on
            flashButton.setImage(icon("bolt.fill", size: 22), for: .normal)
            flashButton.tintColor = .yellow
        case .on:
            flashMode = .off
            flashButton.setImage(icon("bolt.slash.fill", size: 22), for: .normal)
            flashButton.tintColor = .white
        default:
            flashMode = .auto
            flashButton.setImage(icon("bolt.badge.automatic", size: 22), for: .normal)
            flashButton.tintColor = .yellow
        }
    }

    @objc private func takePhoto() {
        captureTimestamp = Date()
        let currentFlash = flashMode
        let output = photoOutput
        sessionQueue.async { [weak self] in
            guard self != nil else { return }
            let settings = AVCapturePhotoSettings()
            if output.supportedFlashModes.contains(currentFlash) {
                settings.flashMode = currentFlash
            }
            output.capturePhoto(with: settings, delegate: self!)
        }
    }
}

extension CameraReaderViewController: @preconcurrency AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        let ts = captureTimestamp
        let maxDim: CGFloat = 1600
        let size = image.size
        let finalImage: UIImage
        if max(size.width, size.height) > maxDim {
            let scale = maxDim / max(size.width, size.height)
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            finalImage = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        } else {
            finalImage = image
        }
        DispatchQueue.main.async { [weak self] in self?.onCapture?(finalImage, ts) }
    }
}
