import Foundation

/// Kind of place a ``GeoResult`` designates, as classified by the `/geocode`
/// gateway. Also the filter accepted by ``LaTraceGeocoder``.
public enum GeoResultType: String, Codable, CaseIterable, Sendable {
    case city, town, village, district, region, country, address
    /// Stations, airports, monuments, parks, waterways.
    case landmark
    /// Businesses (hotels, shops, restaurants). Opt-in only.
    case poi

    /// What the La Trace web search asks for: places, addresses and
    /// landmarks, no businesses.
    public static let searchDefaults: [GeoResultType] = [
        .city, .town, .village, .district, .region, .country, .address, .landmark,
    ]
}

/// A geocoding hit returned by ``LaTraceGeocoder`` (Photon-backed).
///
/// Kept intentionally small — the partner's own search bar only needs a
/// display label and a coordinate to fly the camera to.
public struct GeoResult: Codable, Equatable, Sendable {
    /// Human-readable label (street, city, POI name…).
    public let label: String
    /// `[lng, lat]` in WGS84.
    public let coords: LngLat
    /// Contextual line under the label (region, country…). In `nl` the
    /// backend returns a raw multilingual string ("Oost-Vlaanderen, Belgie /
    /// Belgique / Belgien"): truncate or hide it rather than display it as-is.
    public let secondary: String?
    /// `nil` when the gateway sends a kind this SDK version does not know.
    public let type: GeoResultType?
    /// `[minLng, minLat, maxLng, maxLat]`, present for areas (city,
    /// district…). Fit the camera to it rather than flying to `coords`.
    public let bbox: [Double]?

    public init(
        label: String,
        coords: LngLat,
        secondary: String? = nil,
        type: GeoResultType? = nil,
        bbox: [Double]? = nil
    ) {
        self.label = label
        self.coords = coords
        self.secondary = secondary
        self.type = type
        self.bbox = bbox
    }
}
