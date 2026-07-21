import Foundation
import WebKit

/// `WKScriptMessageHandler` on the `lt` channel. Deserialises inbound
/// `BridgeEnvelope` frames (embed -> host) and forwards them **raw** to the
/// ``LaTraceMapBridge`` as ``InboundEnvelope`` `(name, payload)` pairs.
///
/// This layer is a pure transport: it validates the frozen envelope header
/// (`channel == 'lt-explore'`, matching version) and hands the untouched
/// `name` + `payload` up. It does **not** interpret payloads — decoding a
/// frame into a public event (`pin:click` → `Poi`, `viewport:change` →
/// `Viewport`, …) is chantier 3's job, above the bridge publisher. Keeping
/// the transport payload-agnostic means the contract can grow without a
/// bridge change.
///
/// The embed posts `JSON.stringify(envelope)` (a `String`); a raw dictionary
/// body is also tolerated for test fixtures that bypass `JSON.stringify`.
/// Any frame that is malformed, off-channel, or the wrong version is dropped
/// with a debug log rather than crashing.
internal final class BridgeMessageHandler: NSObject, WKScriptMessageHandler {

    /// Set by ``LaTraceMapBridge/init``. `weak` to avoid the retain cycle
    /// WKUserContentController -> handler -> bridge -> webView.
    weak var bridge: LaTraceMapBridge?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let bridge = bridge else { return }

        guard let dict = messageDictionary(from: message.body) else {
            NSLog("[LaTraceMapSDK] dropped message with unrecognised body: %@", String(describing: message.body))
            return
        }

        guard let envelope = deserialiseEnvelope(dict) else { return }
        bridge.handleInbound(envelope)
    }

    // MARK: - Envelope deserialisation (header only)

    /// Normalise the message body (JSON string or raw dict) to `[String: Any]`.
    private func messageDictionary(from body: Any) -> [String: Any]? {
        if let string = body as? String,
           let data = string.data(using: .utf8) {
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        return body as? [String: Any]
    }

    /// Validate the frozen envelope header, then forward `(name, payload)`
    /// raw. Returns `nil` (and logs) for off-channel / wrong-version /
    /// malformed frames.
    private func deserialiseEnvelope(_ dict: [String: Any]) -> InboundEnvelope? {
        guard let channel = dict["channel"] as? String, channel == BridgeEnvelope.channel else {
            NSLog("[LaTraceMapSDK] dropped off-channel frame: %@", String(describing: dict["channel"]))
            return nil
        }
        if let v = dict["v"] as? Int, v != BridgeEnvelope.version {
            NSLog("[LaTraceMapSDK] dropped frame with unsupported version %d", v)
            return nil
        }
        guard let name = dict["name"] as? String else {
            NSLog("[LaTraceMapSDK] dropped frame without a name")
            return nil
        }
        return InboundEnvelope(name: name, payload: payloadData(from: dict["payload"]))
    }

    /// Re-serialise a JSON `payload` value back to `Data`, or `nil` when the
    /// frame carries no payload.
    private func payloadData(from payload: Any?) -> Data? {
        guard let payload = payload, !(payload is NSNull) else { return nil }
        return try? JSONSerialization.data(withJSONObject: payload, options: [.fragmentsAllowed])
    }
}
