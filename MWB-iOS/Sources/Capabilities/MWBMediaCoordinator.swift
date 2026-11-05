import UIKit
import PhotosUI
import QuickLook
import AVFoundation

/// 持有系统选择器回调，直到用户选图、扫码或取消操作。
final class MWBMediaCoordinator: NSObject, PHPickerViewControllerDelegate,
                                 UIImagePickerControllerDelegate, UINavigationControllerDelegate,
                                 QLPreviewControllerDataSource {
    private weak var controller: UIViewController?
    private var pending: MWBJSCallback?
    private weak var presented: UIViewController?
    private var previewURL: URL?

    init(controller: UIViewController?) {
        self.controller = controller
    }

    private func begin(_ callback: @escaping MWBJSCallback) -> Bool {
        guard pending == nil else {
            callback(MWBResult.failure(-1008, "Another media operation is in progress").jsonString, true)
            return false
        }
        pending = callback
        return true
    }

    private func finish(_ result: MWBResult) {
        DispatchQueue.main.async {
            self.presented?.dismiss(animated: true)
            self.pending?(result.jsonString, true)
            self.pending = nil
            self.presented = nil
        }
    }

    func chooseImage(params: [String: Any], callback: @escaping MWBJSCallback) {
        guard begin(callback) else { return }
        let source = params["sourceType"] as? String ?? ""
        DispatchQueue.main.async {
            switch source {
            case "album": self.showAlbum(limit: params["count"] as? Int ?? 1)
            case "camera": self.showCamera()
            case "all":
                guard let controller = self.controller else {
                    self.finish(.failure(-1005, "Container is unavailable"))
                    return
                }
                let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
                sheet.addAction(UIAlertAction(title: "相册", style: .default) { _ in
                    self.showAlbum(limit: params["count"] as? Int ?? 1)
                })
                sheet.addAction(UIAlertAction(title: "相机", style: .default) { _ in self.showCamera() })
                sheet.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
                    self.finish(.failure(-1007, "Cancelled"))
                })
                sheet.popoverPresentationController?.sourceView = controller.view
                sheet.popoverPresentationController?.sourceRect = CGRect(x: controller.view.bounds.midX,
                                                                         y: controller.view.bounds.midY,
                                                                         width: 1, height: 1)
                controller.present(sheet, animated: true)
            default:
                self.finish(.failure(-1001, "Invalid sourceType"))
            }
        }
    }

    private func showAlbum(limit: Int) {
        guard let controller else {
            finish(.failure(-1005, "Container is unavailable"))
            return
        }
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = max(1, limit)
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        presented = picker
        controller.present(picker, animated: true)
    }

    private func showCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            finish(.failure(-1004, "Camera is unavailable"))
            return
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.presentCamera() }
                    else { self.finish(.failure(-1008, "Camera permission denied")) }
                }
            }
        } else if status == .authorized {
            presentCamera()
        } else {
            finish(.failure(-1008, "Camera permission denied"))
        }
    }

    private func presentCamera() {
        guard let controller else {
            finish(.failure(-1005, "Container is unavailable"))
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        presented = picker
        controller.present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard !results.isEmpty else {
            finish(.failure(-1007, "Cancelled"))
            return
        }
        let group = DispatchGroup()
        let lock = NSLock()
        var files: [Int: [String: String]] = [:]
        for (index, item) in results.enumerated() where item.itemProvider.canLoadObject(ofClass: UIImage.self) {
            group.enter()
            item.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                defer { group.leave() }
                guard let image = object as? UIImage,
                      let original = MWBMediaFiles.save(image, quality: 1),
                      let compressed = MWBMediaFiles.save(image, quality: 0.65) else { return }
                lock.lock()
                files[index] = ["original": original.path, "compressed": compressed.path]
                lock.unlock()
            }
        }
        group.notify(queue: .main) {
            let data = files.sorted(by: { $0.key < $1.key }).map(\.value)
            self.finish(data.isEmpty ? .failure(-1002, "Cannot load image") : .success(["data": data]))
        }
    }

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        guard let image = info[.originalImage] as? UIImage,
              let original = MWBMediaFiles.save(image, quality: 1),
              let compressed = MWBMediaFiles.save(image, quality: 0.65) else {
            finish(.failure(-1002, "Cannot save image"))
            return
        }
        finish(.success(["data": [["original": original.path, "compressed": compressed.path]]]))
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        finish(.failure(-1007, "Cancelled"))
    }

    func scan(params: [String: Any], callback: @escaping MWBJSCallback) {
        guard begin(callback) else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let present: () -> Void = {
            guard let controller = self.controller else {
                self.finish(.failure(-1005, "Container is unavailable"))
                return
            }
            let scanner = MWBScannerViewController(
                scanTypes: params["scanType"] as? [String] ?? ["qrCode", "barCode"],
                showAlbum: !(params["hideAlbum"] as? Bool ?? false)
            ) { result in self.finish(result) }
            self.presented = scanner
            controller.present(scanner, animated: true)
        }
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { present() }
                    else { self.finish(.failure(-1008, "Camera permission denied")) }
                }
            }
        } else if status == .authorized {
            DispatchQueue.main.async(execute: present)
        } else {
            finish(.failure(-1008, "Camera permission denied"))
        }
    }

    func openFile(url: URL, callback: @escaping MWBJSCallback) {
        guard begin(callback) else { return }
        if url.isFileURL {
            guard let trusted = MWBMediaFiles.trustedURL(url.path) else {
                finish(.failure(-1006, "Untrusted file path"))
                return
            }
            showPreview(trusted)
            return
        }
        guard url.scheme == "https" else {
            finish(.failure(-1001, "Only HTTPS file URLs are supported"))
            return
        }
        URLSession.shared.downloadTask(with: url) { temporary, _, error in
            guard let temporary else {
                self.finish(.failure(-1002, error?.localizedDescription ?? "Download failed"))
                return
            }
            let name = url.lastPathComponent.isEmpty ? "document.pdf" : url.lastPathComponent
            let destination = MWBMediaFiles.directory.appendingPathComponent(UUID().uuidString + "-" + name)
            do {
                try FileManager.default.copyItem(at: temporary, to: destination)
                self.showPreview(destination)
            } catch {
                self.finish(.failure(-1002, error.localizedDescription))
            }
        }.resume()
    }

    private func showPreview(_ url: URL) {
        DispatchQueue.main.async {
            guard let controller = self.controller else {
                self.finish(.failure(-1005, "Container is unavailable"))
                return
            }
            self.previewURL = url
            let preview = QLPreviewController()
            preview.dataSource = self
            self.presented = preview
            controller.present(preview, animated: true)
            self.pending?(MWBResult.success().jsonString, true)
            self.pending = nil
        }
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        (previewURL ?? MWBMediaFiles.directory) as NSURL
    }
}
