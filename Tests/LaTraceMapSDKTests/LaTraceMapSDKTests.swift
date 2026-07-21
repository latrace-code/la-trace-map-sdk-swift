import XCTest
@testable import LaTraceMapSDK

final class LaTraceMapSDKTests: XCTestCase {
    func testVersionIsNotEmpty() {
        XCTAssertFalse(LaTraceMapSDKInfo.version.isEmpty, "SDK version must be a non-empty string")
    }

    func testBasemapRoundTrip() throws {
        for value in Basemap.allCases {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(Basemap.self, from: data)
            XCTAssertEqual(decoded, value)
        }
        // The JSON representation must be the bare string, since the embed
        // compares against string literals.
        let satelliteJSON = String(decoding: try JSONEncoder().encode(Basemap.satellite), as: UTF8.self)
        XCTAssertEqual(satelliteJSON, "\"satellite\"")
    }
}
