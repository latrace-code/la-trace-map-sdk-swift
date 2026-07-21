#if canImport(CoreLocation)
import Foundation
import CoreLocation

/// Native geolocation helper that bridges `CLLocationManager` to the map
/// via a closure sink.
///
/// Designed as a **standalone** helper: it has no compile-time dependency
/// on ``LaTraceExploreMap``, so a host that already owns CoreLocation can
/// ignore it. Integrators wire the two together themselves:
///
/// ```swift
/// let provider = LaTraceLocationProvider { lng, lat, accuracy in
///     map.setUserLocation(UserCoords(lng: lng, lat: lat, accuracy: accuracy))
/// }
/// provider.requestPermission()
/// provider.start()
/// ```
///
/// ### Threading
/// `CLLocationManager` must be constructed on the main thread; iOS will
/// emit a runtime warning otherwise. The initializer asserts main-thread
/// usage in debug builds and dispatches to main as a safety net in
/// release. All delegate callbacks from `CLLocationManager` are also
/// delivered on the main thread, so the sink is always invoked on main.
///
/// ### Info.plist
/// The host application **must** declare
/// `NSLocationWhenInUseUsageDescription` in its `Info.plist`. If the key
/// is missing, iOS silently skips the permission prompt and the user
/// will be stuck in `.notDetermined` forever. See
/// `Sources/LaTraceMapSDK/Location/README.md` for the full setup guide.
///
/// ### Accuracy circle
/// The JS-side `setUserLocation` paints a custom marker but does **not**
/// render an accuracy circle today. The `accuracy` value is still
/// forwarded so we can light up the visual the day it ships JS-side
/// without breaking the Swift API.
public final class LaTraceLocationProvider: NSObject {

    // MARK: - Public types

    /// Sink invoked every time a new location is received. Coordinates
    /// are in WGS84 lng / lat order — matches `LngLat` in the rest of
    /// the SDK. Accuracy is in meters; pass through unchanged from
    /// `CLLocation.horizontalAccuracy`. `nil` accuracy means "value was
    /// reported as invalid by CoreLocation" (negative
    /// `horizontalAccuracy`).
    public typealias LocationSink = (Double, Double, Double?) -> Void

    /// Callback invoked when the authorization status changes (initial
    /// permission decision or runtime change such as the user toggling
    /// Settings).
    public typealias AuthorizationHandler = (CLAuthorizationStatus) -> Void

    // MARK: - Public surface

    /// The most recent authorization status. Reads through to the
    /// underlying `CLLocationManager`, so it is always current rather
    /// than a cached snapshot.
    public var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    // MARK: - Private state

    private let manager: LocationManagerProtocol
    private let sink: LocationSink
    private let authorizationHandler: AuthorizationHandler?
    private var state: LocationProviderState = .idle

    // MARK: - Init

    /// Designated initializer.
    ///
    /// - Parameters:
    ///   - sink: closure invoked with `(lng, lat, accuracy?)` on every
    ///     valid location fix.
    ///   - authorizationHandler: optional callback fired when the
    ///     authorization status changes.
    ///   - accuracy: desired accuracy. Default is
    ///     `kCLLocationAccuracyBest`, which is appropriate for a map
    ///     blue-dot use case. Hosts that want lower battery cost can
    ///     pass `kCLLocationAccuracyHundredMeters` or coarser.
    public convenience init(
        sink: @escaping LocationSink,
        authorizationHandler: AuthorizationHandler? = nil,
        accuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    ) {
        // `CLLocationManager` must be created on the main thread. We
        // assert in debug to surface mistakes early, and dispatch in
        // release to avoid hard crashes.
        let manager: CLLocationManager
        if Thread.isMainThread {
            manager = CLLocationManager()
        } else {
            assertionFailure("LaTraceLocationProvider must be initialized on the main thread")
            manager = DispatchQueue.main.sync { CLLocationManager() }
        }
        self.init(
            manager: manager,
            sink: sink,
            authorizationHandler: authorizationHandler,
            accuracy: accuracy
        )
    }

