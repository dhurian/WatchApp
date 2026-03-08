//
//  FullCameraViewController.swift
//  WatchApp
//

import UIKit
import AVFoundation

class FullCameraViewController: UIViewController {

    var onCapture: ((UIImage) -> Void)?
    var onDismiss: (() -> Void)?

    // MARK: - AV Properties (accessed only on sessionQueue)
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var photoOutput = AVCapturePhotoOutput()
    private var currentPosition: AVCaptureDevice.Position = .back

    // MARK: - Main thread properties
    private var flashMode: AVCaptureDevice.FlashMode = .auto
    private var countdownSeconds = 0
    private var countdownTimer: Timer?
    private let timerOptions = [0, 3, 10]
    private var timerIndex = 0

    // MARK: - UI
    private let previewContainer = UIView()
    private let captureButton = UIButton()
    private let flipButton = UIButton()
    private let flashButton = UIButton()
    private let closeButton = UIButton()
    private let timerButton = UIButton()
    private let countdownLabel = UILabel()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupUI()
        checkPermissionAndSetup()
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
        countdownTimer?.invalidate()
        countdownTimer = nil
        // Stop synchronously so hardware powers down immediately
        sessionQueue.sync { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
        // Remove preview layer immediately to free GPU
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Remove all inputs and outputs to fully release camera hardware
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }
            self.session.commitConfiguration()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = previewContainer.bounds
    }

    // MARK: - Preview Layer (main thread only)
    private var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - Permission + Setup

    private func checkPermissionAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { [weak self] in self?.configureSession() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.sessionQueue.async { self?.configureSession() } }
            }
        default:
            break
        }
    }

    // Called on sessionQueue
    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = bestCamera(for: currentPosition),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        photoOutput = output
        session.commitConfiguration()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let layer = AVCaptureVideoPreviewLayer(session: self.session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = self.previewContainer.bounds
            self.previewContainer.layer.addSublayer(layer)
            self.previewLayer = layer
        }

        session.startRunning()
    }

    private func bestCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera,
            .builtInDualCamera, .builtInWideAngleCamera
        ]
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: position).devices.first
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    // MARK: - Setup UI

    private func setupUI() {
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewContainer)
        NSLayoutConstraint.activate([
            previewContainer.topAnchor.constraint(equalTo: view.topAnchor),
            previewContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            previewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        let controlBar = UIView()
        controlBar.translatesAutoresizingMaskIntoConstraints = false
        controlBar.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        view.addSubview(controlBar)
        NSLayoutConstraint.activate([
            controlBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            controlBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controlBar.heightAnchor.constraint(equalToConstant: 110)
        ])

        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.backgroundColor = .white
        captureButton.layer.cornerRadius = 36
        captureButton.layer.borderWidth = 4
        captureButton.layer.borderColor = UIColor.systemGray3.cgColor
        captureButton.addTarget(self, action: #selector(captureButtonTapped), for: .touchUpInside)
        controlBar.addSubview(captureButton)
        NSLayoutConstraint.activate([
            captureButton.centerXAnchor.constraint(equalTo: controlBar.centerXAnchor),
            captureButton.centerYAnchor.constraint(equalTo: controlBar.centerYAnchor),
            captureButton.widthAnchor.constraint(equalToConstant: 72),
            captureButton.heightAnchor.constraint(equalToConstant: 72)
        ])

        flipButton.translatesAutoresizingMaskIntoConstraints = false
        flipButton.setImage(icon("camera.rotate", size: 26), for: .normal)
        flipButton.tintColor = .white
        flipButton.addTarget(self, action: #selector(flipCamera), for: .touchUpInside)
        controlBar.addSubview(flipButton)
        NSLayoutConstraint.activate([
            flipButton.centerYAnchor.constraint(equalTo: controlBar.centerYAnchor),
            flipButton.trailingAnchor.constraint(equalTo: controlBar.trailingAnchor, constant: -32),
            flipButton.widthAnchor.constraint(equalToConstant: 48),
            flipButton.heightAnchor.constraint(equalToConstant: 48)
        ])

        let topBar = UIView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        view.addSubview(topBar)
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 90)
        ])

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(icon("xmark", size: 18), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        topBar.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 20),
            closeButton.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -14),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        flashButton.translatesAutoresizingMaskIntoConstraints = false
        flashButton.setImage(icon("bolt.badge.automatic", size: 22), for: .normal)
        flashButton.tintColor = .yellow
        flashButton.addTarget(self, action: #selector(toggleFlash), for: .touchUpInside)
        topBar.addSubview(flashButton)
        NSLayoutConstraint.activate([
            flashButton.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            flashButton.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -14),
            flashButton.widthAnchor.constraint(equalToConstant: 44),
            flashButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        timerButton.translatesAutoresizingMaskIntoConstraints = false
        timerButton.setImage(icon("timer", size: 22), for: .normal)
        timerButton.tintColor = .white
        timerButton.addTarget(self, action: #selector(toggleTimer), for: .touchUpInside)
        topBar.addSubview(timerButton)
        NSLayoutConstraint.activate([
            timerButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -20),
            timerButton.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -14),
            timerButton.widthAnchor.constraint(equalToConstant: 44),
            timerButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        countdownLabel.translatesAutoresizingMaskIntoConstraints = false
        countdownLabel.font = UIFont.systemFont(ofSize: 96, weight: .thin)
        countdownLabel.textColor = .white
        countdownLabel.textAlignment = .center
        countdownLabel.isHidden = true
        view.addSubview(countdownLabel)
        NSLayoutConstraint.activate([
            countdownLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            countdownLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func icon(_ name: String, size: CGFloat) -> UIImage? {
        UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .medium))
    }

    // MARK: - Actions

    @objc private func captureButtonTapped() {
        let seconds = timerOptions[timerIndex]
        if seconds == 0 { takePhoto() } else { startCountdown(from: seconds) }
    }

    @objc private func flipCamera() {
        let newPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        currentPosition = newPosition
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }
            if let device = self.bestCamera(for: newPosition),
               let input = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            self.session.commitConfiguration()
        }
        UIView.transition(with: previewContainer, duration: 0.35, options: .transitionFlipFromLeft, animations: nil)
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

    @objc private func toggleTimer() {
        timerIndex = (timerIndex + 1) % timerOptions.count
        let seconds = timerOptions[timerIndex]
        if seconds == 0 {
            timerButton.setImage(icon("timer", size: 22), for: .normal)
            timerButton.setTitle(nil, for: .normal)
            timerButton.tintColor = .white
        } else {
            timerButton.setImage(nil, for: .normal)
            timerButton.setTitle("\(seconds)s", for: .normal)
            timerButton.setTitleColor(.yellow, for: .normal)
            timerButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        }
    }

    @objc private func closeTapped() {
        onDismiss?()
    }

    // MARK: - Countdown

    private func startCountdown(from seconds: Int) {
        captureButton.isEnabled = false
        flipButton.isEnabled = false
        countdownSeconds = seconds
        countdownLabel.text = "\(countdownSeconds)"
        countdownLabel.isHidden = false
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.countdownSeconds -= 1
            if self.countdownSeconds <= 0 {
                t.invalidate()
                self.countdownLabel.isHidden = true
                self.captureButton.isEnabled = true
                self.flipButton.isEnabled = true
                self.takePhoto()
            } else {
                self.countdownLabel.text = "\(self.countdownSeconds)"
            }
        }
    }

    // MARK: - Capture

    private func takePhoto() {
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

// MARK: - AVCapturePhotoCaptureDelegate

extension FullCameraViewController: @preconcurrency AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        let maxDim: CGFloat = 2048
        guard let image = UIImage(data: data) else { return }
        let size = image.size
        let longest = max(size.width, size.height)
        let finalImage: UIImage
        if longest > maxDim {
            let scale = maxDim / longest
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            finalImage = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        } else {
            finalImage = image
        }
        DispatchQueue.main.async { [weak self] in
            self?.onCapture?(finalImage)
            self?.onDismiss?()
        }
    }
}
