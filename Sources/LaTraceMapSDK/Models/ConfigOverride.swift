import Foundation

/// Live configuration override for the piloted map (colours, glyphs,
/// declutter density, chrome presets, locale).
///
/// Sub-set of the wire-types `ConfigOverride` (CONTRAT 1 §3.2) relevant to
/// the carte-pilotée surface. Every field is optional — it is a `Partial`,
/// so only the provided keys are applied by the embed.
public struct ConfigOverride: Codable, Equatable, Sendable {

    /// Semantic `--lt-*` theme tokens.
    public var theme: [String: String]?
    /// **Single source** of marker colour, keyed by `Poi.category`.
    public var poiColors: [String: PoiColor]?
    /// Custom marker logos, keyed by `poiType` (then `category`).
    public var poiIcons: [String: String]?
    /// Declutter exclusion radius in px, `(0, 200]`.
    public var poiExclusionRadiusPx: Double?
    public var mapNav: MapNavOverride? = nil
    /// What a pin tap does inside the embed. A host that shows its own card MUST send
    /// `hostHandled`: `panel` (the embed default) leaves its POI panel open behind a
    /// bare UI, keeping the pin emphasised forever since the host never closes a panel
    /// it cannot see, and `externalPreview` stacks the embed's own bottom sheet under
    /// the host's card (that preview is content, so the bare chrome does not hide it).
    public var poiDetailMode: PoiDetailMode?
    /// Stores the active locale, but does **not** re-translate the chrome nor
    /// the corpus already pushed: use ``LaTraceExploreMap/setLocale(_:)`` to
    /// switch language.
    public var locale: Locale?

    public init(
        theme: [String: String]? = nil,
        poiColors: [String: PoiColor]? = nil,
        poiIcons: [String: String]? = nil,
        poiExclusionRadiusPx: Double? = nil,
        mapNav: MapNavOverride? = nil,
        poiDetailMode: PoiDetailMode? = nil,
        locale: Locale? = nil
    ) {
        self.theme = theme
        self.poiColors = poiColors
        self.poiIcons = poiIcons
        self.poiExclusionRadiusPx = poiExclusionRadiusPx
        self.mapNav = mapNav
        self.poiDetailMode = poiDetailMode
        self.locale = locale
    }

    /// Mirrors the embed's `config.poiDetailMode`.
    public enum PoiDetailMode: String, Codable, Equatable, Sendable {
        case panel
        case externalPreview
        /// The embed renders NO detail UI at all: it only recentres and emits
        /// `pin:click`. What a native host wants, since its own card would
        /// otherwise sit on top of the embed's preview sheet.
        case hostHandled = "none"
    }

    /// Background / text colour pair for a POI category marker.
    public struct PoiColor: Codable, Equatable, Sendable {
        public var background: String
        public var text: String

        public init(background: String, text: String) {
            self.background = background
            self.text = text
        }
    }

    /// La Trace map-nav control toggles (the partner keeps its own
    /// controls; these govern the embed's built-in widget).
    public struct MapNavOverride: Codable, Equatable, Sendable {
        public var zoom: Bool?
        public var compass: Bool?
        public var pitch3d: Bool?
        public var fullscreen: Bool?
        public var geolocate: Bool?
        public var basemapSwitcher: Bool?

        public init(
            zoom: Bool? = nil,
            compass: Bool? = nil,
            pitch3d: Bool? = nil,
            fullscreen: Bool? = nil,
            geolocate: Bool? = nil,
            basemapSwitcher: Bool? = nil
        ) {
            self.zoom = zoom
            self.compass = compass
            self.pitch3d = pitch3d
            self.fullscreen = fullscreen
            self.geolocate = geolocate
            self.basemapSwitcher = basemapSwitcher
        }
    }
}
