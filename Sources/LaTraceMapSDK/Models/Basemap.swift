import Foundation

/// Identifies one of the basemap styles bundled with the LaTrace JS SDK.
///
/// The string values must match the ones the JS layer compares against — at
/// the time of writing the bundled `index.js` only references `plan`,
/// `satellite` and `topo`. The default when no basemap is provided is
/// `plan`.
public enum Basemap: String, Codable, CaseIterable, Sendable {
    case plan
    case satellite
    case topo
}
