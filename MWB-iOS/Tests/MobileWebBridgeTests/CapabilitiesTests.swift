import XCTest
@testable import MobileWebBridge

final class CapabilitiesTests: XCTestCase {
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
