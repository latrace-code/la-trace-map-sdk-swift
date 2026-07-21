import Foundation

/// Wire contract shared with the Explore embed (`map-sdk-contract`).
///
/// Every frame in either direction is a `BridgeEnvelope`:
/// `{ channel: 'lt-explore', v: 1, kind, name, payload?, id?, error? }`.
/// `kind: 'cmd'` = host -> embed (drive the map), `kind: 'evt'` = embed ->
/// host (report). `res` is reserved and unused in this L1 subset.
///
/// The channel/version constants are frozen; a frame that does not match
/// both is dropped by ``BridgeMessageHandler``.
///
/// The transport (``BridgeMessageHandler`` / ``LaTraceMapBridge``) only reads
/// the envelope **header** (channel / version / name) and forwards the raw
/// `payload`. The inbound payload wire models and the strongly-typed event
/// surface live in chantier 3 (`InboundEnvelope` → `LaTraceExploreEvent`),
/// so they are intentionally absent here.
public enum BridgeEnvelope {
    /// `BRIDGE_CHANNEL` — frozen. Matches the WKScriptMessageHandler name
    /// `lt` on the native side; the two are intentionally different (`lt`
    /// is the transport channel, `lt-explore` is the protocol channel).
    public static let channel = "lt-explore"

    /// `BRIDGE_VERSION` — frozen at 1.
    public static let version = 1

    public enum Kind: String, Codable, Sendable {
        case cmd
        case evt
        case res
    }
}
