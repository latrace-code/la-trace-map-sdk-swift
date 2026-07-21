import Foundation
import Combine

/// Pilotable controller for the Explore map — a reduced, UIKit-first
/// mirror of the JS `LaTraceExplore` (`kind: 'cmd'`).
///
/// Deliberately excludes any UI-opening surface (no `openPoi` / panel /
/// search / filters) — the fiche and chrome live in the host app. This
/// controller only pushes the corpus, moves the camera, overrides config,
/// feeds native geolocation and drives visual pin selection.
///
/// Obtain an instance from ``LaTraceExploreMapView/map``; observe events
/// via ``eventsPublisher`` (or the sugar in `LaTraceExploreMap+Events`).
public final class LaTraceExploreMap {

    // MARK: - Events

    /// Every ``LaTraceExploreEvent`` forwarded by the embed, decoded from
    /// the bridge's inbound envelopes. Deliver on the main thread on the
    /// consumer side (`.receive(on: .main)`).
    public let eventsPublisher: AnyPublisher<LaTraceExploreEvent, Never>

    // MARK: - Optimistic state

    /// The currently highlighted pin id (optimistic — set the instant
    /// ``highlightPin(_:)`` is called, before the embed confirms).
    public private(set) var highlightedPin: String?

    /// The current basemap. Set optimistically by ``setBasemap(_:)`` and
    /// realigned on every `basemap:change`, including the one the embed emits
    /// at boot for the partner's own default (which is not necessarily `plan`).
    public private(set) var basemap: Basemap = .plan

    // MARK: - Internals

    private let bridge: ExploreBridging
    private var basemapSync: AnyCancellable?
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    /// Designated initializer. The view builds the concrete bridge and
    /// hands it in; tests inject a mock conforming to ``ExploreBridging``.
    internal init(bridge: ExploreBridging) {
        self.bridge = bridge
        self.eventsPublisher = bridge.eventsPublisher
            .compactMap { LaTraceExploreEvent(envelope: $0) }
            .eraseToAnyPublisher()
        // Subscribed here, not folded into the publisher above: an effect in
        // the shared `compactMap` would run once per subscriber and never at
        // all for a host that only reads ``basemap``.
        basemapSync = eventsPublisher.sink { [weak self] event in
            if case .basemapChange(let basemap) = event { self?.basemap = basemap }
        }
    }

    // MARK: - POIs

    /// Replace the whole corpus. Invalid POIs (empty id / non-finite
    /// coords) are rejected client-side and reported in the result.
    ///
    /// The embed applies its own validation on top and reports what it
    /// refused through ``LaTraceExploreEvent/poisRejected(_:)``.
    @discardableResult
    public func setPois(_ pois: [Poi]) -> PushResult {
        let (accepted, rejected) = Self.partition(pois)
        return Self.result(accepted, rejected, sent: send(ExploreCommand.poisSet, PoisPayload(pois: accepted)))
    }

    /// Merge POIs into the corpus. Same client-side validation as
    /// ``setPois(_:)``. No frame is sent when nothing survives validation.
    @discardableResult
    public func addPois(_ pois: [Poi]) -> PushResult {
        let (accepted, rejected) = Self.partition(pois)
        guard !accepted.isEmpty else { return PushResult(accepted: 0, rejected: rejected) }
        return Self.result(accepted, rejected, sent: send(ExploreCommand.poisAdd, PoisPayload(pois: accepted)))
    }

    /// Clear the whole corpus (`pois:clear`, no payload).
    public func clearPois() {
        bridge.call(name: ExploreCommand.poisClear, payload: nil)
    }

    // MARK: - Camera

    /// Animate the camera to a target. A non-finite `center` drops the
    /// command; a non-finite `zoom` / `pitch` / `bearing` is omitted and the
    /// embed keeps the current value.
    public func flyTo(_ target: CameraTarget, options: CameraOptions? = nil) {
        guard Self.isUsable(target.center) else {
            Self.dropped("camera:flyTo", "center is not a finite [lng, lat] pair")
            return
        }
        send(ExploreCommand.cameraFlyTo, FlyToPayload(
            center: target.center,
            zoom: Self.finite(target.zoom),
            pitch: Self.finite(target.pitch),
            bearing: Self.finite(target.bearing),
            durationMs: options?.durationMs
        ))
    }

    /// Fit the camera to a bounding box.
    ///
    /// A `padding` side left `nil` is sent as `0`, it does **not** fall back
    /// to the embed's own padding: pass no padding at all to keep that one,
    /// or spell out the four sides.
    public func fitBounds(_ bbox: BBox, padding: Padding? = nil) {
        guard bbox.count == 4, bbox.allSatisfy({ $0.isFinite }) else {
            Self.dropped("camera:fitBounds", "bbox is not four finite values")
            return
        }
        send(ExploreCommand.cameraFitBounds, FitBoundsPayload(bbox: bbox, padding: padding))
    }

