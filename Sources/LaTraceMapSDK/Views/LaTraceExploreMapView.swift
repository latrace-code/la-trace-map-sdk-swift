#if canImport(UIKit)
import UIKit
import WebKit
import Combine

/// UIKit-native host for the reduced Explore (piloted, bare) map.
///
/// Reuses the host ossature: owns the `WKWebView`, the
/// `BridgeMessageHandler` on the `lt` channel and a `LaTraceMapBridge`,
/// plus a spinner-until-`ready` anti-flash overlay. It differs in what it
/// loads and the surface it exposes:
///
/// - loads the **distant** top-level URL
///   `{exploreBaseUrl}/explore?sdkBridge=1&ui=bare&transport=native&…`
///   (no local `map.html`);
/// - exposes the reduced ``LaTraceExploreMap`` controller via ``map``.
public final class LaTraceExploreMapView: UIView {

    // MARK: - Public surface

    /// Pilotable controller. Issue `setPois` / `flyTo` / `setConfigOverride`
    /// etc. through it; commands sent before the embed is ready are queued
    /// by the bridge and replayed on `ready`.
    public var map: LaTraceExploreMap { controller }

    /// Every ``LaTraceExploreEvent`` the embed forwards. Deliver on the
    /// main thread on the consumer side (`.receive(on: .main)`).
    public var eventsPublisher: AnyPublisher<LaTraceExploreEvent, Never> {
        controller.eventsPublisher
    }

    /// Called after the embed has been reloaded following an iOS content-process
    /// kill. Everything the host pushed since boot (corpus, camera, highlight)
    /// is gone: re-push it here.
    public var onReloaded: (() -> Void)?

