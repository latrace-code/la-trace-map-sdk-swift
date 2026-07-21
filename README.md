# LaTraceMapSDK

Native iOS package that embeds the La Trace cartography as a **piloted map**:
the SDK owns the map (markers, camera, basemap), the host app owns everything
else (bottom sheet, POI card, search, filters).

The map itself is the La Trace Explore surface, loaded as a remote document in
a `WKWebView` and driven over a native bridge. No JS bundle ships with your
IPA, and you need neither Node nor any JS tooling.

## Requirements

- iOS 15.0 or later
- Swift 5.9 or later (Xcode 15+)
- The four integration values below, handed over by La Trace.

| Value | What it is |
| --- | --- |
| `apiKey` | Publishable native key (`pk_live_…`). Must be provisioned with `allowedOrigins: ["*"]`: a native client sends no `Origin` header, and an origin-scoped key is refused with 403 `origin_not_allowed` on `/geocode` and `/static-map`. |
| `configId` | Your map's config id (`ClientMap`). It selects the territory, the theme and the stats bucket. |
| `exploreBaseUrl` | Host serving the Explore embed (the front app). Environment-specific, never defaulted by the SDK. |
| `apiBaseUrl` | API gateway base, serving `/geocode` and `/static-map`. **Not** the Explore host: that one answers its SPA shell on every path. Only needed for the geocoder and the static-map thumbnails. |

## Install

### Swift Package Manager

In Xcode: `File > Add Package Dependencies...`, paste the repository URL
`https://github.com/latrace-code/la-trace-map-sdk-swift.git`, dependency rule
**Up to Next Major Version** from `1.0.3`, product `LaTraceMapSDK`.

Or in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/latrace-code/la-trace-map-sdk-swift.git", from: "1.0.3")
]
```

Then add `LaTraceMapSDK` as a dependency of your app target.

### CocoaPods

```ruby
pod 'LaTraceMapSDK', '~> 1.0'
```

Published on the CocoaPods trunk: <https://cocoapods.org/pods/LaTraceMapSDK>.
Both managers resolve without authentication, the repository being public.

### Runnable example

A minimal UIKit integration lives in
[`la-trace-map-sdk-example-ios`](https://github.com/latrace-code/la-trace-map-sdk-example-ios):
clone it, run `xcodegen generate`, fill in your four values, and you have a map
with your own places.

## Usage

### UIKit

```swift
import UIKit
import Combine
import LaTraceMapSDK

final class MapViewController: UIViewController {
    private var cancellables = Set<AnyCancellable>()
    private lazy var mapView = LaTraceExploreMapView(options: LaTraceExploreOptions(
        apiKey: "pk_live_…",
        configId: "…",
        exploreBaseUrl: URL(string: "https://…")!
    ))

    override func viewDidLoad() {
        super.viewDidLoad()
        mapView.frame = view.bounds
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(mapView)

        // A pin tap never opens anything inside the map: it reports, you decide.
        mapView.map.onPinClick(in: &cancellables) { [weak self] poi in
            self?.presentCard(for: poi)
            self?.mapView.map.highlightPin(poi.id)
        }

        mapView.map.setPois(restaurants.map { $0.asLaTracePoi })
        mapView.map.fitBounds(corpusBBox)
    }

    deinit { mapView.map.destroy() }
}
```

### SwiftUI

```swift
LaTraceExploreView(
    options: options,
    onEvent: { event in if case .pinClick(let poi) = event { presentCard(for: poi) } },
    onMapReady: { map in map.setPois(pois) }
)
```

## Driving the map

Everything goes through `LaTraceExploreMap` (`mapView.map`):

| | |
| --- | --- |
| Corpus | `setPois(_:)` and `addPois(_:)` return a `PushResult` listing what was refused client-side; `clearPois()` returns nothing. |
| Camera | `flyTo(_:options:)`, `fitBounds(_:padding:)`, `setCenter(_:)`. |
| Selection | `highlightPin(_:)` — visual only, `nil` clears it. |
| Look | `setConfigOverride(_:)` (`poiColors` per category, `poiIcons` per `poiType` then category, declutter radius), `setBasemap(_:)`. |
| Language | `setLocale(_:)` — re-resolves the whole pushed corpus, not just the chrome. |
| Geolocation | `setUserLocation(_:)` — you own CoreLocation, `LaTraceLocationProvider` is there if you want a ready-made one. |

Events come back on `map.eventsPublisher` (or the `on…(in:_:)` helpers):
`ready`, `pinClick`, `viewportChange`, `searchArea`, `externalOpen`,
`basemapChange`, `poisRejected` and `error`.

## Counting map usage

Openings and sessions feed the partner dashboard:

- a normal embed counts its opening at boot;
- a pre-warmed one (`prewarm: true`, view mounted hidden) counts it when you
  call `activateMap(initialBBox:)`;
- `trackOpen()` counts a re-opening on a **reused** view (coming back to the
  map tab), never the first appearance;
- `flushAnalytics()` sends the pending counters. The view already does it when
  the app resigns active; `destroy()` does it before you drop the view.

## REST helpers

Both live outside the bridge and take `apiBaseUrl` (the gateway, see above):

- `LaTraceGeocoder(apiKey:apiBaseUrl:countries:)` — `autocomplete(_:)` /
  `geocode(_:)` for your own search bar. Pass `countries` (ISO-2 CSV) or the
  index answers well outside your territory.
- `laTraceStaticMapRequest(…)` — an authenticated `URLRequest` for a
  server-rendered thumbnail, with your own marker colours and logos.

## Contract

The wire protocol (commands, events, payloads) is specified in the La Trace
SDK API contract, which is the reference in case of doubt; this package
implements the piloted-map subset of it (no panel, no search, no filters
opened by the map). The contract revision this package targets is the one
pinned by its version.

## Development workflow

### Cut a release

From a clean `main` branch:

```bash
./scripts/release.sh 0.1.0
```

The script validates the semver argument, bumps `LaTraceMapSDKInfo.version`,
commits, creates an annotated tag and prints the two `git push` commands to
run manually. Releases are never pushed automatically.

### Continuous integration

`.github/workflows/ci.yml` runs `swift build` and `swift test` on every push
to `main`, every pull request targeting `main` and every `v*` tag.

### Debugging the embed

In `DEBUG` builds the web view is inspectable: attach Safari's Web Inspector
to the app to see the embed's own console. Frames dropped by the bridge
(off-channel, unsupported version, malformed) and commands dropped by the SDK
(unencodable payload, non-finite camera values) are logged with the
`[LaTraceMapSDK]` prefix.

## License

UNLICENSED. See [`LICENSE`](./LICENSE).
