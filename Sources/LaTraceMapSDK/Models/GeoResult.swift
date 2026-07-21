import Foundation

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

    public init(label: String, coords: LngLat, secondary: String? = nil) {
        self.label = label
        self.coords = coords
        self.secondary = secondary
    }
}
