#if canImport(CoreGraphics)
import Foundation
import CoreGraphics
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Server limits mirrored client-side: past them the endpoint answers 400
/// (`invalid_params`) / 413 (`dimensions_too_large`) instead of an image.
public let laTraceStaticMapMaxMarkers = 50
public let laTraceStaticMapMaxDimension = 1280

/// Builds an authenticated request for a static-map thumbnail (a server-rendered
/// PNG) framed on `center`/`zoom`, with the given POIs drawn as La Trace markers.
///
/// - `apiBaseUrl` is the **API gateway** base (the one that also serves
///   `/geocode`), NOT the Explore app base: the Explore host answers its SPA
///   shell on every path.
/// - Auth is the `X-LaTrace-Key` header, like ``LaTraceGeocoder``. A browser
///   `<img>` cannot send a header and must use a backend-signed `?key=`+`sig`
///   URL instead; a native client can, so the key stays out of the URL (and out
///   of proxy logs / URL caches). The key must be provisioned with
///   `allowedOrigins: ["*"]`: with no `Origin` header, an origin-scoped key is
///   refused with 403 `origin_not_allowed`.
/// - `poiColors` is the host's marker palette, the same `[category: PoiColor]`
///   map the interactive map takes via ``ConfigOverride/poiColors``. A POI whose
///   category has no entry falls back to the La Trace colour — colours are keyed
///   by category only, there is no `poiType` key for them.
/// - `poiIcons` is the same `[key: url]` map as ``ConfigOverride/poiIcons``,
///   resolved with the same precedence (`poiType` first, then `category`).
///
/// Returns `nil` when `center` is not a usable `[lng, lat]`.
public func laTraceStaticMapRequest(
    configId: String,
    apiKey: String,
    apiBaseUrl: URL,
    center: LngLat,
    zoom: Double,
    size: CGSize,
    scale: Int = 2,
    pois: [Poi],
    poiColors: [String: ConfigOverride.PoiColor] = [:],
    poiIcons: [String: String] = [:]
) -> URLRequest? {
    guard center.count == 2, center[0].isFinite, center[1].isFinite else { return nil }

    let base = apiBaseUrl.appendingPathComponent("static-map")
    var components = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()

    var items = [
        URLQueryItem(name: "configId", value: configId),
        URLQueryItem(name: "center", value: "\(center[0]),\(center[1])"),
        URLQueryItem(name: "zoom", value: String(zoom)),
        URLQueryItem(name: "width", value: String(staticMapDimension(size.width))),
        URLQueryItem(name: "height", value: String(staticMapDimension(size.height))),
        URLQueryItem(name: "scale", value: scale == 2 ? "2" : "1")
    ]
    let markers = pois
        .compactMap { staticMapMarker($0, poiColors: poiColors, poiIcons: poiIcons) }
        .prefix(laTraceStaticMapMaxMarkers)
    if !markers.isEmpty {
        items.append(URLQueryItem(name: "markers", value: markers.joined(separator: ";")))
    }
    components.queryItems = items

    guard let url = components.url else { return nil }
    var request = URLRequest(url: url)
    request.setValue(apiKey, forHTTPHeaderField: "X-LaTrace-Key")
    return request
}

/// One `markers` entry: `lng,lat[,type[,color[,icon]]]`, positional: an absent
/// field in the middle stays as an empty slot so the later ones keep their rank.
private func staticMapMarker(
    _ poi: Poi,
    poiColors: [String: ConfigOverride.PoiColor],
    poiIcons: [String: String]
) -> String? {
    guard poi.coords.count == 2, poi.coords[0].isFinite, poi.coords[1].isFinite else { return nil }
    // `color` = `body-disc`: the drop (= PoiColor.text, the colour read at a
    // distance) then the puck under the glyph (= PoiColor.background). Bare hex,
    // no `#`: it would have to travel percent-encoded.
    let color = poiColors[poi.category].map { "\(bareHex($0.text))-\(bareHex($0.background))" } ?? ""
    // Same precedence as the interactive map (`poiType` then `category`): a type
    // key is the only way to tell two types of one category apart, and resolving
    // by category alone left the thumbnail on the La Trace glyph while the map
    // showed the host's logo. Each candidate is filtered on its own, so an
    // unusable type icon still falls back to the category one.
    let icon = staticMapIcon(poi.poiType.flatMap { poiIcons[$0] })
        ?? staticMapIcon(poiIcons[poi.category])
        ?? ""
    var fields = ["\(poi.coords[0])", "\(poi.coords[1])", poi.poiType ?? "", color, icon]
    while let last = fields.last, last.isEmpty { fields.removeLast() }
    return fields.joined(separator: ",")
}

/// The server only fetches `https` icons, and `;` is the entry separator, so a
/// host icon that is a data URI (or carries a `;`) is dropped rather than sent:
/// the marker then falls back to the La Trace glyph instead of breaking the list.
private func staticMapIcon(_ url: String?) -> String? {
    guard let url, url.hasPrefix("https://"), !url.contains(";") else { return nil }
    return url
}

private func bareHex(_ value: String) -> String {
    value.hasPrefix("#") ? String(value.dropFirst()) : value
}

private func staticMapDimension(_ points: CGFloat) -> Int {
    min(max(Int(points.rounded()), 1), laTraceStaticMapMaxDimension)
}
#endif
