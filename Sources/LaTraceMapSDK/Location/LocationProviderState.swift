#if canImport(CoreLocation)
import CoreLocation

/// Internal state machine for `LaTraceLocationProvider`.
///
/// Kept separate from the provider so the lifecycle transitions are easy
/// to reason about and unit-test in isolation. The provider mutates this
/// value on the main thread only; it is **not** thread-safe by itself.
internal enum LocationProviderState: Equatable {

    /// Initial state. No subscription to location updates, no pending
    /// permission request.
    case idle

    /// `requestPermission()` has been invoked and we are waiting for the
    /// user / system to resolve the authorization prompt.
    case requestingPermission

    /// Continuous updates are active (`startUpdatingLocation` has been
    /// called and not yet balanced by `stop`).
    case active

    /// `requestOnce()` is in flight. The provider will transition back
    /// to `.idle` after the next successful fix or error.
    case awaitingOneShot

    /// The provider has been stopped explicitly. Distinct from `.idle`
    /// so observers can tell "never started" from "explicitly stopped".
    case stopped
}
#endif
