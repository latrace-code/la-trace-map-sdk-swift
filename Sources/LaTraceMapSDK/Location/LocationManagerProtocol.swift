#if canImport(CoreLocation)
import CoreLocation

/// Minimal surface of `CLLocationManager` used by `LaTraceLocationProvider`.
///
/// Extracted as a protocol so the helper can be unit-tested with a fake
/// implementation without having to spin up a real `CLLocationManager`
/// (which is awkward to drive in tests because it talks to the system
/// location daemon and requires running on a real device or the
/// simulator with a custom location).
///
/// `CLLocationManager` is extended below to conform automatically — it
/// already implements every member.
internal protocol LocationManagerProtocol: AnyObject {

    /// Delegate receiving location updates and authorization changes.
    /// `CLLocationManagerDelegate` is the existing AppKit/UIKit-friendly
    /// callback API; iOS 17 introduced async/await alternatives, but the
    /// package targets iOS 15+ so the delegate pattern is still the
    /// portable choice here.
    var delegate: CLLocationManagerDelegate? { get set }

    /// Desired accuracy. Defaults to `kCLLocationAccuracyBest` in the
    /// provider — see `LaTraceLocationProvider.init`.
    var desiredAccuracy: CLLocationAccuracy { get set }

    /// Current authorization status. Available as an instance member
    /// since iOS 14 (replaces the deprecated class method).
    var authorizationStatus: CLAuthorizationStatus { get }

    /// Triggers the "When in use" permission prompt. Idempotent on the
    /// system side: iOS will only show the prompt once per app lifetime.
    func requestWhenInUseAuthorization()

    /// Start continuous location updates.
    func startUpdatingLocation()

    /// Stop continuous location updates.
    func stopUpdatingLocation()

    /// Request a single location fix.
    func requestLocation()
}

extension CLLocationManager: LocationManagerProtocol {
    // `CLLocationManager` already provides every member of
    // `LocationManagerProtocol` with the right signature, so no work is
    // needed here. The empty extension just declares conformance.
}
#endif
