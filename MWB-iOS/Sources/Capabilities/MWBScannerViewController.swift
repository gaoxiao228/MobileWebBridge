import UIKit
import AVFoundation
import PhotosUI
import Vision

/// 相机和相册共用同一套码型筛选；相册保留 Vision 原有支持的码型。
struct MWBScanOptions {
    let scanTypes: Set<String>
    let showAlbum: Bool

    init?(params: [String: Any]) {
        let supported: Set<String> = ["qrCode", "barCode"]
        if let raw = params["scanType"] {
            guard let types = raw as? [String], !types.isEmpty, supported.isSuperset(of: types) else { return nil }
            scanTypes = Set(types)
        } else {
            scanTypes = supported
        }
        showAlbum = !(params["hideAlbum"] as? Bool ?? false)
    }

    func match(_ candidates: [(type: String, text: String?)]) -> MWBResult? {
        for (type, text) in candidates where scanTypes.contains(type) {
            if let text, !text.isEmpty { return .success(["scanType": type, "code": text]) }
        }
        return nil
    }

    func decodeAlbum(_ image: UIImage?) -> MWBResult {
        guard let image, let cgImage = image.cgImage else { return .failure(-1002, "Cannot read image") }
        let orientation: CGImagePropertyOrientation
        switch image.imageOrientation {
        case .up: orientation = .up
        case .upMirrored: orientation = .upMirrored
        case .down: orientation = .down
        case .downMirrored: orientation = .downMirrored
        case .left: orientation = .left
        case .leftMirrored: orientation = .leftMirrored
        case .right: orientation = .right
        case .rightMirrored: orientation = .rightMirrored
        @unknown default: orientation = .up
        }
        let request = VNDetectBarcodesRequest()
        if scanTypes == ["qrCode"] { request.symbologies = [.qr] }
        do {
            try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
            let candidates = (request.results ?? []).map { ($0.symbology == .qr ? "qrCode" : "barCode", $0.payloadStringValue) }
            return match(candidates) ?? .failure(-1004, "No matching code in image")
        } catch {
            return .failure(-1002, error.localizedDescription)
        }
    }
}

