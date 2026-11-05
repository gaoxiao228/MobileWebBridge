import UIKit
import AVFoundation
import Photos

/// 仅在 MWB 专用缓存目录中创建和读取媒体文件，避免网页读取任意 App 文件。
enum MWBMediaFiles {
    static var directory: URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MWBMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func trustedURL(_ path: String) -> URL? {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let root = directory.standardizedFileURL.resolvingSymlinksInPath().path
        return url.path.hasPrefix(root + "/") ? url : nil
    }

    static func image(from base64: String) -> UIImage? {
        let encoded = base64.components(separatedBy: "base64,").last ?? base64
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return UIImage(data: data)
    }

    static func save(_ image: UIImage, quality: CGFloat = 0.85) -> URL? {
        guard let data = image.jpegData(compressionQuality: quality) else { return nil }
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

/// 媒体 API 将耗时操作交给系统框架，并统一转成 MWB 的结果格式。
extension MWBBridgeAdapter {
    @objc func checkRequestCameraPermissions(_ arg: Any?, handler: @escaping MWBJSCallback) {
        guard !rejectUntrusted(handler) else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            respond(.success(["grant": true]), with: handler)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                self.respond(.success(["grant": granted]), with: handler)
            }
        default:
            respond(.success(["grant": false]), with: handler)
        }
    }

    @objc func compressImage(_ arg: Any?, handler: @escaping MWBJSCallback) {
        guard !rejectUntrusted(handler) else { return }
        guard let params = arg as? [String: Any],
              let base64 = params["base64Image"] as? String,
              let image = MWBMediaFiles.image(from: base64) else {
            respond(.failure(-1001, "Invalid image"), with: handler)
            return
        }
        let limit = max(1, params["maxLength"] as? Int ?? Int.max)
        DispatchQueue.global(qos: .userInitiated).async {
            var quality: CGFloat = 0.9
            var output = image.jpegData(compressionQuality: quality)
            while let data = output, data.count > limit, quality > 0.1 {
                quality -= 0.1
                output = image.jpegData(compressionQuality: quality)
            }
            guard let output, output.count <= limit else {
                self.respond(.failure(-1004, "Image exceeds maxLength"), with: handler)
                return
            }
            self.respond(.success([
                "base64Image": output.base64EncodedString(),
                "imageWidth": Int(image.size.width),
                "imageHeight": Int(image.size.height)
            ]), with: handler)
        }
    }

    @objc func scanCode(_ arg: Any?, handler: @escaping MWBJSCallback) {
        guard !rejectUntrusted(handler) else { return }
        mediaCoordinator.scan(params: arg as? [String: Any] ?? [:], callback: handler)
    }

    @objc func chooseImage(_ arg: Any?, handler: @escaping MWBJSCallback) {
        guard !rejectUntrusted(handler) else { return }
        guard let params = arg as? [String: Any], params["sourceType"] is String else {
            respond(.failure(-1001, "sourceType is required"), with: handler)
            return
        }
        mediaCoordinator.chooseImage(params: params, callback: handler)
    }

    @objc func saveImageToPhotosAlbum(_ arg: Any?, handler: @escaping MWBJSCallback) {
        guard !rejectUntrusted(handler) else { return }
        guard let base64 = (arg as? [String: Any])?["base64Image"] as? String,
              let image = MWBMediaFiles.image(from: base64) else {
            respond(.failure(-1001, "Invalid image"), with: handler)
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                self.respond(.failure(-1008, "Photo library permission denied"), with: handler)
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                self.respond(success ? .success() : .failure(-1002, error?.localizedDescription ?? "Save failed"),
                             with: handler)
            }
        }
    }

    @objc func convertImagePathToBase64(_ arg: Any?, handler: @escaping MWBJSCallback) {
        guard !rejectUntrusted(handler) else { return }
        guard let path = (arg as? [String: Any])?["path"] as? String,
              let url = MWBMediaFiles.trustedURL(path),
              let data = try? Data(contentsOf: url) else {
            respond(.failure(-1001, "Invalid image path"), with: handler)
            return
        }
        respond(.success(["base64Image": data.base64EncodedString()]), with: handler)
    }

    @objc func openFile(_ arg: Any?, handler: @escaping MWBJSCallback) {
        guard !rejectUntrusted(handler) else { return }
        guard let text = (arg as? [String: Any])?["url"] as? String,
              let url = URL(string: text) else {
            respond(.failure(-1001, "File URL is required"), with: handler)
            return
        }
        mediaCoordinator.openFile(url: url, callback: handler)
    }
}
