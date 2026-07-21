import Foundation
import Combine

/// A decoded inbound bridge frame handed up from the transport layer.
///
/// This is the element type of the bridge's `eventsPublisher` at the
/// **single seam** between chantier 3 (this surface) and chantier 2 (the
/// `Bridge/*` transport). The transport deserialises the wire
/// `BridgeEnvelope` and forwards `(name, payload)`; interpreting the
/// payload into a public ``LaTraceExploreEvent`` is done here, above the
/// publisher (the "fan-out" the frontier contract keeps on this side).
///
/// - `name`: the envelope `name`, e.g. `"pin:click"`, `"viewport:change"`,
///   `"ready"`.
/// - `payload`: the raw JSON bytes of the envelope `payload` (or `nil`
///   for payload-less frames such as `ready`).
public struct InboundEnvelope: Equatable, Sendable {
    public let name: String
    public let payload: Data?

    public init(name: String, payload: Data?) {
        self.name = name
        self.payload = payload
    }
}

/// The reduced transport surface this SDK consumes from the `Bridge/*`
/// layer (chantier 2). Declaring it as a protocol keeps the controller
/// unit-testable with a mock and pins the frozen seam:
///
/// - `call(name:payload:)` — host → embed (`kind: 'cmd'`). `payload` is the
///   pre-serialised JSON of the command payload (or `nil` for payload-less
///   commands such as `pois:clear`).
/// - `eventsPublisher` — embed → host (`kind: 'evt'`), as ``InboundEnvelope``.
///
/// The concrete `LaTraceMapBridge` (chantier 2) conforms via the seam file
/// `Views/LaTraceMapBridge+ExploreBridging.swift`.
public protocol ExploreBridging: AnyObject {
    func call(name: String, payload: Data?)
    var eventsPublisher: AnyPublisher<InboundEnvelope, Never> { get }
}

/// Wire command names (`kind: 'cmd'`) — verbatim from the frozen contract
/// (map-sdk/src/explore/LaTraceExplore.ts).
internal enum ExploreCommand {
    static let poisSet = "pois:set"
    static let poisAdd = "pois:add"
    static let poisClear = "pois:clear"
    static let cameraFlyTo = "camera:flyTo"
    static let cameraFitBounds = "camera:fitBounds"
    static let configOverride = "config:override"
    /// Locale switch. Distinct from `config:override`, which only stores the
    /// value: this one also re-translates the chrome and re-resolves the
    /// LocalizedStrings of the pushed corpus.
    static let configSetLocale = "config:setLocale"
    static let geoSetUserLocation = "geo:setUserLocation"
    /// Visual selection only. Wire name aligned with appCore
    /// (`poi:highlight`) — see `LaTraceExploreMap.highlightPin`.
    static let pinHighlight = "poi:highlight"
    static let basemapSet = "basemap:set"
    static let activateMap = "activateMap"
    static let analyticsMapOpened = "analytics:mapOpened"
    static let analyticsFlush = "analytics:flush"
}

/// Wire event names (`kind: 'evt'`) — verbatim from the frozen contract
/// (wire-types.ts ExploreEvents).
internal enum ExploreEventName {
    static let ready = "ready"
    static let pinClick = "pin:click"
    static let viewportChange = "viewport:change"
    static let searchArea = "search:area"
    static let externalOpen = "external:open"
    static let basemapChange = "basemap:change"
    static let poisRejected = "pois:rejected"
    static let error = "error"
}
