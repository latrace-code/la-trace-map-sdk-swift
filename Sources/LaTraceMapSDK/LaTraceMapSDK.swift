import Foundation

/// Namespace for the La Trace Map SDK.
///
/// This package embeds the La Trace Explore map in a WKWebView and exposes a
/// UIKit/SwiftUI surface to pilot it (``LaTraceExploreMapView``,
/// ``LaTraceExploreMap``), plus two REST helpers outside the bridge
/// (``LaTraceGeocoder``, `laTraceStaticMapRequest`).
public enum LaTraceMapSDKInfo {
    /// The current SDK version. It also pins the revision of the SDK API
    /// contract this package implements. Bumped by `scripts/release.sh`.
    public static let version = "0.0.1"
}
