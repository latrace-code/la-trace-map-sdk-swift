import Foundation

/// A bounding box encoded as `[west, south, east, north]` (WGS84),
/// matching the `bbox: [w, s, e, n]` tuple in the wire contract.
public typealias BBox = [Double]

/// A read-only camera / viewport snapshot emitted by `viewport:change`.
///
/// Mirrors the wire contract
/// `Viewport = { center: [lng, lat]; zoom: number; bbox: [w, s, e, n] }`.
public struct Viewport: Codable, Equatable, Sendable {
    public let center: LngLat
    public let zoom: Double
    public let bbox: BBox

    public init(center: LngLat, zoom: Double, bbox: BBox) {
        self.center = center
        self.zoom = zoom
        self.bbox = bbox
    }
}

/// Native geolocation coordinates fed to the map (source: CoreLocation,
/// **not** the browser geolocation). Mirrors the wire contract
/// `{ lng, lat, accuracy? }`.
public struct UserCoords: Codable, Equatable, Sendable {
    public let lng: Double
    public let lat: Double
    public let accuracy: Double?

    public init(lng: Double, lat: Double, accuracy: Double? = nil) {
        self.lng = lng
        self.lat = lat
        self.accuracy = accuracy
    }
}

/// A camera destination for `flyTo` / `setCenter`.
///
/// Only `center` is required; the rest fall back to the current camera
/// state on the embed side.
public struct CameraTarget: Equatable, Sendable {
    public var center: LngLat
    public var zoom: Double?
    public var pitch: Double?
    public var bearing: Double?

    public init(
        center: LngLat,
        zoom: Double? = nil,
        pitch: Double? = nil,
        bearing: Double? = nil
    ) {
        self.center = center
        self.zoom = zoom
        self.pitch = pitch
        self.bearing = bearing
    }
}

/// Animation options for a camera move.
public struct CameraOptions: Equatable, Sendable {
    public var durationMs: Int?

    public init(durationMs: Int? = nil) {
        self.durationMs = durationMs
    }
}

/// Edge padding applied when fitting a bounding box. Use ``init(uniform:)``
/// for an equal inset on all sides.
///
/// A side left `nil` is sent as `0`, it does **not** fall back to the embed's
/// own padding: passing `Padding(bottom: 200)` to clear a bottom sheet also
/// drops the top / left / right inset to zero. To keep the embed default, pass
/// no padding at all; to keep it on some sides only, spell the four out.
///
/// Serialised as the object form `{ top, right, bottom, left }` accepted
/// by the wire contract's `padding?: number | { … }`.
public struct Padding: Codable, Equatable, Sendable {
    public var top: Double?
    public var right: Double?
    public var bottom: Double?
    public var left: Double?

    public init(
        top: Double? = nil,
        right: Double? = nil,
        bottom: Double? = nil,
        left: Double? = nil
    ) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    public init(uniform value: Double) {
        self.top = value
        self.right = value
        self.bottom = value
        self.left = value
    }
}