    /// Tell the SDK whether the map is on screen. When it is not, a content-process
    /// kill is not recovered immediately: the reload is deferred until the map
    /// comes back, so a background kill does not pay for a boot nobody sees.
    public func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible, pendingRecovery {
            pendingRecovery = false
            recoverFromProcessTermination()
        }
    }

    // MARK: - Private state

    private let webView: WKWebView
    private let messageHandler: BridgeMessageHandler
    private let bridge: LaTraceMapBridge
    private let controller: LaTraceExploreMap
    private let options: LaTraceExploreOptions
    private let theme: LaTraceMapViewTheme

    private var loadingSpinner: UIActivityIndicatorView?
    private var readyCancellable: AnyCancellable?
    private var readyTimeoutWatch: AnyCancellable?
    private var readyTimeout: DispatchWorkItem?
    private var resignActiveObserver: NSObjectProtocol?
    private var hasLoaded = false
    private var isVisible = true
    private var pendingRecovery = false

    /// How long the embed has to report `ready` before the host is told the
    /// map is not coming. Mirrors the web SDK's `readyTimeoutMs` default.
    private static let readyTimeoutSeconds: TimeInterval = 15

    // MARK: - Init

    public convenience init(options: LaTraceExploreOptions) {
        self.init(options: options, theme: .default)
    }

    public init(options: LaTraceExploreOptions, theme: LaTraceMapViewTheme) {
        self.options = options
        self.theme = theme

        let userContent = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContent
        if #available(iOS 14.0, *) {
            let prefs = WKWebpagePreferences()
            prefs.allowsContentJavaScript = true
            configuration.defaultWebpagePreferences = prefs
        }
        configuration.allowsInlineMediaPlayback = true
        configuration.suppressesIncrementalRendering = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView

        let messageHandler = BridgeMessageHandler()
        userContent.add(messageHandler, name: "lt")
        self.messageHandler = messageHandler

        let bridge = LaTraceMapBridge(webView: webView, messageHandler: messageHandler)
        self.bridge = bridge
        webView.navigationDelegate = bridge

        self.controller = LaTraceExploreMap(bridge: bridge)

        super.init(frame: .zero)

        configureWebView()
        installLoadingSpinnerIfNeeded()
        applyInitialState()

        // Recover from an iOS content-process kill (offscreen/backgrounded web
        // views get reclaimed): re-queue the initial state and reload, so the
        // map comes back instead of staying black. See anomaly A.
        bridge.onWebContentProcessTerminated = { [weak self] in
            self?.recoverFromProcessTermination()
        }

        // A failed top-level navigation leaves a dead web view; without
        // dropping the latch, `didMoveToWindow` would never load again and the
        // map would stay blank for the whole life of the view.
        bridge.onNavigationFailed = { [weak self] in
            self?.hasLoaded = false
        }

        // iOS suspends the web view shortly after the app leaves the
        // foreground: the usage counters must go out while the JS is still
        // running, otherwise nothing is ever recorded. `willResignActive` is
        // the last moment the app is fully alive, and the embed ignores a
        // flush with nothing to send, so over-firing (control centre, banner)
        // costs nothing. The host has nothing to wire.
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.controller.flushAnalytics()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("LaTraceExploreMapView does not support storyboard instantiation")
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "lt")
        readyCancellable?.cancel()
        readyTimeout?.cancel()
        readyTimeoutWatch?.cancel()
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
        }
    }

    // MARK: - Lifecycle

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        // Loads once the view is in a window — even when mounted hidden
        // (sized, never display:none) for prewarm. Never re-load() a web view
        // where Angular has already bootstrapped (`hasLoaded` latch): a second
        // load on a live embed re-runs zone.js → "already running" → black map.
        // Only an explicit recovery path (process kill) reloads, and it resets
        // the latch + re-queues state first.
        guard window != nil else { return }
        // A kill while the view was out of the window (a fiche presented full
        // screen) leaves the embed blank: recover on the way back, otherwise
        // the map stays black for good.
        if pendingRecovery {
            pendingRecovery = false
            recoverFromProcessTermination()
            return
        }
        guard !hasLoaded else { return }
        hasLoaded = true
        loadEmbed()
    }

    private func loadEmbed() {
        webView.load(URLRequest(url: exploreEmbedURL(options: options)))
        armReadyTimeout()
    }

    /// An embed that never reports `ready` (offline, wrong `exploreBaseUrl`,
    /// environment without the native bridge) would otherwise be a spinner
    /// that never stops and no event at all: the host could not even show its
    /// own fallback. Bounded, then reported as an `error` event.
    private func armReadyTimeout() {
        cancelReadyTimeout()
        readyTimeoutWatch = controller.eventsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                if case .ready = event { self?.cancelReadyTimeout() }
            }
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.cancelReadyTimeout()
            self.bridge.emitLocalError(
                code: "bridge_timeout",
                message: "The Explore embed did not report `ready` within \(Int(Self.readyTimeoutSeconds))s."
            )
        }
        readyTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.readyTimeoutSeconds, execute: timeout)
    }

    private func cancelReadyTimeout() {
        readyTimeout?.cancel()
        readyTimeout = nil
        readyTimeoutWatch?.cancel()
        readyTimeoutWatch = nil
    }

    /// Reload after an iOS content-process termination. The old JS context is
    /// gone (no double-bootstrap risk), so a fresh load is safe: reset the
    /// bridge readiness latch, re-queue the `initial*` state and reload the URL.
    private func recoverFromProcessTermination() {
        guard window != nil, isVisible else {
            pendingRecovery = true
            return
        }
        bridge.resetForReload()
        applyInitialState()
        if theme.showsLoadingSpinner, loadingSpinner == nil {
            installLoadingSpinnerIfNeeded()
        }
        // After a process kill `webView.url` is nil, so reload() is a no-op;
        // re-issue the top-level request explicitly.
        loadEmbed()
        onReloaded?()
    }

    // MARK: - Setup

    private func configureWebView() {
        backgroundColor = theme.backgroundColor
        webView.isOpaque = false
        webView.backgroundColor = theme.backgroundColor
        webView.scrollView.backgroundColor = theme.backgroundColor
        webView.scrollView.bouncesZoom = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.allowsLinkPreview = false

        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func installLoadingSpinnerIfNeeded() {
        guard theme.showsLoadingSpinner else { return }

        let spinner = UIActivityIndicatorView(style: .large)
        if let color = theme.spinnerColor { spinner.color = color }
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        spinner.startAnimating()
        loadingSpinner = spinner

        // `ready` fires on style.load, up to 1,5 s before the first tiles are
        // painted: dismissing there leaves an empty beige rectangle. The first
        // `viewport:change` after ready is the earliest signal that the map has
        // actually rendered. That event comes from `moveend`, so a host that
        // never moves the camera at boot would spin forever: hence the bounded
        // fallback.
        var isReady = false
        readyCancellable = controller.eventsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                switch event {
                case .ready:
                    isReady = true
                    self?.scheduleSpinnerFallback()
                case .viewportChange where isReady:
                    self?.dismissLoadingSpinner()
                default:
                    break
                }
            }
    }

    private func scheduleSpinnerFallback() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.dismissLoadingSpinner()
        }
    }

    private func dismissLoadingSpinner() {
        loadingSpinner?.stopAnimating()
        loadingSpinner?.removeFromSuperview()
        loadingSpinner = nil
        readyCancellable?.cancel()
        readyCancellable = nil
    }

    /// Queues the `initial*` commands. The bridge buffers these until the
    /// embed reports `ready`, then replays them in order (config → locale →
    /// pois → camera).
    private func applyInitialState() {
        controller.setConfigOverride(hostConfig)
        if let locale = options.locale {
            // The `locale` query param only sets the embed's chrome language;
            // the pushed corpus keeps resolving its LocalizedStrings in the
            // default one until this command lands.
            controller.setLocale(locale)
        }
        if let pois = options.initialPois {
            controller.setPois(pois)
        }
        if let view = options.initialView {
            controller.flyTo(view, options: CameraOptions(durationMs: 0))
        }
    }

    /// The host's config, with `poiDetailMode` defaulted to `hostHandled`.
    ///
    /// The SDK loads the embed with `ui=bare` and the host renders its own
    /// card, so the embed's default (`panel`) would open a POI panel nothing
    /// paints, leaving the tapped pin emphasised for good. A host that asks
    /// for another mode explicitly still gets it.
    private var hostConfig: ConfigOverride {
        var config = options.initialConfig ?? ConfigOverride()
        if config.poiDetailMode == nil { config.poiDetailMode = .hostHandled }
        return config
    }
}
#endif
