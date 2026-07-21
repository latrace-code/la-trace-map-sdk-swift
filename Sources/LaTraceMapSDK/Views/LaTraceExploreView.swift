#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import Combine

/// Optional SwiftUI wrapper around ``LaTraceExploreMapView``.
///
/// UIKit is the primary surface (the Fooding app is UIKit); this is a thin
/// convenience for SwiftUI hosts. Grab the ``LaTraceExploreMap`` controller
/// via ``onMapReady`` to issue commands, and observe events via
/// ``onEvent``.
public struct LaTraceExploreView: UIViewRepresentable {

    private let options: LaTraceExploreOptions
    private let theme: LaTraceMapViewTheme
    private let onEvent: ((LaTraceExploreEvent) -> Void)?
    private let onMapReady: ((LaTraceExploreMap) -> Void)?

    public init(
        options: LaTraceExploreOptions,
        theme: LaTraceMapViewTheme = .default,
        onEvent: ((LaTraceExploreEvent) -> Void)? = nil,
        onMapReady: ((LaTraceExploreMap) -> Void)? = nil
    ) {
        self.options = options
        self.theme = theme
        self.onEvent = onEvent
        self.onMapReady = onMapReady
    }

    public func makeUIView(context: Context) -> LaTraceExploreMapView {
        let view = LaTraceExploreMapView(options: options, theme: theme)
        if let onMapReady {
            // Defer so the SwiftUI tree has finished mounting.
            DispatchQueue.main.async { onMapReady(view.map) }
        }
        if let onEvent {
            context.coordinator.subscribe(to: view, callback: onEvent)
        }
        return view
    }

    public func updateUIView(_ uiView: LaTraceExploreMapView, context: Context) {
        // No-op. State flows through the controller, not SwiftUI diffing.
    }

    public static func dismantleUIView(
        _ uiView: LaTraceExploreMapView,
        coordinator: Coordinator
    ) {
        // Last moment the web view is still alive: the pending counters (and
        // the opening they carry) are only recorded by this flush.
        uiView.map.destroy()
        coordinator.cancel()
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
        private var cancellable: AnyCancellable?

        func subscribe(
            to view: LaTraceExploreMapView,
            callback: @escaping (LaTraceExploreEvent) -> Void
        ) {
            cancellable = view.eventsPublisher
                .receive(on: DispatchQueue.main)
                .sink { callback($0) }
        }

        func cancel() {
            cancellable?.cancel()
            cancellable = nil
        }
    }
}
#endif
