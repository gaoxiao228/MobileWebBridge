import XCTest
@testable import MobileWebBridge

final class HostTests: XCTestCase {
    func testUnregisteredNativePageReturnsHostError() {
        let controller = MWBWebViewController(configuration: .init(
            initialURL: URL(string: "https://example.com")!,
            allowedOrigins: ["https://example.com"]
        ))
        let adapter = MWBBridgeAdapter(controller: controller)
        var payload = ""

        adapter.openNativePage(["pageName": "Unregistered"]) { response, _ in payload = response }

        XCTAssertEqual(MWBResult.parse(payload)?.errCode, -1005)
    }
}
