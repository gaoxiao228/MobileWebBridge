import UIKit
import AVFoundation
import PhotosUI
import Vision

/// 基于系统相机和 Vision 的扫码页，不引入第三方扫码依赖。
final class MWBScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate,
                                      PHPickerViewControllerDelegate {
    private let scanTypes: [String]
    private let showAlbum: Bool
    private let completion: (MWBResult) -> Void
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var completed = false

    init(scanTypes: [String], showAlbum: Bool, completion: @escaping (MWBResult) -> Void) {
        self.scanTypes = scanTypes
        self.showAlbum = showAlbum
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(scanTypes:showAlbum:completion:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        let close = UIButton(type: .system)
        close.setTitle("关闭", for: .normal)
        close.tintColor = .white
        close.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        close.frame = CGRect(x: 20, y: 50, width: 64, height: 44)
        view.addSubview(close)
        if showAlbum {
            let album = UIButton(type: .system)
            album.setTitle("相册", for: .normal)
            album.tintColor = .white
            album.addTarget(self, action: #selector(openAlbum), for: .touchUpInside)
            album.frame = CGRect(x: view.bounds.width - 84, y: 50, width: 64, height: 44)
            album.autoresizingMask = [.flexibleLeftMargin]
            view.addSubview(album)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.session.stopRunning() }
        }
    }

    private func setupCamera() {
        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            complete(.failure(-1004, "Camera is unavailable"))
            return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            complete(.failure(-1004, "Scanner is unavailable"))
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        let requested: [AVMetadataObject.ObjectType] = scanTypes.flatMap { type in
            type == "qrCode" ? [.qr] : (type == "barCode" ? [.ean8, .ean13, .code128, .code39, .pdf417] : [])
        }
        output.metadataObjectTypes = requested.isEmpty ? [.qr] : requested.filter(output.availableMetadataObjectTypes.contains)
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let code = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
              let value = code.stringValue else { return }
        complete(.success(["scanType": code.type == .qr ? "qrCode" : "barCode", "code": value]))
    }

    @objc private func cancel() { complete(.failure(-1007, "Cancelled")) }

    @objc private func openAlbum() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage, let cgImage = image.cgImage else { return }
            let request = VNDetectBarcodesRequest()
            do {
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
                guard let observation = request.results?.first,
                      let value = observation.payloadStringValue else {
                    self?.complete(.failure(-1004, "No code found in image"))
                    return
                }
                let type = observation.symbology == .qr ? "qrCode" : "barCode"
                self?.complete(.success(["scanType": type, "code": value]))
            } catch {
                self?.complete(.failure(-1002, error.localizedDescription))
            }
        }
    }

    private func complete(_ result: MWBResult) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.completed else { return }
            self.completed = true
            self.completion(result)
        }
    }
}
