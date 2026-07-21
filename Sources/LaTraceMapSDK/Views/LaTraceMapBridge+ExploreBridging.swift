#if canImport(UIKit)
import Foundation

/// The single seam between chantier 3 (this Explore surface) and chantier 2
/// (`Bridge/*` transport).
///
/// `LaTraceMapBridge` (owned by chantier 2) is expected to expose exactly:
///
/// ```swift
/// func call(name: String, payload: Data?)
/// var eventsPublisher: AnyPublisher<InboundEnvelope, Never> { get }
/// ```
///
/// i.e. host → embed as an envelope command, and embed → host as decoded
/// ``InboundEnvelope`` frames. When that frozen signature is in place, this
/// empty conformance is all that is needed to feed ``LaTraceExploreMap``.
///
/// This file is the **only** place chantier 3 names the concrete bridge
/// type. Everything else depends on the ``ExploreBridging`` protocol.
extension LaTraceMapBridge: ExploreBridging {}
#endif
