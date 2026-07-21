import Foundation

/// Bootstrap options for the Explore map surface.
///
/// The map loads `{exploreBaseUrl}/explore?sdkBridge=1&ui=bare&transport=native&customConfigId=…&apiKey=…`
/// (see ``exploreEmbedURL(options:)``). `initial*` values are queued as
/// commands and applied as soon as the embed reports `ready`.
public struct LaTraceExploreOptions: Equatable, Sendable {

    /// Dedicated native key (`pk_live_*`). The barrier is key + quota
    /// (embedder Origin is not reliable natively), so the key must be
    /// provisioned with `allowedOrigins: ["*"]`: a native client sends no
    /// `Origin`, and an origin-scoped key is refused (403 `origin_not_allowed`)
    /// on ``LaTraceGeocoder`` and ``laTraceStaticMapRequest(configId:apiKey:apiBaseUrl:center:zoom:size:scale:pois:poiColors:poiIcons:)``.
    public var apiKey: String

    /// Base config id + stats key (session / clientMap id).
    public var configId: String

    /// Explore host serving the embed (front app). Required and never
    /// defaulted: the native transport ships with the web deploy, so the
    /// environment that supports it is a deployment fact, not a constant this
    /// package can guess. La Trace hands the URL over with the key and the
    /// config id.
    public var exploreBaseUrl: URL

    public var initialConfig: ConfigOverride?
    public var initialPois: [Poi]?
    public var initialView: CameraTarget?
    public var locale: Locale?

    /// Warm-reuse the embed while the map is still off-screen (the map is
    /// rarely the first screen). The host must keep the view mounted but
    /// hidden (sized, never `display:none`), then call
    /// ``LaTraceExploreMap/activateMap(initialBBox:)`` when the map screen
    /// appears — the embed boots but stays hidden until then.
    public var prewarm: Bool

    public init(
        apiKey: String,
        configId: String,
        exploreBaseUrl: URL,
        initialConfig: ConfigOverride? = nil,
        initialPois: [Poi]? = nil,
        initialView: CameraTarget? = nil,
        locale: Locale? = nil,
        prewarm: Bool = false
    ) {
        self.apiKey = apiKey
        self.configId = configId
        self.exploreBaseUrl = exploreBaseUrl
        self.initialConfig = initialConfig
        self.initialPois = initialPois
        self.initialView = initialView
        self.locale = locale
        self.prewarm = prewarm
    }
}

/// Builds the top-level URL the WKWebView loads for the piloted, bare map.
///
/// Flags are frozen by CONTRAT 4:
/// `sdkBridge=1` (pont), `ui=bare` (map only), `transport=native`
/// (postMessage → `window.webkit.messageHandlers.lt`).
///
/// The config id travels as `customConfigId`: it is the only name the front
/// reads besides `exploreMapId`, and it is what the web SDK already writes.
/// A `configId=` param is silently ignored, which resolves the default map.
public func exploreEmbedURL(options: LaTraceExploreOptions) -> URL {
    var base = options.exploreBaseUrl
    // A base URL already ending in /explore (common config mistake) would
    // otherwise yield /explore/explore → Angular NotFoundPage. Strip it first.
    if base.lastPathComponent == "explore" {
        base.deleteLastPathComponent()
    }
    var components = URLComponents(
        url: base.appendingPathComponent("explore"),
        resolvingAgainstBaseURL: false
    ) ?? URLComponents()

    var items = [
        URLQueryItem(name: "sdkBridge", value: "1"),
        URLQueryItem(name: "ui", value: "bare"),
        URLQueryItem(name: "transport", value: "native"),
        URLQueryItem(name: "customConfigId", value: options.configId),
        URLQueryItem(name: "apiKey", value: options.apiKey)
    ]
    if let locale = options.locale {
        items.append(URLQueryItem(name: "locale", value: locale.rawValue))
    }
    if options.prewarm {
        items.append(URLQueryItem(name: "prewarm", value: "1"))
    }
    // Preserve any query already present on a custom base URL.
    components.queryItems = (components.queryItems ?? []) + items

    return components.url ?? base
}
