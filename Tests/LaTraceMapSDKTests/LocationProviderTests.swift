#if canImport(CoreLocation)
import XCTest
import CoreLocation
@testable import LaTraceMapSDK

/// Tests for `LaTraceLocationProvider`.
///
/// The provider is driven through a fake `LocationManagerProtocol` so
/// the tests don't depend on real device hardware or simulator
/// permission state.
final class LocationProviderTests: XCTestCase {

    // MARK: - Fakes

    final class FakeLocationManager: LocationManagerProtocol {
        weak var delegate: CLLocationManagerDelegate?
        var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
        var authorizationStatus: CLAuthorizationStatus = .notDetermined

        var didRequestWhenInUseAuthorization = false
        var didStartUpdating = false
        var didStopUpdating = false
        var didRequestSingleLocation = false

        func requestWhenInUseAuthorization() {
            didRequestWhenInUseAuthorization = true
        }
        func startUpdatingLocation() {
            didStartUpdating = true
        }
        func stopUpdatingLocation() {
            didStopUpdating = true
        }
        func requestLocation() {
            didRequestSingleLocation = true
        }
    }

    // MARK: - Tests

    /// Constructing the provider must not start any updates; the host
    /// has to opt in explicitly via `start()` / `requestOnce()`.
    func testInitDoesNotStartUpdates() {
        let manager = FakeLocationManager()
        _ = LaTraceLocationProvider(
            manager: manager,
            sink: { _, _, _ in XCTFail("Sink must not fire before start()") }
        )

        XCTAssertFalse(manager.didStartUpdating)
        XCTAssertFalse(manager.didRequestSingleLocation)
        XCTAssertFalse(manager.didRequestWhenInUseAuthorization)
    }

    /// Driving a fake `didUpdateLocations` through the provider must
    /// forward the latest coordinate (lng, lat, accuracy) to the sink.
    func testSinkReceivesInjectedLocation() {
        let manager = FakeLocationManager()
        let expectation = self.expectation(description: "sink invoked")
        // The sink fires again for the second (invalid-accuracy) fix below,
        // after the wait has already resolved on the first fix.
        expectation.assertForOverFulfill = false

        var receivedLng: Double?
        var receivedLat: Double?
        var receivedAccuracy: Double?

        let provider = LaTraceLocationProvider(
            manager: manager,
            sink: { lng, lat, accuracy in
                receivedLng = lng
                receivedLat = lat
                receivedAccuracy = accuracy
                expectation.fulfill()
            }
        )

        // Use the internal forwarder so we don't need to construct a
        // real `CLLocationManager` argument for the delegate method.
        let fix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),
            altitude: 35,
            horizontalAccuracy: 12,
            verticalAccuracy: 5,
            timestamp: Date()
        )
        provider.forwardLatestLocation(from: [fix])

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedLng ?? .nan, 2.3522, accuracy: 0.0001)
        XCTAssertEqual(receivedLat ?? .nan, 48.8566, accuracy: 0.0001)
        XCTAssertEqual(receivedAccuracy ?? .nan, 12, accuracy: 0.0001)

        // A second fix with an invalid horizontal accuracy should
        // surface as `nil` accuracy rather than a negative number.
        let invalid = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            altitude: 0,
            horizontalAccuracy: -1,
            verticalAccuracy: 0,
            timestamp: Date()
        )
        provider.forwardLatestLocation(from: [invalid])
        XCTAssertNil(receivedAccuracy, "Invalid horizontalAccuracy must be reported as nil")
    }

    /// The optional `authorizationHandler` must be invoked when
    /// `CLLocationManager` reports an authorization change.
    func testAuthorizationHandlerCalledOnChange() {
        let manager = FakeLocationManager()
        let expectation = self.expectation(description: "auth handler invoked")
        var receivedStatus: CLAuthorizationStatus?

        let provider = LaTraceLocationProvider(
            manager: manager,
            sink: { _, _, _ in },
            authorizationHandler: { status in
                receivedStatus = status
                expectation.fulfill()
            }
        )

        // Drive the change through the internal forwarder. In production
        // the entry point is `locationManagerDidChangeAuthorization(_:)`,
        // which requires a real `CLLocationManager` argument we don't
        // want to construct here.
        // `.authorizedWhenInUse` is iOS-only; on the macOS test host we use
        // the equivalent always-authorized status so the suite compiles and
        // runs on both platforms.
        #if os(iOS)
        let expectedStatus: CLAuthorizationStatus = .authorizedWhenInUse
        #else
        let expectedStatus: CLAuthorizationStatus = .authorizedAlways
        #endif
        provider.forwardAuthorizationChange(expectedStatus)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedStatus, expectedStatus)
    }
}
#endif
