import CoreImage
import UIKit
import XCTest
@testable import MobileWebBridge

final class CapabilitiesTests: XCTestCase {
    func testScannerChromeCentersTheFrameAndReservesRoomInLandscape() {
        // 与 Android 使用相同的安全区和预期坐标。
        XCTAssertEqual(MWBScannerChrome.viewfinder(in: CGRect(x: 10, y: 40, width: 400, height: 820)),
                       CGRect(x: 76, y: 275, width: 268, height: 268))
        XCTAssertEqual(MWBScannerChrome.viewfinder(in: CGRect(x: 30, y: 8, width: 760, height: 300)),
                       CGRect(x: 361, y: 66, width: 98, height: 98))
    }

    @MainActor func testScannerChromeKeepsTheFrameWhenAlbumIsHiddenAndRoutesActions() throws {
        let withAlbum = MWBScannerChrome(showAlbum: true)
        let withoutAlbum = MWBScannerChrome(showAlbum: false)
        var closed = 0
        var albums = 0
        withAlbum.onClose = { closed += 1 }
        withAlbum.onAlbum = { albums += 1 }
        for chrome in [withAlbum, withoutAlbum] {
            chrome.frame = CGRect(x: 0, y: 0, width: 390, height: 780)
            chrome.layoutIfNeeded()
        }
        func hintFrame(_ chrome: MWBScannerChrome) throws -> CGRect {
            try XCTUnwrap(chrome.subviews.compactMap { $0 as? UILabel }.first {
                $0.text == "将二维码或条形码放入框内"
            }).frame
        }
        func button(_ label: String, in chrome: MWBScannerChrome) -> UIButton? {
            chrome.subviews.compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == label }
        }
        XCTAssertEqual(try hintFrame(withAlbum), try hintFrame(withoutAlbum))
        XCTAssertNil(button("相册", in: withoutAlbum))
        try XCTUnwrap(button("相册", in: withAlbum)).sendActions(for: .touchUpInside)
        try XCTUnwrap(button("关闭", in: withAlbum)).sendActions(for: .touchUpInside)
        XCTAssertEqual(albums, 1)
        XCTAssertEqual(closed, 1)
    }

    @MainActor func testScannerChromeDimsOnlyOutsideTheViewfinder() throws {
        let chrome = MWBScannerChrome(showAlbum: true)
        chrome.frame = CGRect(x: 0, y: 0, width: 390, height: 780)
        chrome.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        // 以纯色代替相机帧，验证实际绘制结果没有把框内一同压暗。
        let image = UIGraphicsImageRenderer(size: chrome.bounds.size, format: format).image { renderer in
            renderer.cgContext.setFillColor(UIColor(red: 0.42, green: 0.62, blue: 0.55, alpha: 1).cgColor)
            renderer.cgContext.fill(chrome.bounds)
            chrome.layer.render(in: renderer.cgContext)
        }
        func green(x: CGFloat, y: CGFloat) throws -> UInt8 {
            let pixel = try XCTUnwrap(image.cgImage?.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
            let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                                  bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)[1]
        }
        let frame = MWBScannerChrome.viewfinder(in: chrome.bounds)
        let y = floor(frame.minY + 22)
        XCTAssertEqual(try Double(green(x: 195, y: y)), 158, accuracy: 3)
        XCTAssertLessThan(try green(x: 20, y: y), 80)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Scanner chrome with a simulated camera surface"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testScanRejectsInvalidTypesBeforeOpeningCamera() {
        let media = MWBMediaCoordinator(controller: nil)
        for invalid in [[], ["unknown"], [1], "qrCode"] as [Any] {
            let callback = expectation(description: "Reject invalid scan types before requesting camera access")
            media.scan(params: ["scanType": invalid]) { json, _ in
                XCTAssertEqual(MWBResult.parse(json)?.errCode, -1001)
                callback.fulfill()
            }
            wait(for: [callback], timeout: 2)
        }
    }

    func testScanOptionsFilterCandidatesAndRejectUnreadableImages() throws {
        let defaults = try XCTUnwrap(MWBScanOptions(params: [:]))
        XCTAssertTrue(defaults.showAlbum)
        XCTAssertEqual(defaults.scanTypes, ["qrCode", "barCode"])
        let bars = try XCTUnwrap(MWBScanOptions(params: ["scanType": ["barCode"], "hideAlbum": true]))
        XCTAssertFalse(bars.showAlbum)
        XCTAssertEqual(defaults.decodeAlbum(nil).errCode, -1002)
        XCTAssertNil(bars.match([("qrCode", "skip"), ("barCode", ""), ("barCode", nil)]))
        let matched = bars.match([("qrCode", "skip"), ("barCode", "123")])?.result as? [String: Any]
        XCTAssertEqual(matched?["code"] as? String, "123")
    }

    func testScanAlbumDecodesRotatedQRAndFiltersRequestedType() throws {
        let payload = "mwb-offline"
        let filter = try XCTUnwrap(CIFilter(name: "CIQRCodeGenerator"))
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        let code = try XCTUnwrap(filter.outputImage).transformed(by: .init(scaleX: 8, y: 8))
        // 给识别样本留出安静区，避免边缘紧贴图片边界。
        let extent = code.extent.insetBy(dx: -32, dy: -32)
        let output = code.composited(over: CIImage(color: .white).cropped(to: extent))
        let cgImage = try XCTUnwrap(CIContext().createCGImage(output, from: extent))
        let image = UIImage(cgImage: cgImage, scale: 1, orientation: .right)

        let defaults = try XCTUnwrap(MWBScanOptions(params: [:]))
        let success = defaults.decodeAlbum(image)
        #if targetEnvironment(simulator)
        try XCTSkipIf(success.errCode == -1002 && success.errorMsg == "Could not create inference context",
                      "This simulator runtime cannot initialize Vision barcode inference; verify on device.")
        #endif
        XCTAssertEqual(success.errCode, 0, success.errorMsg ?? "")
        let result = success.result as? [String: Any]
        XCTAssertEqual(result?["scanType"] as? String, "qrCode")
        XCTAssertEqual(result?["code"] as? String, payload)

        let bars = try XCTUnwrap(MWBScanOptions(params: ["scanType": ["barCode"]]))
        XCTAssertEqual(bars.decodeAlbum(image).errCode, -1004)
    }

    func testEveryNativeMethodHasTheDSBridgeSelector() {
        let controller = MWBWebViewController(configuration: .init(
            initialURL: URL(string: "https://example.com")!,
            allowedOrigins: ["https://example.com"]
        ))
        let adapter = MWBBridgeAdapter(controller: controller)
        let synchronous = [
            "setEnableDebug", "getAppInfoSync", "getDeviceInfoSync", "getClipboardDataSync",
            "getNetworkTypeSync", "setStorageSync", "getStorageSync", "removeStorageSync",
            "clearStorageSync"
        ]
        let asynchronous = [
            "toast", "navigateTo", "redirectTo", "navigateBack", "navigateBackToRoot", "openExternalBrowser",
            "setNavigationBarTheme", "cleanWebviewCache", "exitApp", "openNativePage",
            "openAppAuthorizeSetting", "setBadgeCount", "setClipboardData", "makePhoneCall",
            "getNotificationSwitchStatus", "compressImage", "scanCode", "saveImageToPhotosAlbum",
            "chooseImage", "openFile", "checkRequestCameraPermissions",
            "convertImagePathToBase64"
        ]

        for name in synchronous {
            XCTAssertTrue(adapter.responds(to: NSSelectorFromString("\(name):")), name)
        }
        for name in asynchronous {
            XCTAssertTrue(adapter.responds(to: NSSelectorFromString("\(name):handler:")), name)
        }
        // 旧水印接口移除后，原生桥也不应继续响应。
        XCTAssertFalse(adapter.responds(to: NSSelectorFromString("addWaterMark:handler:")))
    }

    func testStorageSeparatesGroupsAndReturnsOriginalValue() {
        let suite = UserDefaults(suiteName: "mwb-test-\(UUID().uuidString)")!
        let storage = MWBStorage(defaults: suite)
        storage.set(key: "token", value: ["id": 1], group: "a", validSeconds: nil)

        XCTAssertNil(storage.get(key: "token", group: "b"))
        XCTAssertEqual((storage.get(key: "token", group: "a") as? [String: Int])?["id"], 1)
        storage.clear(group: "a")
        XCTAssertNil(storage.get(key: "token", group: "a"))
    }

    func testStoragePreservesNullValues() {
        let suite = UserDefaults(suiteName: "mwb-test-\(UUID().uuidString)")!
        let storage = MWBStorage(defaults: suite)
        storage.set(key: "empty", value: NSNull(), group: nil, validSeconds: nil)
        storage.set(key: "nested", value: ["field": NSNull()], group: nil, validSeconds: nil)

        XCTAssertTrue(storage.get(key: "empty", group: nil) is NSNull)
        XCTAssertTrue((storage.get(key: "nested", group: nil) as? [String: Any])?["field"] is NSNull)
    }
}
