import Foundation
import Combine
import WebKit

/// Internal Swift <-> JS transport for the Explore embed.
///
/// Responsibilities (transport only — it does **not** build or load the
/// embed URL; the view owns that, see ``LaTraceExploreMapView``):
/// - send `cmd` frames (host -> embed) as `BridgeEnvelope`s, buffering them
///   until the embed reports `ready`, then flushing in order;
/// - deserialise inbound envelopes and forward them **raw** to subscribers
///   as ``InboundEnvelope`` `(name, payload)` pairs — interpreting the
///   payload into a public event is done above the publisher (chantier 3).
///
/// Transport (frozen):
/// - embed -> host: `window.webkit.messageHandlers.lt.postMessage(JSON.stringify(envelope))`
///   (WKScriptMessageHandler named `lt`, handled by ``BridgeMessageHandler``);
/// - host -> embed: `window.__ltReceive(<jsonString>)` via `evaluateJavaScript`.
///
/// The bridge owns the WKWebView navigation-delegate slot and the `lt`
/// message-handler binding; the view wires those at construction time and
/// drives the top-level navigation itself. This is the single seam with the
/// SDK layer (chantier 3), pinned by the ``ExploreBridging`` protocol:
/// `call(name:payload:)` + `eventsPublisher`.
internal final class LaTraceMapBridge: NSObject {

    // MARK: - Event surface (seam)

    /// Combine subject fed by ``BridgeMessageHandler``. Exposed as a
    /// publisher so subscribers can't push values back into it.
    let eventsSubject = PassthroughSubject<InboundEnvelope, Never>()

    /// Latched once the embed has emitted `ready`. New subscribers to
    /// ``eventsPublisher`` receive `ready` as their first value so the
    /// bootstrap signal is never missed by a late subscriber.
    private var didEmitReady = false