    /// Recenter without animation. Implemented as an instant
    /// `camera:flyTo` (`durationMs: 0`) so there is a single camera path to
    /// maintain.
    public func setCenter(_ center: LngLat) {
        flyTo(CameraTarget(center: center), options: CameraOptions(durationMs: 0))
    }

    // MARK: - Config

    /// Apply a live config override (poiColors / poiIcons / declutter /
    /// mapNav / poiDetailMode). Partial — only the provided keys move. The
    /// chrome preset is NOT part of it: the embed resolves `ui` once at boot
    /// from the URL, so a live override of it would be silently dropped.
    /// Switch
    /// language with ``setLocale(_:)``, not with the `locale` key here: an
    /// override stores the value without re-translating anything.
    public func setConfigOverride(_ config: ConfigOverride) {
        send(ExploreCommand.configOverride, ConfigPayload(config: config))
    }

    /// Switch the active locale: the embed's own chrome and every
    /// `LocalizedString` of the pushed corpus (names, descriptions, editorial
    /// tabs) are re-resolved in that language.
    ///
    /// Goes through `config:setLocale`, not `config:override`: the latter only
    /// stores the value, leaving the corpus and the chrome in the previous
    /// language.
    public func setLocale(_ locale: Locale) {
        send(ExploreCommand.configSetLocale, LocalePayload(locale: locale))
    }

    // MARK: - Native geolocation

    /// Feed native (CoreLocation) coordinates to the map, or `nil` to clear
    /// the blue dot. This is **not** the browser geolocation.
    public func setUserLocation(_ coords: UserCoords?) {
        if let coords, !(coords.lng.isFinite && coords.lat.isFinite) {
            Self.dropped("geo:setUserLocation", "coords are not finite")
            return
        }
        send(ExploreCommand.geoSetUserLocation, SetUserLocationPayload(coords: coords))
    }

    // MARK: - Selection (visual only)

    /// Highlight a pin (or clear with `nil`). Visual selection only — it
    /// does **not** open a panel; the fiche is the host's responsibility.
    ///
    /// Emitted optimistically as `poi:highlight` (the wire name appCore
    /// routes); `highlightedPin` updates instantly, before the embed renders
    /// the selection.
    public func highlightPin(_ poiId: String?) {
        highlightedPin = poiId
        send(ExploreCommand.pinHighlight, HighlightPayload(poiId: poiId))
    }

    // MARK: - Basemap

    /// Switch the basemap. The host keeps its own selector chrome; observe
    /// ``LaTraceExploreEvent/basemapChange(_:)`` to stay in sync when the
    /// basemap moves on its own (the map's default at boot).
    public func setBasemap(_ basemap: Basemap) {
        self.basemap = basemap
        send(ExploreCommand.basemapSet, BasemapPayload(basemap: basemap))
    }

    // MARK: - Activation / analytics

    /// Reveal a pre-warmed embed (``LaTraceExploreOptions/prewarm``): the
    /// real style loads here, never before, and this open is counted. Pass
    /// the bbox of the corpus about to be shown so the map opens already
    /// framed on it, without a visible camera move. No-op if not pre-warmed.
    public func activateMap(initialBBox: BBox? = nil) {
        // A pre-warmed embed only reveals itself on this command: an unusable
        // bbox must degrade to "activate without framing", never to "never
        // activate" (a hidden map for good, and no open counted).
        if let initialBBox, initialBBox.count == 4, initialBBox.allSatisfy({ $0.isFinite }) {
            send(ExploreCommand.activateMap, ActivateMapPayload(initialView: InitialView(bbox: initialBBox)))
        } else {
            if initialBBox != nil { Self.dropped("activateMap initialBBox", "bbox is not four finite values") }
            bridge.call(name: ExploreCommand.activateMap, payload: nil)
        }
    }

    /// Count one more map opening on a **reused** embed: call it when the host
    /// shows the map again without recreating the view, typically when the user
    /// comes back to the map tab from another tab.
    ///
    /// Stays a manual gesture on purpose. Only the host knows what "the map was
    /// opened again" means inside its own navigation, so the SDK never fires
    /// this by itself, unlike ``flushAnalytics()`` which the view wires to the
    /// app lifecycle.
    ///
    /// Call it on **re-openings only**. The very first appearance is already
    /// counted by the embed: at boot for a normal embed, at
    /// ``activateMap(initialBBox:)`` for a pre-warmed one. Calling it there too
    /// counts that opening twice. Same rule right after ``LaTraceExploreMapView/onReloaded``:
    /// the embed rebooted, so its opening is already counted.
    ///
    /// Calling it early is not a way to skip it: the bridge queues commands
    /// until the embed reports `ready` and replays them, so a call issued
    /// during the host's initial setup still lands as an extra opening.
    ///
    /// A detail sheet, a modal or a full-screen card presented over the map is
    /// not a new opening: do not call it when such a screen is dismissed and
    /// the map reappears.
    ///
    /// Each call opens a fresh analytics session (new session id, +1 session in
    /// the partner dashboard). It does not start a new MapTiler billing
    /// session: the web document is not reloaded.
    public func trackOpen() {
        bridge.call(name: ExploreCommand.analyticsMapOpened, payload: nil)
    }

