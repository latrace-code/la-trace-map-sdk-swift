#if canImport(Combine)
import XCTest
import Combine
@testable import LaTraceMapSDK

/// Unit tests for the reduced Explore surface (chantier 3). They exercise
/// command serialisation, corpus validation and event decoding through a
/// mock ``ExploreBridging`` — no `WKWebView`, no JS layer.
final class ExploreApiTests: XCTestCase {

    // MARK: - Mock bridge

    private final class MockBridge: ExploreBridging {
        struct Sent { let name: String; let payload: Data? }
        private(set) var sent: [Sent] = []
        private let subject = PassthroughSubject<InboundEnvelope, Never>()

        var eventsPublisher: AnyPublisher<InboundEnvelope, Never> {
            subject.eraseToAnyPublisher()
        }
        func call(name: String, payload: Data?) {
            sent.append(Sent(name: name, payload: payload))
        }
        func emit(_ envelope: InboundEnvelope) { subject.send(envelope) }

        var last: Sent? { sent.last }
        func lastJSON() -> [String: Any]? {
            guard let data = last?.payload else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
    }

    private func makeMap() -> (LaTraceExploreMap, MockBridge) {
        let bridge = MockBridge()
        return (LaTraceExploreMap(bridge: bridge), bridge)
    }

    private func poi(_ id: String, _ lng: Double, _ lat: Double) -> Poi {
        Poi(id: id, coords: [lng, lat], category: "Gastronomy", name: .plain("P \(id)"))
    }

    // MARK: - Commands

    func testSetPoisSendsCorpusAndCounts() {
        let (map, bridge) = makeMap()
        let result = map.setPois([poi("a", 2.3, 48.8), poi("b", 2.4, 48.9)])
        XCTAssertEqual(result.accepted, 2)
        XCTAssertTrue(result.rejected.isEmpty)
        XCTAssertEqual(bridge.last?.name, "pois:set")
        let json = bridge.lastJSON()
        XCTAssertEqual((json?["pois"] as? [[String: Any]])?.count, 2)
    }

    func testSetPoisRejectsInvalid() {
        let (map, bridge) = makeMap()
        let bad = Poi(id: "", coords: [0, 0], category: "X", name: .plain("bad"))
        let nan = Poi(id: "n", coords: [.nan, 1], category: "X", name: .plain("nan"))
        let short = Poi(id: "s", coords: [1], category: "X", name: .plain("short"))
        let result = map.setPois([poi("ok", 1, 1), bad, nan, short])
        XCTAssertEqual(result.accepted, 1)
        XCTAssertEqual(result.rejected.count, 3)
        XCTAssertEqual(result.rejected.first { $0.id == "" }?.reason, .emptyId)
        XCTAssertEqual(result.rejected.first { $0.id == "n" }?.reason, .invalidCoords)
        XCTAssertEqual(result.rejected.first { $0.id == "s" }?.reason, .invalidCoords)
        // Only the valid POI is pushed.
        XCTAssertEqual((bridge.lastJSON()?["pois"] as? [[String: Any]])?.count, 1)
    }

    func testAddPoisSkipsFrameWhenAllInvalid() {
        let (map, bridge) = makeMap()
        let result = map.addPois([Poi(id: "", coords: [0, 0], category: "X", name: .plain("bad"))])
        XCTAssertEqual(result.accepted, 0)
        XCTAssertTrue(bridge.sent.isEmpty)
    }

    func testClearPoisHasNoPayload() {
        let (map, bridge) = makeMap()
        map.clearPois()
        XCTAssertEqual(bridge.last?.name, "pois:clear")
        XCTAssertNil(bridge.last?.payload)
    }

    func testFlyToPayload() {
        let (map, bridge) = makeMap()
        map.flyTo(CameraTarget(center: [2.3, 48.8], zoom: 12), options: CameraOptions(durationMs: 400))
        XCTAssertEqual(bridge.last?.name, "camera:flyTo")
        let json = bridge.lastJSON()
        XCTAssertEqual(json?["center"] as? [Double], [2.3, 48.8])
        XCTAssertEqual(json?["zoom"] as? Double, 12)
        XCTAssertEqual(json?["durationMs"] as? Int, 400)
    }

