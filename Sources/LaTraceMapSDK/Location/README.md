# Location

Native CoreLocation helper for the La Trace Map SDK.

`LaTraceLocationProvider` wraps `CLLocationManager` and forwards the
acquired coordinates to an arbitrary sink closure — typically
`LaTraceExploreMap.setUserLocation(_:)`, but the provider has no
compile-time dependency on the map so it can be used standalone.

## Info.plist requirement

The host application **must** declare a usage description in its
`Info.plist`, otherwise iOS silently skips the permission prompt and the
user is stuck in `.notDetermined` forever:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We use your location to show your position on the map and find points of interest near you.</string>
```

The provider only requests "When in use" authorization. If your app
needs background updates, add a separate `CLLocationManager` of your
own; this helper intentionally keeps the scope narrow.

## Integration with the map

When paired with `LaTraceExploreMapView`, the typical wiring is:

```swift
import LaTraceMapSDK

let map = mapView.map

let provider = LaTraceLocationProvider(
    sink: { [weak map] lng, lat, accuracy in
        map?.setUserLocation(UserCoords(lng: lng, lat: lat, accuracy: accuracy))
    },
    authorizationHandler: { status in
        switch status {
        case .denied, .restricted:
            // Show a "Location disabled" UI in the host app.
            break
        case .authorizedWhenInUse, .authorizedAlways:
            // Permission granted — nothing to do, updates will start
            // flowing through the sink.
            break
        default:
            break
        }
    }
)

// Trigger from a user gesture:
provider.requestPermission()
provider.start()
```

The provider is fully usable on its own — point the sink at any closure
that consumes `(lng, lat, accuracy?)`, typically a call to
`LaTraceExploreMap.setUserLocation(_:)`.

## Lifecycle

| Method | Behavior |
| --- | --- |
| `requestPermission()` | Triggers the "When in use" prompt. iOS only shows it once per app lifetime — subsequent calls are no-ops at the system level. |
| `start()` | Begins continuous updates. Idempotent. |
| `stop()` | Stops continuous updates. Idempotent. |
| `requestOnce()` | One-shot fix via `CLLocationManager.requestLocation()`. Lighter on battery than `start()` + `stop()` for a single sample. |

The sink is always invoked on the main thread because
`CLLocationManagerDelegate` callbacks are delivered on main.

## Behavior when permission is denied

If the user denies the prompt, `authorizationHandler` receives
`.denied`. `start()` and `requestOnce()` will silently fail (no error,
no sink invocation) — CoreLocation routes the denial through
`locationManager(_:didFailWithError:)`, which the provider logs in
debug builds and otherwise swallows. Hosts should rely on
`authorizationHandler` to drive UI changes, not on the absence of sink
calls.

## Known limitations

- **No visual accuracy circle.** The JS-side `setUserLocation` paints
  a custom marker but does not yet render an accuracy ring. The
  `accuracy` value is still forwarded so we can light up the visual
  the day it ships in the JS SDK without breaking the Swift API.
- **`horizontalAccuracy < 0` is reported as `nil`.** CoreLocation uses
  a negative value to signal "invalid" — forwarding the raw negative
  number would confuse JS consumers, so the provider normalizes it.
- **iOS 15+ only.** `CLLocationManagerDelegate` is used in its
  classic, callback-based form; iOS 17's async/await APIs are not
  used to keep deployment compatibility wide.
