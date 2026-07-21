import Foundation

/// The events the Explore embed forwards over the bridge (`kind: 'evt'`), as
/// a strongly-typed enum. The contract carries more of them; this surface
/// decodes the subset a piloted map needs — the UI ones (panel, search,
/// filters, gallery) belong to hosts that let the embed render its chrome.
///
/// - ``pinClick(poi:)`` → host opens its own native popup + tracks the view.
/// - ``viewportChange(_:)`` → the map moved / settled (there is **no**
///   distinct `map:idle`; `viewport:change` is the only movement signal).
/// - ``searchArea(bbox:)`` → host runs its "search this area" query and
///   re-pushes the corpus.
/// - ``externalOpen(poiId:url:)`` → outbound-link tracking.
/// - ``basemapChange(_:)`` → the basemap moved (host command **or** the
///   map's own default at boot); the host realigns its selector.
/// - ``poisRejected(_:)`` → POIs the embed refused after a push; without it
///   a corpus loses entries with no trace host-side.
public enum LaTraceExploreEvent: Equatable, Sendable {
    case ready
    case pinClick(poi: Poi)
    case viewportChange(Viewport)
    case searchArea(bbox: BBox)
    case externalOpen(poiId: String, url: String)
    case basemapChange(Basemap)
    case poisRejected([EmbedReject])
    case error(code: String, message: String)

    // MARK: - Wire mapping

    /// Decode an event from an inbound bridge frame. Returns `nil` when the
    /// name is unknown or the payload cannot be decoded, so the caller can
    /// drop the frame without crashing.
    internal init?(envelope: InboundEnvelope) {
        let decoder = JSONDecoder()
        let data = envelope.payload ?? Data("{}".utf8)

        switch envelope.name {
        case ExploreEventName.ready:
            self = .ready

        case ExploreEventName.pinClick:
            guard let wrapper = try? decoder.decode(PinClickPayload.self, from: data) else { return nil }
            self = .pinClick(poi: wrapper.poi)

        case ExploreEventName.viewportChange:
            guard let viewport = try? decoder.decode(Viewport.self, from: data) else { return nil }
            self = .viewportChange(viewport)

        case ExploreEventName.searchArea:
            guard let wrapper = try? decoder.decode(SearchAreaPayload.self, from: data) else { return nil }
            self = .searchArea(bbox: wrapper.bbox)

        case ExploreEventName.externalOpen:
            guard let wrapper = try? decoder.decode(ExternalOpenPayload.self, from: data) else { return nil }
            self = .externalOpen(poiId: wrapper.poiId, url: wrapper.url)

        case ExploreEventName.basemapChange:
            guard let wrapper = try? decoder.decode(BasemapChangePayload.self, from: data) else { return nil }
            self = .basemapChange(wrapper.basemap)

        case ExploreEventName.poisRejected:
            guard let wrapper = try? decoder.decode(PoisRejectedPayload.self, from: data) else { return nil }
            self = .poisRejected(wrapper.rejected)

        case ExploreEventName.error:
            guard let wrapper = try? decoder.decode(ErrorPayload.self, from: data) else { return nil }
            self = .error(code: wrapper.code, message: wrapper.message)

        default:
            return nil
        }
    }

    // MARK: - Payload shapes

    private struct PinClickPayload: Decodable { let poi: Poi }
    private struct SearchAreaPayload: Decodable { let bbox: BBox }
    private struct ExternalOpenPayload: Decodable { let poiId: String; let url: String }
    private struct BasemapChangePayload: Decodable { let basemap: Basemap }
    private struct PoisRejectedPayload: Decodable { let rejected: [EmbedReject] }
    private struct ErrorPayload: Decodable { let code: String; let message: String }
}

/// One POI the embed refused after a push, with the wire reason verbatim
/// (`missing_id`, `duplicate_id`, `invalid_coords`, `invalid_field`,
/// `unknown_category`). Kept as a raw string so a new server-side reason
/// reaches the host instead of failing to decode.
public struct EmbedReject: Codable, Equatable, Sendable {
    public let id: String?
    public let reason: String

    public init(id: String?, reason: String) {
        self.id = id
        self.reason = reason
    }
}