    func testSetCenterUsesFlyToInstant() {
        let (map, bridge) = makeMap()
        map.setCenter([1, 2])
        XCTAssertEqual(bridge.last?.name, "camera:flyTo")
        XCTAssertEqual(bridge.lastJSON()?["durationMs"] as? Int, 0)
        XCTAssertNil(bridge.lastJSON()?["zoom"])
    }

    func testFitBoundsPayload() {
        let (map, bridge) = makeMap()
        map.fitBounds([1, 2, 3, 4], padding: Padding(uniform: 20))
        XCTAssertEqual(bridge.last?.name, "camera:fitBounds")
        let json = bridge.lastJSON()
        XCTAssertEqual(json?["bbox"] as? [Double], [1, 2, 3, 4])
        XCTAssertEqual((json?["padding"] as? [String: Any])?["top"] as? Double, 20)
    }

    func testConfigOverridePayloadWrapping() {
        let (map, bridge) = makeMap()
        map.setConfigOverride(ConfigOverride(
            poiColors: ["Gastronomy": .init(background: "#f00", text: "#fff")],
            poiExclusionRadiusPx: 30
        ))
        XCTAssertEqual(bridge.last?.name, "config:override")
        let config = bridge.lastJSON()?["config"] as? [String: Any]
        XCTAssertEqual(config?["poiExclusionRadiusPx"] as? Double, 30)
        let colors = config?["poiColors"] as? [String: Any]
        XCTAssertEqual((colors?["Gastronomy"] as? [String: Any])?["background"] as? String, "#f00")
    }

    func testSetLocaleUsesTheDedicatedCommand() {
        let (map, bridge) = makeMap()
        map.setLocale(.nl)
        // `config:override` would only store the value: the chrome and the
        // pushed corpus would stay in the previous language.
        XCTAssertEqual(bridge.last?.name, "config:setLocale")
        XCTAssertEqual(bridge.lastJSON()?["locale"] as? String, "nl")
    }

    func testFlyToDropsNonFiniteCenterAndOmitsNonFiniteZoom() {
        let (map, bridge) = makeMap()
        map.flyTo(CameraTarget(center: [.nan, 48.8]))
        XCTAssertTrue(bridge.sent.isEmpty)

        map.flyTo(CameraTarget(center: [2.3, 48.8], zoom: .infinity, bearing: 30))
        XCTAssertEqual(bridge.last?.name, "camera:flyTo")
        XCTAssertNil(bridge.lastJSON()?["zoom"])
        XCTAssertEqual(bridge.lastJSON()?["bearing"] as? Double, 30)
    }

    func testActivateMapFallsBackToPlainActivationOnBadBBox() {
        let (map, bridge) = makeMap()
        map.activateMap(initialBBox: [.nan, 2, 3, 4])
        XCTAssertEqual(bridge.last?.name, "activateMap")
        XCTAssertNil(bridge.last?.payload)
    }

    func testDestroyFlushesPendingCounters() {
        let (map, bridge) = makeMap()
        map.destroy()
        XCTAssertEqual(bridge.last?.name, "analytics:flush")
    }

    func testSetUserLocationEmitsNullWhenCleared() throws {
        let (map, bridge) = makeMap()
        map.setUserLocation(nil)
        XCTAssertEqual(bridge.last?.name, "geo:setUserLocation")
        let data = try XCTUnwrap(bridge.last?.payload)
        let string = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(string.contains("\"coords\":null"), string)
    }

    func testSetUserLocationEmitsCoords() {
        let (map, bridge) = makeMap()
        map.setUserLocation(UserCoords(lng: 2.3, lat: 48.8, accuracy: 12))
        let coords = bridge.lastJSON()?["coords"] as? [String: Any]
        XCTAssertEqual(coords?["lng"] as? Double, 2.3)
        XCTAssertEqual(coords?["accuracy"] as? Double, 12)
    }

    func testHighlightPinOptimisticAndPayload() {
        let (map, bridge) = makeMap()
        map.highlightPin("abc")
        XCTAssertEqual(map.highlightedPin, "abc")
        XCTAssertEqual(bridge.last?.name, "poi:highlight")
        XCTAssertEqual(bridge.lastJSON()?["poiId"] as? String, "abc")
        map.highlightPin(nil)
        XCTAssertNil(map.highlightedPin)
        let string = String(decoding: bridge.last!.payload!, as: UTF8.self)
        XCTAssertTrue(string.contains("\"poiId\":null"), string)
    }