    /// Send the pending map-usage counters now, while the web view is still
    /// alive, and keep the session open (the open is never counted twice, and
    /// what happens next is still recorded). ``LaTraceExploreMapView`` already
    /// calls this when the app resigns active, so a host has nothing to wire;
    /// call it only when the host tears the map down on its own terms.
    public func flushAnalytics() {
        bridge.call(name: ExploreCommand.analyticsFlush, payload: nil)
    }

    // MARK: - Lifecycle

    /// Send the pending counters and drop optimistic state. Call it before
    /// releasing the map view: the session (and the opening it carries) is
    /// only recorded by a flush, so tearing the web view down without one
    /// loses it entirely. Event delivery stops when subscribers cancel their
    /// subscriptions to ``eventsPublisher``.
    public func destroy() {
        flushAnalytics()
        highlightedPin = nil
    }

    // MARK: - Command encoding

    /// Returns `false` when the payload could not be encoded and nothing was
    /// sent, so callers never report a success the embed never saw.
    @discardableResult
    private func send<P: Encodable>(_ name: String, _ payload: P) -> Bool {
        do {
            let data = try encoder.encode(payload)
            bridge.call(name: name, payload: data)
            return true
        } catch {
            // JSONEncoder throws on any non-finite Double, so a stray NaN deep
            // in a POI wipes the whole frame. Logged rather than asserted: an
            // assertion is a no-op in release, which is exactly where the
            // corpus would silently vanish.
            NSLog("[LaTraceMapSDK] dropped '%@': payload could not be encoded (%@)", name, String(describing: error))
            return false
        }
    }

    private static func dropped(_ name: String, _ reason: String) {
        NSLog("[LaTraceMapSDK] dropped '%@': %@", name, reason)
    }

    private static func isUsable(_ center: LngLat) -> Bool {
        center.count == 2 && center[0].isFinite && center[1].isFinite
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static func result(_ accepted: [Poi], _ rejected: [PushReject], sent: Bool) -> PushResult {
        guard sent else {
            return PushResult(
                accepted: 0,
                rejected: rejected + accepted.map { PushReject(id: $0.id, reason: .encodingFailed) }
            )
        }
        return PushResult(accepted: accepted.count, rejected: rejected)
    }

    private static func partition(_ pois: [Poi]) -> (accepted: [Poi], rejected: [PushReject]) {
        var accepted: [Poi] = []
        var rejected: [PushReject] = []
        for poi in pois {
            if poi.id.isEmpty {
                rejected.append(PushReject(id: "", reason: .emptyId))
                continue
            }
            let c = poi.coords
            if c.count != 2 || !c[0].isFinite || !c[1].isFinite {
                rejected.append(PushReject(id: poi.id, reason: .invalidCoords))
                continue
            }
            accepted.append(poi)
        }
        return (accepted, rejected)
    }

    // MARK: - Command payload shapes

    private struct PoisPayload: Encodable {
        let pois: [Poi]
    }

    private struct FlyToPayload: Encodable {
        let center: LngLat
        let zoom: Double?
        let pitch: Double?
        let bearing: Double?
        let durationMs: Int?
    }

    private struct FitBoundsPayload: Encodable {
        let bbox: BBox
        let padding: Padding?
    }

    private struct ConfigPayload: Encodable {
        let config: ConfigOverride
    }

    private struct LocalePayload: Encodable {
        let locale: Locale
    }

    /// `{ coords: { … } | null }` — the null must be emitted, not omitted,
    /// so the embed clears the blue dot.
    private struct SetUserLocationPayload: Encodable {
        let coords: UserCoords?
        enum CodingKeys: String, CodingKey { case coords }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let coords {
                try container.encode(coords, forKey: .coords)
            } else {
                try container.encodeNil(forKey: .coords)
            }
        }
    }

    private struct BasemapPayload: Encodable {
        let basemap: Basemap
    }

    private struct InitialView: Encodable {
        let bbox: BBox
    }

    private struct ActivateMapPayload: Encodable {
        let initialView: InitialView
    }

    /// `{ poiId: string | null }` — null clears the selection.
    private struct HighlightPayload: Encodable {
        let poiId: String?
        enum CodingKeys: String, CodingKey { case poiId }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let poiId {
                try container.encode(poiId, forKey: .poiId)
            } else {
                try container.encodeNil(forKey: .poiId)
            }
        }
    }
}
