import XCTest
@testable import MobileWebBridge

final class BridgeTests: XCTestCase {
    func testResultSerializesSuccessAndErrorCodes() {
        XCTAssertEqual(MWBResult.success(["value": 1]).dictionary["errCode"] as? Int, 0)
        XCTAssertEqual(MWBResult.failure(-1005, "not configured").dictionary["errCode"] as? Int, -1005)
    }

    func testExitAppReturnsUnsupportedWithoutTerminatingProcess() {
        let controller = MWBWebViewController(configuration: .init(
            initialURL: URL(string: "https://example.com")!,
            allowedOrigins: ["https://example.com"]
        ))
        let adapter = MWBBridgeAdapter(controller: controller)
        var payload = ""

        adapter.exitApp(nil) { response, _ in payload = response }

        XCTAssertEqual(MWBResult.parse(payload)?.errCode, -1004)
    }
}