/// 基于系统相机和 Vision 的扫码页，不引入第三方扫码依赖。
final class MWBScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate,
                                      PHPickerViewControllerDelegate {
    private enum Phase { case camera, picking, decoding, finished }

    private let options: MWBScanOptions
    private let completion: (MWBResult) -> Void
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.mobilewebbridge.scan.camera", qos: .userInitiated)
    private let imageQueue = DispatchQueue(label: "com.mobilewebbridge.scan.image", qos: .userInitiated)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private lazy var chrome = MWBScannerChrome(showAlbum: options.showAlbum)
    private var imageLoad: Progress?
    // UI、选图状态及完成回调仅在主线程读写；相机启动和停止在串行队列执行。
    private var phase = Phase.camera
    private var visible = false
    private var closing = false

    init(options: MWBScanOptions, completion: @escaping (MWBResult) -> Void) {
        self.options = options
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(options:completion:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 21/255, green: 31/255, blue: 32/255, alpha: 1)
        if !setupCamera() {
            // 等当前 present() 建立后再由协调器关闭扫码页。
            DispatchQueue.main.async { [weak self] in self?.complete(.failure(-1004, "Camera is unavailable")) }
        }
        chrome.onClose = { [weak self] in self?.cancel() }
        chrome.onAlbum = { [weak self] in self?.openAlbum() }
        chrome.frame = view.bounds
        chrome.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(chrome)
        let notifications = NotificationCenter.default
        notifications.addObserver(self, selector: #selector(resumeScanMotion),
                                  name: UIApplication.didBecomeActiveNotification, object: nil)
        notifications.addObserver(self, selector: #selector(stopScanMotion),
                                  name: UIApplication.willResignActiveNotification, object: nil)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        visible = true
        startCameraIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        visible = false
        closing = isBeingDismissed || presentingViewController?.isBeingDismissed == true
        stopCamera()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // 宿主可直接关闭扫码页；呈现系统选图器不代表扫码结束。
        if closing { cancel() }
    }

    private func startCameraIfNeeded() {
        guard visible, phase == .camera, previewLayer != nil else { return }
        resumeScanMotion()
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    private func stopCamera() {
        stopScanMotion()
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    @objc private func resumeScanMotion() {
        chrome.setScanning(visible && phase == .camera && previewLayer != nil && UIApplication.shared.applicationState == .active)
    }

    @objc private func stopScanMotion() { chrome.setScanning(false) }

    private func setupCamera() -> Bool {
        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            return false
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        let requested: [AVMetadataObject.ObjectType] = options.scanTypes.flatMap { type in
            type == "qrCode" ? [.qr] : (type == "barCode" ? [.ean8, .ean13, .code128, .code39, .pdf417] : [])
        }
        let available = requested.filter(output.availableMetadataObjectTypes.contains)
        guard !available.isEmpty else { return false }
        output.metadataObjectTypes = available
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview
        NotificationCenter.default.addObserver(self, selector: #selector(cameraRuntimeError(_:)),
                                               name: AVCaptureSession.runtimeErrorNotification, object: session)
        return true
    }

    @objc private func cameraRuntimeError(_ notification: Notification) {
        let reset = (notification.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code == .mediaServicesWereReset
        DispatchQueue.main.async { [weak self] in
            guard let self, self.phase == .camera, self.visible else { return }
            // 与相机中断不同，其他运行时错误可能再也不交付相机帧。
            if reset { self.startCameraIfNeeded() }
            else { self.complete(.failure(-1004, "Camera is unavailable")) }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard phase == .camera, visible else { return }
        let candidates = metadataObjects.compactMap { $0 as? AVMetadataMachineReadableCodeObject }
            .map { ($0.type == .qr ? "qrCode" : "barCode", $0.stringValue) }
        if let result = options.match(candidates) { complete(result) }
    }

    @objc private func cancel() { complete(.failure(-1007, "Cancelled")) }

    @objc private func openAlbum() {
        guard phase == .camera, visible else { return }
        phase = .picking
        stopCamera()
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        picker.modalPresentationStyle = .fullScreen
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard phase == .picking else { return }
        guard let provider = results.first?.itemProvider else {
            // 取消选图不结束桥调用；等系统选择器收起再恢复相机。
            picker.dismiss(animated: true) { [weak self] in
                guard let self, self.phase == .picking else { return }
                self.phase = .camera
                self.startCameraIfNeeded()
            }
            return
        }
        phase = .decoding
        picker.dismiss(animated: true) { [weak self] in self?.decode(provider) }
    }

    private func decode(_ provider: NSItemProvider) {
        guard phase == .decoding else { return }
        guard provider.canLoadObject(ofClass: UIImage.self) else {
            complete(.failure(-1002, "Cannot read image"))
            return
        }
        let options = self.options
        let queue = imageQueue
        imageLoad = provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            queue.async { [weak self] in
                guard self != nil else { return }
                let result = options.decodeAlbum(object as? UIImage)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.phase == .decoding else { return }
                    self.complete(result)
                }
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        imageLoad?.cancel()
    }

    private func complete(_ result: MWBResult) {
        guard phase != .finished else { return }
        phase = .finished
        imageLoad?.cancel()
        imageLoad = nil
        stopCamera()
        completion(result)
    }
}

/// 叠在取景预览上方的界面，不依赖相机，也不限制识别区域。
final class MWBScannerChrome: UIView {
    private static let foreground = UIColor(red: 247/255, green: 250/255, blue: 249/255, alpha: 1)
    private static let mint = UIColor(red: 115/255, green: 244/255, blue: 197/255, alpha: 1)
    private static let sweepKey = "scanSweep"

    var onClose: (() -> Void)?
    var onAlbum: (() -> Void)?

    private let shade = CAShapeLayer()
    private let border = CAShapeLayer()
    private let corners = CAShapeLayer()
    private let cornerClips = CAShapeLayer()
    private let track = CALayer()
    private let sweep = CALayer()
    private let tail = CAGradientLayer()
    private let line = CAGradientLayer()
    private let sweepEdges = CAGradientLayer()
    private var scanning = false

    private let title = UILabel()
    private let hint = UILabel()
    private let close = Control(type: .system)
    private let album: UIButton?

    init(showAlbum: Bool) {
        album = showAlbum ? Control(type: .system) : nil
        super.init(frame: .zero)
        setUpDrawing()
        configure(title, text: "扫一扫", size: 17, weight: .semibold, style: .headline)
        title.accessibilityTraits.insert(.header)
        configure(hint, text: "将二维码或条形码放入框内", size: 13, style: .footnote)
        hint.textColor = UIColor(red: 225/255, green: 233/255, blue: 231/255, alpha: 1)
        addSubview(title)
        addSubview(hint)
        configure(close, symbol: "xmark", label: "关闭", diameter: 36, action: #selector(didClose))
        if let album {
            configure(album, symbol: "photo.on.rectangle", label: "相册", diameter: 48, action: #selector(didOpenAlbum))
            let caption = UILabel(frame: CGRect(x: 0, y: 54, width: 76, height: 19))
            configure(caption, text: "相册", size: 12, style: .caption1)
            caption.isAccessibilityElement = false
            album.addSubview(caption)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(updateSweep),
                                               name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(showAlbum:)") }

    deinit { NotificationCenter.default.removeObserver(self) }

    // 与 Android 使用相同的安全区比例和留白，外观不受相册入口显隐影响。
    nonisolated static func viewfinder(in safe: CGRect) -> CGRect {
        let edge = max(0, min(safe.width * 0.67, 320, safe.height - 202))
        let minTop = safe.minY + 58
        let maxTop = max(minTop, safe.maxY - 144 - edge)
        let top = min(max(safe.minY + safe.height * 0.45 - edge / 2, minTop), maxTop)
        return CGRect(x: safe.midX - edge / 2, y: top, width: edge, height: edge)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 首次挂载前布局时 guide 可能尚未求值；直接用当前 bounds 和系统安全边距。
        let safe = bounds.inset(by: safeAreaInsets)
        let frame = Self.viewfinder(in: safe)
        title.frame = CGRect(x: safe.minX + 57, y: safe.minY + 4, width: max(0, safe.width - 114), height: 44)
        close.frame = CGRect(x: safe.minX + 13, y: safe.minY + 4, width: 44, height: 44)
        hint.frame = CGRect(x: safe.minX + 8, y: frame.maxY + 17, width: max(0, safe.width - 16), height: 24)
        album?.frame = CGRect(x: safe.midX - 38, y: safe.maxY - 97, width: 76, height: 73)
        layoutReticle(frame)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    private func configure(_ label: UILabel, text: String, size: CGFloat, weight: UIFont.Weight = .regular,
                           style: UIFont.TextStyle) {
        label.text = text
        label.textColor = Self.foreground
        label.textAlignment = .center
        label.font = UIFontMetrics(forTextStyle: style)
            .scaledFont(for: .systemFont(ofSize: size, weight: weight), maximumPointSize: size * 1.4)
        label.adjustsFontForContentSizeCategory = true
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
    }

    private func configure(_ button: UIButton, symbol: String, label: String, diameter: CGFloat, action: Selector) {
        let hasCaption = diameter == 48
        let badge = UIImageView(frame: CGRect(x: ((hasCaption ? 76 : 44) - diameter) / 2,
                                               y: hasCaption ? 0 : 4, width: diameter, height: diameter))
        badge.backgroundColor = Self.foreground.withAlphaComponent(0.1)
        badge.tintColor = Self.foreground
        badge.layer.cornerRadius = diameter / 2
        badge.clipsToBounds = true
        if hasCaption {
            badge.layer.borderWidth = 1
            badge.layer.borderColor = Self.foreground.withAlphaComponent(0.18).cgColor
        }
        badge.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: hasCaption ? 20 : 17))
        badge.contentMode = .center
        badge.isAccessibilityElement = false
        button.addSubview(badge)
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
        addSubview(button)
    }

    // 自绘图标仍使用系统按钮事件和按下反馈。
    private final class Control: UIButton {
        override var isHighlighted: Bool {
            didSet { alpha = isHighlighted ? 0.65 : 1 }
        }
    }

    @objc private func didClose() { onClose?() }
    @objc private func didOpenAlbum() { onAlbum?() }

    private func setUpDrawing() {
        shade.fillRule = .evenOdd
        shade.fillColor = UIColor(red: 8/255, green: 15/255, blue: 20/255, alpha: 0.72).cgColor
        border.fillColor = UIColor.clear.cgColor
        border.strokeColor = Self.foreground.withAlphaComponent(0.3).cgColor
        border.lineWidth = 1
        corners.fillColor = UIColor.clear.cgColor
        corners.strokeColor = Self.mint.cgColor
        corners.lineWidth = 2
        corners.mask = cornerClips
        track.masksToBounds = true
        sweepEdges.startPoint = CGPoint(x: 0, y: 0.5)
        sweepEdges.endPoint = CGPoint(x: 1, y: 0.5)
        sweepEdges.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        sweepEdges.locations = [0.01, 0.18, 0.82, 0.99]
        sweep.mask = sweepEdges
        tail.colors = [Self.mint.withAlphaComponent(0).cgColor, Self.mint.withAlphaComponent(0.34).cgColor]
        line.startPoint = CGPoint(x: 0, y: 0.5)
        line.endPoint = CGPoint(x: 1, y: 0.5)
        line.colors = [Self.mint.cgColor, UIColor(red: 215/255, green: 1, blue: 235/255, alpha: 1).cgColor, Self.mint.cgColor]
        sweep.addSublayer(tail)
        sweep.addSublayer(line)
        track.addSublayer(sweep)
        [shade, border, track, corners].forEach { layer.addSublayer($0) }
    }

    private func layoutReticle(_ rect: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let outer = UIBezierPath(rect: bounds)
        let window = UIBezierPath(roundedRect: rect, cornerRadius: 14)
        if !rect.isEmpty { outer.append(window) }
        shade.frame = bounds
        border.frame = bounds
        corners.frame = bounds
        shade.path = outer.cgPath
        border.path = rect.isEmpty ? nil : window.cgPath
        corners.path = border.path
        cornerClips.frame = bounds
        let clip = UIBezierPath()
        let length = min(24, rect.width / 2)
        for x in [rect.minX, rect.maxX - length] {
            for y in [rect.minY, rect.maxY - length] {
                clip.append(UIBezierPath(rect: CGRect(x: x - 1, y: y - 1, width: length + 2, height: length + 2)))
            }
        }
        cornerClips.path = clip.cgPath
        let nextTrack = rect.width > 10 ? rect.insetBy(dx: 5, dy: 5) : .zero
        guard nextTrack != track.frame else { return }
        track.frame = nextTrack
        sweep.bounds = CGRect(x: 0, y: 0, width: track.bounds.width, height: 30)
        sweep.anchorPoint = CGPoint(x: 0.5, y: 1)
        sweep.position = CGPoint(x: track.bounds.midX, y: track.bounds.midY)
        sweepEdges.frame = sweep.bounds
        tail.frame = sweep.bounds
        line.frame = CGRect(x: 0, y: 28, width: sweep.bounds.width, height: 2)
        sweep.removeAnimation(forKey: Self.sweepKey)
        updateSweep()
    }

    func setScanning(_ active: Bool) {
        scanning = active
        updateSweep()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateSweep()
    }

    @objc private func updateSweep() {
        guard scanning, window != nil, !UIAccessibility.isReduceMotionEnabled, track.bounds.height > 0 else {
            sweep.removeAnimation(forKey: Self.sweepKey)
            return
        }
        guard sweep.animation(forKey: Self.sweepKey) == nil else { return }
        let travel = CAKeyframeAnimation(keyPath: "position.y")
        travel.values = [track.bounds.height * 0.04, track.bounds.height * 0.97, track.bounds.height * 0.97]
        travel.keyTimes = [0, 0.94, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0, 0]
        fade.keyTimes = [0, 0.09, 0.79, 0.94, 1]
        // 透明时才从底部回到顶部；减少动态效果时保留居中的静态扫描线。
        let cycle = CAAnimationGroup()
        cycle.duration = 2.3
        travel.duration = cycle.duration
        fade.duration = cycle.duration
        cycle.animations = [travel, fade]
        cycle.repeatCount = .infinity
        sweep.add(cycle, forKey: Self.sweepKey)
    }
}