    func testTrackOpenHasNoPayloadAndIsNotImplicit() {
        let (map, bridge) = makeMap()
        XCTAssertTrue(bridge.sent.isEmpty)
        map.trackOpen()
        XCTAssertEqual(bridge.sent.count, 1)
        XCTAssertEqual(bridge.last?.name, "analytics:mapOpened")
        XCTAssertNil(bridge.last?.payload)
    }

    func testFlushAnalyticsHasNoPayload() {
        let (map, bridge) = makeMap()
        map.flushAnalytics()
        XCTAssertEqual(bridge.last?.name, "analytics:flush")
        XCTAssertNil(bridge.last?.payload)
    }

    // MARK: - Events

    private func collect(_ map: LaTraceExploreMap) -> (events: EventBox, cancellable: AnyCancellable) {
        let box = EventBox()
        let c = map.eventsPublisher.sink { box.events.append($0) }
        return (box, c)
    }

    private final class EventBox { var events: [LaTraceExploreEvent] = [] }

    func testPinClickDecoding() {
        let (map, bridge) = makeMap()
        let (box, c) = collect(map)
        defer { c.cancel() }
        let payload = try! JSONEncoder().encode(["poi": poi("z", 2.3, 48.8)])
        bridge.emit(InboundEnvelope(name: "pin:click", payload: payload))
        guard case .pinClick(let poi)? = box.events.first else {
            return XCTFail("expected pinClick, got \(box.events)")
        }
        XCTAssertEqual(poi.id, "z")
    }

    func testViewportChangeDecoding() {
        let (map, bridge) = makeMap()
        let (box, c) = collect(map)
        defer { c.cancel() }
        let payload = try! JSONEncoder().encode(Viewport(center: [2.3, 48.8], zoom: 11, bbox: [1, 2, 3, 4]))
        bridge.emit(InboundEnvelope(name: "viewport:change", payload: payload))
        guard case .viewportChange(let vp)? = box.events.first else {
            return XCTFail("expected viewportChange, got \(box.events)")
        }
        XCTAssertEqual(vp.zoom, 11)
        XCTAssertEqual(vp.bbox, [1, 2, 3, 4])
    }

    func testSearchAreaAndExternalOpenAndReadyAndError() {
        let (map, bridge) = makeMap()
        let (box, c) = collect(map)
        defer { c.cancel() }
        bridge.emit(InboundEnvelope(name: "ready", payload: nil))
        bridge.emit(InboundEnvelope(name: "search:area", payload: Data("{\"bbox\":[1,2,3,4]}".utf8)))
        bridge.emit(InboundEnvelope(name: "external:open", payload: Data("{\"poiId\":\"p\",\"url\":\"https://x\"}".utf8)))
        bridge.emit(InboundEnvelope(name: "error", payload: Data("{\"code\":\"E\",\"message\":\"boom\"}".utf8)))
        bridge.emit(InboundEnvelope(name: "unknown:thing", payload: nil))

        XCTAssertEqual(box.events, [
            .ready,
            .searchArea(bbox: [1, 2, 3, 4]),
            .externalOpen(poiId: "p", url: "https://x"),
            .error(code: "E", message: "boom")
        ])
    }

    func testPoisRejectedDecoding() {
        let (map, bridge) = makeMap()
        let (box, c) = collect(map)
        defer { c.cancel() }
        bridge.emit(InboundEnvelope(
            name: "pois:rejected",
            payload: Data("{\"rejected\":[{\"id\":\"a\",\"reason\":\"duplicate_id\"},{\"reason\":\"missing_id\"}]}".utf8)
        ))
        XCTAssertEqual(box.events, [.poisRejected([
            EmbedReject(id: "a", reason: "duplicate_id"),
            EmbedReject(id: nil, reason: "missing_id")
        ])])
    }

    func testBasemapRealignsOnEmbedEvent() {
        let (map, bridge) = makeMap()
        XCTAssertEqual(map.basemap, .plan)
        bridge.emit(InboundEnvelope(name: "basemap:change", payload: Data("{\"basemap\":\"satellite\"}".utf8)))
        XCTAssertEqual(map.basemap, .satellite)
    }

