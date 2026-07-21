#if canImport(UIKit)
import UIKit

/// Cosmetic configuration applied to the native chrome wrapping the
/// LaTrace WKWebView. Intentionally minimal: it covers the bits that an
/// integrator has to set to avoid the white flash on launch and to keep
/// the loading state on-brand. Everything map-related (basemap, markers,
/// colours) belongs on ``LaTraceExploreOptions`` and the
/// ``LaTraceExploreMap`` controller, not here.
public struct LaTraceMapViewTheme {

    /// Background color shown behind the WKWebView before the map first
    /// paints. Choose a color that matches your app's chrome to avoid the
    /// white flash on launch. Default: `.systemBackground`.
    public var backgroundColor: UIColor

    /// Show a native `UIActivityIndicatorView` centered over the map
    /// until the `ready` event fires. Useful on slow networks where the
    /// JS bundle and tiles take a moment to load.
    public var showsLoadingSpinner: Bool

    /// Spinner color. When `nil`, the spinner uses the system default
    /// (which adapts to dark/light mode against
    /// ``backgroundColor``).
    public var spinnerColor: UIColor?

    public init(
        backgroundColor: UIColor = .systemBackground,
        showsLoadingSpinner: Bool = true,
        spinnerColor: UIColor? = nil
    ) {
        self.backgroundColor = backgroundColor
        self.showsLoadingSpinner = showsLoadingSpinner
        self.spinnerColor = spinnerColor
    }

    /// Convenience zero-argument theme matching the SDK defaults.
    public static var `default`: LaTraceMapViewTheme { LaTraceMapViewTheme() }
}
#endif
