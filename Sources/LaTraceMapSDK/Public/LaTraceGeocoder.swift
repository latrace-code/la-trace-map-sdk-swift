import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// REST helper for the partner's **own** search bar (Photon-backed
/// `/geocode`, fr/en/nl). Lives outside the bridge — it is a plain HTTP
/// client, not a piloted-map command.
///
/// The response is the gateway shape `{ results: [{ label, coords, … }] }`
/// (contrat §4.1), parsed tolerantly: an entry without usable coords is
/// dropped rather than failing the call.
public struct LaTraceGeocoder: Sendable {

    private let apiKey: String
    private let apiBaseUrl: URL
    private let countries: String?
    private let session: URLSession

    /// - Parameters:
    ///   - apiKey: dedicated native key (`pk_live_*`), provisioned with
    ///     `allowedOrigins: ["*"]` — a native client sends no `Origin`, and an
    ///     origin-scoped key answers 403 `origin_not_allowed`.
    ///   - apiBaseUrl: **API gateway** base, the one serving `/geocode` and
    ///     `/static-map`. Not the Explore host: that one answers its SPA shell
    ///     on every path. Required, since the gateway is a deployment fact
    ///     La Trace hands over with the key.
    ///   - countries: ISO-2 CSV allowlist (e.g. `"fr,be"`). Without it the
    ///     index answers well outside the partner's territory (`Gent` returns
    ///     a Dutch result).
    public init(apiKey: String, apiBaseUrl: URL, countries: String? = nil) {
        self.apiKey = apiKey
        self.apiBaseUrl = apiBaseUrl
        self.countries = countries
        self.session = .shared
    }

    /// Internal initializer for tests with a stubbed session.
    internal init(apiKey: String, apiBaseUrl: URL, countries: String? = nil, session: URLSession) {
        self.apiKey = apiKey
        self.apiBaseUrl = apiBaseUrl
        self.countries = countries
        self.session = session
    }

    /// Type-ahead suggestions for a partial query.
    public func autocomplete(_ q: String, locale: Locale? = nil) async throws -> [GeoResult] {
        try await search(q, locale: locale, limit: 8)
    }

    /// Full forward geocoding for a complete query.
    public func geocode(_ q: String, locale: Locale? = nil) async throws -> [GeoResult] {
        try await search(q, locale: locale, limit: nil)
    }

    // MARK: - Private

    private func search(_ q: String, locale: Locale?, limit: Int?) async throws -> [GeoResult] {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var items = [URLQueryItem(name: "q", value: trimmed)]
        if let locale { items.append(URLQueryItem(name: "lang", value: locale.rawValue)) }
        if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let countries { items.append(URLQueryItem(name: "countries", value: countries)) }
        let data = try await get(path: "geocode", items: items)
        return Self.parse(data)
    }

    private func get(path: String, items: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(
            url: apiBaseUrl.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) ?? URLComponents()
        components.queryItems = (components.queryItems ?? []) + items
        guard let url = components.url else { throw LaTraceGeocoderError.invalidURL }

        // The SDK gateway authenticates `/geocode` by the `X-LaTrace-Key` header
        // (SdkKeyGuard), NOT a query param — only `/static-map` uses `?key=` (an
        // <img> can't send a header). Sending the key as a query param here was
        // silently rejected (401) by the guard.
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-LaTrace-Key")

        // Continuation wrapper around `dataTask` so the API is async
        // without requiring macOS 12 (`URLSession.data(for:)`). The
        // cancellation handler is what actually stops the request: without
        // it, a debounced-then-cancelled keystroke still burns a quota unit.
        let task = LockedTask()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let dataTask = session.dataTask(with: request) { data, response, error in
                    if let error { continuation.resume(throwing: error); return }
                    if let http = response as? HTTPURLResponse {
                        guard (200..<300).contains(http.statusCode) else {
                            continuation.resume(throwing: LaTraceGeocoderError.httpStatus(http.statusCode))
                            return
                        }
                        // A misconfigured base URL (the front host instead of
                        // the SDK gateway) answers 200 with the SPA shell;
                        // parsing it silently yields an empty result list.
                        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
                        guard contentType.lowercased().contains("json") else {
                            continuation.resume(throwing: LaTraceGeocoderError.unexpectedContentType(contentType))
                            return
                        }
                    }
                    continuation.resume(returning: data ?? Data())
                }
                task.start(dataTask)
            }
        } onCancel: {
            task.cancel()
        }
    }

    /// Holds the in-flight `URLSessionDataTask` so the cancellation handler
    /// (which runs on another thread, possibly before the task is created)
    /// can reach it.
    private final class LockedTask: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionDataTask?
        private var cancelled = false

        func start(_ task: URLSessionDataTask) {
            lock.lock()
            let alreadyCancelled = cancelled
            self.task = task
            lock.unlock()
            // Always resume first: cancelling a never-resumed task would
            // leave the completion handler (and the continuation) pending.
            task.resume()
            if alreadyCancelled { task.cancel() }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let task = self.task
            lock.unlock()
            task?.cancel()
        }
    }

    /// Parses the SDK gateway response `{ "results": [ { label, coords, … } ] }`
    /// (contrat §4.1, `SdkGeocodeResponseDto`). This is NOT Photon GeoJSON — the
    /// backend already maps Photon features to `GeocodeResult` before returning,
    /// so a `features`-based parser always yielded an empty list on success.
    internal static func parse(_ data: Data) -> [GeoResult] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = root["results"] as? [[String: Any]]
        else {
            return []
        }
        return results.compactMap { result in
            guard
                let coords = result["coords"] as? [Double],
                coords.count == 2
            else {
                return nil
            }
            let label = (result["label"] as? String) ?? ""
            return GeoResult(
                label: label,
                coords: [coords[0], coords[1]],
                secondary: result["context"] as? String
            )
        }
    }
}

public enum LaTraceGeocoderError: Error, Equatable, Sendable, LocalizedError {
    case invalidURL
    case httpStatus(Int)
    case unexpectedContentType(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid geocode URL."
        case .httpStatus(let code):
            return "Geocode request failed (HTTP \(code))."
        case .unexpectedContentType(let type):
            return "Geocode answered '\(type)' instead of JSON (wrong base URL?)."
        }
    }
}
