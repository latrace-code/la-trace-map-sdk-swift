import Foundation
import Combine

/// Ergonomic sugar over ``LaTraceExploreMap/eventsPublisher`` — one
/// closure per event, delivered on the main thread. Mirrors the JS SDK's
/// `on('event', handler)` feel without exposing Combine schedulers.
///
/// Each helper stores its subscription in the supplied `cancellables` set.
extension LaTraceExploreMap {

    /// Every event, on the main thread.
    public func observeEvents(
        in cancellables: inout Set<AnyCancellable>,
        _ handler: @escaping (LaTraceExploreEvent) -> Void
    ) {
        eventsPublisher
            .receive(on: DispatchQueue.main)
            .sink { handler($0) }
            .store(in: &cancellables)
    }

    /// Pin tapped → open the host's own popup + track the POI view.
    public func onPinClick(
        in cancellables: inout Set<AnyCancellable>,
        _ handler: @escaping (Poi) -> Void
    ) {
        eventsPublisher
            .receive(on: DispatchQueue.main)
            .sink { if case .pinClick(let poi) = $0 { handler(poi) } }
            .store(in: &cancellables)
    }

    /// Map moved / settled → the host may reload the bottom-sheet list.
    public func onViewportChange(
        in cancellables: inout Set<AnyCancellable>,
        _ handler: @escaping (Viewport) -> Void
    ) {
        eventsPublisher
            .receive(on: DispatchQueue.main)
            .sink { if case .viewportChange(let viewport) = $0 { handler(viewport) } }
            .store(in: &cancellables)
    }

    /// "Search this area" → the host queries and re-pushes the corpus.
    public func onSearchArea(
        in cancellables: inout Set<AnyCancellable>,
        _ handler: @escaping (BBox) -> Void
    ) {
        eventsPublisher
            .receive(on: DispatchQueue.main)
            .sink { if case .searchArea(let bbox) = $0 { handler(bbox) } }
            .store(in: &cancellables)
    }

    /// Basemap changed → the host realigns its own selector, including when
    /// the change did not come from ``LaTraceExploreMap/setBasemap(_:)``
    /// (the map's default at boot).
    public func onBasemapChange(
        in cancellables: inout Set<AnyCancellable>,
        _ handler: @escaping (Basemap) -> Void
    ) {
        eventsPublisher
            .receive(on: DispatchQueue.main)
            .sink { if case .basemapChange(let basemap) = $0 { handler(basemap) } }
            .store(in: &cancellables)
    }

    /// POIs the embed refused after a push → the host logs why part of its
    /// corpus is missing instead of counting pins.
    public func onPoisRejected(
        in cancellables: inout Set<AnyCancellable>,
        _ handler: @escaping ([EmbedReject]) -> Void
    ) {
        eventsPublisher
            .receive(on: DispatchQueue.main)
            .sink { if case .poisRejected(let rejected) = $0 { handler(rejected) } }
            .store(in: &cancellables)
    }

    /// Outbound link opened → outbound tracking.
    public func onExternalOpen(
        in cancellables: inout Set<AnyCancellable>,
        _ handler: @escaping (_ poiId: String, _ url: String) -> Void
    ) {
        eventsPublisher
            .receive(on: DispatchQueue.main)
            .sink { if case .externalOpen(let poiId, let url) = $0 { handler(poiId, url) } }
            .store(in: &cancellables)
    }
}