    // MARK: - Models

    func testPoiRoundTrip() throws {
        var original = poi("full", 2.3, 48.8)
        original.poiType = "Restaurant"
        original.priceRange = .level(.two)
        original.website = "https://x"
        original.images = [PoiImage(url: "https://img", credit: "c")]
        original.facets = ["cuisine": ["french", "bistro"]]
        original.custom = ["stars": AnyCodable(3)]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Poi.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testPriceRangeObjectForm() throws {
        let json = Data("{\"min\":10,\"max\":30,\"currency\":\"EUR\"}".utf8)
        let decoded = try JSONDecoder().decode(PriceRange.self, from: json)
        XCTAssertEqual(decoded, .range(min: 10, max: 30, currency: "EUR"))
    }

    func testLocalizedStringForms() throws {
        let plain = try JSONDecoder().decode(LocalizedString.self, from: Data("\"hi\"".utf8))
        XCTAssertEqual(plain, .plain("hi"))
        let loc = try JSONDecoder().decode(LocalizedString.self, from: Data("{\"fr\":\"salut\",\"en\":\"hi\"}".utf8))
        XCTAssertEqual(loc.resolved(for: .fr), "salut")
        XCTAssertEqual(loc.resolved(for: .nl), "salut") // falls back to fr
    }

    // MARK: - REST helpers

    func testExploreEmbedURLFlags() throws {
        let url = exploreEmbedURL(options: LaTraceExploreOptions(
            apiKey: "pk_live_x",
            configId: "cfg-1",
            exploreBaseUrl: URL(string: "https://preview.example.app")!,
            locale: .en
        ))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertTrue(url.path.hasSuffix("/explore"))
        XCTAssertEqual(items["sdkBridge"], "1")
        XCTAssertEqual(items["ui"], "bare")
        XCTAssertEqual(items["transport"], "native")
        XCTAssertEqual(items["customConfigId"], "cfg-1")
        XCTAssertNil(items["configId"])
        XCTAssertEqual(items["apiKey"], "pk_live_x")
        XCTAssertEqual(items["locale"], "en")
        XCTAssertNil(items["prewarm"])
    }

    func testExploreEmbedURLCarriesPrewarmFlag() throws {
        let url = exploreEmbedURL(options: LaTraceExploreOptions(
            apiKey: "pk_live_x",
            configId: "cfg-1",
            exploreBaseUrl: URL(string: "https://preview.example.app")!,
            prewarm: true
        ))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["prewarm"], "1")
    }

    func testExploreEmbedURLNeverDoublesExploreSegment() throws {
        // Base without a trailing /explore: exactly one segment appended.
        let withoutSuffix = exploreEmbedURL(options: LaTraceExploreOptions(
            apiKey: "pk_live_x",
            configId: "cfg-1",
            exploreBaseUrl: URL(string: "https://preview.example.app")!
        ))
        XCTAssertEqual(withoutSuffix.path, "/explore")
        XCTAssertFalse(withoutSuffix.path.contains("/explore/explore"))

        // Base already ending in /explore: the segment must not be doubled.
        let withSuffix = exploreEmbedURL(options: LaTraceExploreOptions(
            apiKey: "pk_live_x",
            configId: "cfg-1",
            exploreBaseUrl: URL(string: "https://preview.example.app/explore")!
        ))
        XCTAssertEqual(withSuffix.path, "/explore")
        XCTAssertFalse(withSuffix.path.contains("/explore/explore"))
    }

    func testGeocoderParsesSdkResults() {
        // SDK gateway shape (SdkGeocodeResponseDto): the backend already maps
        // Photon features to GeocodeResult, so the client parses `results`.
        let json = Data("""
        {"results":[
          {"id":"a","label":"Louvre, Paris, France","type":"poi","coords":[2.35,48.85]},
          {"id":"b","label":"Direct Label","type":"city","coords":[1.0,2.0]},
          {"id":"c","label":"Broken","type":"poi","coords":[9.9]}
        ]}
        """.utf8)
        let results = LaTraceGeocoder.parse(json)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].coords, [2.35, 48.85])
        XCTAssertEqual(results[0].label, "Louvre, Paris, France")
        XCTAssertEqual(results[1].label, "Direct Label")
    }
}
#endif
