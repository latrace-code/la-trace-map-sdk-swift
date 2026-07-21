import Foundation

/// Result of a corpus push (``LaTraceExploreMap/setPois(_:)`` /
/// ``LaTraceExploreMap/addPois(_:)``).
///
/// The SDK validates POIs client-side before sending: entries with an
/// empty `id` or invalid `coords` are rejected locally and never reach the
/// embed. `accepted` counts the POIs actually pushed — the embed validates
/// again on its side (duplicate id, empty resolved name) and reports what it
/// refused through ``LaTraceExploreEvent/poisRejected(_:)``.
public struct PushResult: Codable, Equatable, Sendable {
    public let accepted: Int
    public let rejected: [PushReject]

    public init(accepted: Int, rejected: [PushReject] = []) {
        self.accepted = accepted
        self.rejected = rejected
    }
}

/// A single rejected POI and the reason it was dropped.
public struct PushReject: Codable, Equatable, Sendable {
    public enum Reason: String, Codable, Equatable, Sendable {
        /// `id` was empty.
        case emptyId = "empty-id"
        /// `coords` was not a finite `[lng, lat]` pair.
        case invalidCoords = "invalid-coords"
        /// The frame carrying this POI could not be serialised (a non-finite
        /// number somewhere in the payload), so nothing was sent.
        case encodingFailed = "encoding-failed"
    }

    /// The offending POI id (empty string when the id itself was missing).
    public let id: String
    public let reason: Reason

    public init(id: String, reason: Reason) {
        self.id = id
        self.reason = reason
    }
}
