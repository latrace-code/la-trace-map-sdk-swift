import Foundation

/// A geographic coordinate pair encoded as `[longitude, latitude]` to match
/// the GeoJSON convention used throughout the underlying LaTrace JS SDK.
///
/// Encoded as a JSON array of two numbers so the on-the-wire representation
/// is identical to `[number, number]` in TypeScript.
public typealias LngLat = [Double]