    var eventsPublisher: AnyPublisher<InboundEnvelope, Never> {
        Deferred { [weak self] () -> AnyPublisher<InboundEnvelope, Never> in
            guard let self else {
                return Empty<InboundEnvelope, Never>(completeImmediately: true).eraseToAnyPublisher()
            }
            if self.didEmitReady {
                return Just(InboundEnvelope(name: ExploreEventName.ready, payload: nil))
                    .merge(with: self.eventsSubject)
                    .eraseToAnyPublisher()
            }
            return self.eventsSubject.eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }

    // MARK: - Private state

    internal weak var webView: WKWebView?
    private let messageHandler: BridgeMessageHandler

    /// `true` once the embed has emitted the `ready` event.
    private var isReady = false

    /// `cmd` frames (already serialised to an envelope JSON string) received
    /// before the embed was ready.
    private var pendingEnvelopes: [String] = []

    /// Fired when the WKWebView content process is terminated (iOS reclaims the
    /// JS process for a backgrounded/offscreen web view). Without recovery the
    /// view stays permanently black on re-display. The view reloads on this.
    var onWebContentProcessTerminated: (() -> Void)?

    /// Fired when the top-level navigation to the embed fails (no network, DNS,
    /// 4xx/5xx on the document). The view drops its "already loaded" latch so
    /// coming back to the map retries instead of showing a dead web view.
    var onNavigationFailed: (() -> Void)?

    // MARK: - Init

    init(webView: WKWebView, messageHandler: BridgeMessageHandler) {
        self.webView = webView
        self.messageHandler = messageHandler
        super.init()
        self.messageHandler.bridge = self
    }

    // MARK: - Command dispatch (host -> embed, kind: 'cmd')

    /// Send a command with an already-serialised JSON `payload` (or `nil` for
    /// payload-less commands such as `pois:clear`). Exposes the private
    /// envelope dispatch as the frozen ``ExploreBridging`` seam method: the
    /// bridge stays agnostic of the SDK-layer model types (`Poi`,
    /// `ConfigOverride`, …), which own their Codable conformance above it.
    func call(name: String, payload: Data?) {
        dispatchCommand(name: name, payloadData: payload)
    }

    private func dispatchCommand(name: String, payloadData: Data?) {
        guard let json = encodeEnvelope(kind: .cmd, name: name, payloadData: payloadData) else {
            return
        }
        // `isReady` and `pendingEnvelopes` are also written by the inbound path,
        // which always runs on the main thread (WKScriptMessageHandler). A host
        // pushing its corpus from a network completion would otherwise race the
        // flush and lose commands: serialise every access on the main queue.
        if Thread.isMainThread {
            deliverOrQueue(json)
        } else {
            DispatchQueue.main.async { [weak self] in self?.deliverOrQueue(json) }
        }
    }

    private func deliverOrQueue(_ json: String) {
        if !isReady {
            pendingEnvelopes.append(json)
            return
        }
        deliverToEmbed(json)
    }

    /// Build a `{channel,v,kind,name,payload?}` envelope JSON string.
    ///
    /// Uses JSONSerialization to splice the already-encoded `payload` object
    /// into the envelope without a second round of escaping, and omits the
    /// `payload` key entirely when there is none.
    private func encodeEnvelope(kind: BridgeEnvelope.Kind, name: String, payloadData: Data?) -> String? {
        var dict: [String: Any] = [
            "channel": BridgeEnvelope.channel,
            "v": BridgeEnvelope.version,
            "kind": kind.rawValue,
            "name": name
        ]
        if let payloadData = payloadData {
            guard let payloadObject = try? JSONSerialization.jsonObject(
                with: payloadData,
                options: [.fragmentsAllowed]
            ) else {
                assertionFailure("LaTraceMapBridge: payload for '\(name)' is not valid JSON")
                return nil
            }
            dict["payload"] = payloadObject
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Inbound ingestion (called by BridgeMessageHandler)

    /// Forward a deserialised inbound envelope (raw `name` + `payload`) to
    /// subscribers. The transport does not interpret the payload — chantier 3
    /// decodes it into a public ``LaTraceExploreEvent``.
    func handleInbound(_ envelope: InboundEnvelope) {
        if envelope.name == ExploreEventName.ready {
            if !isReady {
                isReady = true
                flushPending()
            }
            didEmitReady = true
        }
        eventsSubject.send(envelope)
    }

    /// Push a locally-produced `error` frame into the inbound stream.
    ///
    /// A failure that happens before the embed runs (no network, wrong host,
    /// an environment without the native bridge) can never be reported by the
    /// embed itself: without this the host only sees a map that never appears.
    func emitLocalError(code: String, message: String) {
        let payload = try? JSONSerialization.data(
            withJSONObject: ["code": code, "message": message]
        )
        NSLog("[LaTrace] %@: %@", code, message)
        eventsSubject.send(InboundEnvelope(name: ExploreEventName.error, payload: payload))
    }

    /// Reset the readiness latch so a fresh page load (after a content-process
    /// termination + reload) re-buffers commands until the reloaded embed
    /// re-emits `ready`. The view re-queues its `initial*` state before reloading.
    func resetForReload() {
        isReady = false
        didEmitReady = false
        pendingEnvelopes.removeAll(keepingCapacity: false)
    }

    // MARK: - Internals

    private func flushPending() {
        let snapshot = pendingEnvelopes
        pendingEnvelopes.removeAll(keepingCapacity: false)
        for json in snapshot {
            deliverToEmbed(json)
        }
    }

    /// host -> embed: `window.__ltReceive(<jsonString>)`. The envelope JSON
    /// is passed as a single-quoted JS string literal so the embed can
    /// `JSON.parse` it.
    private func deliverToEmbed(_ envelopeJSON: String) {
        evaluate("window.__ltReceive(\(jsStringLiteral(envelopeJSON)));")
    }

    private func evaluate(_ script: String) {
        guard let webView = webView else { return }
        if Thread.isMainThread {
            webView.evaluateJavaScript(script, completionHandler: nil)
        } else {
            DispatchQueue.main.async {
                webView.evaluateJavaScript(script, completionHandler: nil)
            }
        }
    }

    /// Escape a Swift string into a single-quoted JS string literal. Single
    /// quotes because the inner JSON payload is full of double quotes.
    private func jsStringLiteral(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count + 2)
        escaped.append("'")
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\":
                escaped.append("\\\\")
            case "'":
                escaped.append("\\'")
            case "\n":
                escaped.append("\\n")
            case "\r":
                escaped.append("\\r")
            case "\t":
                escaped.append("\\t")
            case "\u{2028}":
                escaped.append("\\u2028")
            case "\u{2029}":
                escaped.append("\\u2029")
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }
        escaped.append("'")
        return escaped
    }
}

// MARK: - WKNavigationDelegate

extension LaTraceMapBridge: WKNavigationDelegate {
    /// The remote embed signals readiness itself by posting the `ready`
    /// envelope on the `lt` channel, so navigation callbacks are not used to
    /// drive bootstrap. Acknowledged only.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
    }

    private func handleNavigationFailure(_ error: Error) {
        let error = error as NSError
        // A cancelled navigation is what a deliberate reload looks like, not
        // a failure.
        guard !(error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) else { return }
        emitLocalError(code: "embed_load_failed", message: error.localizedDescription)
        onNavigationFailed?()
    }

    /// iOS terminated the web content process (memory pressure while the view
    /// was offscreen/backgrounded). The web view is now a blank shell; forward
    /// so the view can re-queue its initial state and reload, instead of
    /// staying permanently black.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("[LaTrace] WKWebView content process terminated, recovering the Explore embed")
        onWebContentProcessTerminated?()
    }
}