    /// Internal initializer used for tests with a fake location manager.
    /// Production callers should use the public `convenience init`.
    internal init(
        manager: LocationManagerProtocol,
        sink: @escaping LocationSink,
        authorizationHandler: AuthorizationHandler? = nil,
        accuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    ) {
        self.manager = manager
        self.sink = sink
        self.authorizationHandler = authorizationHandler
        super.init()
        self.manager.desiredAccuracy = accuracy
        // `delegate` is `weak` on `CLLocationManager`, so this does not
        // create a retain cycle.
        self.manager.delegate = self
    }

    // MARK: - Lifecycle

    /// Request "When in use" permission.
    ///
    /// Call this from a user gesture (button tap or similar). iOS
    /// requires `NSLocationWhenInUseUsageDescription` in the host app's
    /// `Info.plist` — without it the prompt is silently skipped.
    ///
    /// Idempotent: calling multiple times while already
    /// `requestingPermission` is a no-op. If the status is already
    /// resolved (granted or denied), this call still goes through to
    /// `CLLocationManager` so the system can re-emit the current value
    /// via the delegate.
    public func requestPermission() {
        state = .requestingPermission
        manager.requestWhenInUseAuthorization()
    }

    /// Start receiving continuous location updates.
    ///
    /// Idempotent — calling twice while already active is safe and
    /// does not stack subscriptions. No-op if called before permission
    /// has been granted; in that case the host should call
    /// `requestPermission()` first and react to the
    /// `authorizationHandler` callback.
    public func start() {
        guard state != .active else { return }
        state = .active
        manager.startUpdatingLocation()
    }

    /// Stop receiving updates. Idempotent.
    public func stop() {
        guard state == .active || state == .awaitingOneShot else {
            // Allow transitioning from any "live" state. Reset to
            // `.stopped` so observers can distinguish "never started"
            // (.idle) from "explicitly stopped".
            state = .stopped
            return
        }
        state = .stopped
        manager.stopUpdatingLocation()
    }

    /// One-shot location request. Fires the sink once and stops.
    ///
    /// Uses `requestLocation()` under the hood, which is more
    /// battery-friendly than `startUpdatingLocation()` for a single
    /// fix. If a continuous subscription is already active, this call
    /// is a no-op (the continuous stream will deliver fixes anyway).
    public func requestOnce() {
        guard state != .active else { return }
        state = .awaitingOneShot
        manager.requestLocation()
    }
}

// MARK: - CLLocationManagerDelegate

extension LaTraceLocationProvider: CLLocationManagerDelegate {

    public func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        forwardLatestLocation(from: locations)
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationHandler?(manager.authorizationStatus)
    }

    /// `CLLocationManager` will call this on permission denial, when no
    /// fix is available within the timeout window, or on transient
    /// network errors. We log via `assertionFailure` in debug to make
    /// the failure visible during development; release builds swallow
    /// the error and leave the sink un-invoked — the host should rely on
    /// `authorizationHandler` to detect the denied case.
    public func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        if state == .awaitingOneShot {
            state = .idle
        }
        #if DEBUG
        // Don't `assertionFailure` here: location errors are routine
        // (e.g. user denied, airplane mode). Print for visibility in
        // debug builds without crashing the host app.
        print("LaTraceLocationProvider: location error: \(error)")
        #endif
    }

    // MARK: - Internal — exposed for tests

    /// Forwards the most recent location from `locations` to the sink.
    /// Extracted so unit tests can drive the same code path without
    /// constructing a real `CLLocationManager` delegate call.
    internal func forwardLatestLocation(from locations: [CLLocation]) {
        guard let latest = locations.last else { return }

        let coord = latest.coordinate
        // `horizontalAccuracy < 0` is CoreLocation's convention for
        // "invalid value" — forward as `nil` rather than a bogus
        // negative number so JS-side code can render fallback UI.
        let accuracy: Double? = latest.horizontalAccuracy >= 0
            ? latest.horizontalAccuracy
            : nil

        sink(coord.longitude, coord.latitude, accuracy)

        if state == .awaitingOneShot {
            state = .idle
            manager.stopUpdatingLocation()
        }
    }

    /// Forwards an authorization change to the optional handler.
    /// Extracted for unit tests; production code path is
    /// `locationManagerDidChangeAuthorization(_:)`.
    internal func forwardAuthorizationChange(_ status: CLAuthorizationStatus) {
        authorizationHandler?(status)
    }
}
#endif
