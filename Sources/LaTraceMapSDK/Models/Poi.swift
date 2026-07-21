import Foundation

/// A point of interest pushed to the map corpus.
///
/// 1:1 mirror of the wire-types `Poi` (map-sdk-contract, CONTRAT 1).
/// `id`, `coords`, `category` and `name` are required; everything else is
/// optional enrichment. `custom` is an opaque pass-through the map never
/// interprets.
///
/// - `category` drives the **marker colour** via `ConfigOverride.poiColors`.
/// - `poiType` (fine type) drives the **marker glyph**.
public struct Poi: Codable, Equatable, Sendable {

    // MARK: Required

    /// Opaque, stable key used everywhere (selection, tracking, dedup).
    public var id: String
    /// `[lng, lat]` in WGS84.
    public var coords: LngLat
    /// Parent category — source of the marker colour.
    public var category: String

    /// Display name. Required by the contract: the embed drops a POI whose
    /// name resolves to an empty string in the active locale, so a nameless
    /// POI never reaches the map.
    ///
    /// Optional on the property (not in the initializer) only so an inbound
    /// `pin:click` frame still decodes when the embed sends a POI without a
    /// resolved name; a pushed POI always carries one.
    public var name: LocalizedString?

    // MARK: Optional display

    /// Fine POI type (taxonomy `PoiType`) — source of the marker glyph.
    public var poiType: String?
    public var typeLabel: LocalizedString?
    public var address: String?
    public var city: String?
    public var postalCode: String?
    /// ISO-3166 alpha-2.
    public var country: String?
    public var priceRange: PriceRange?
    public var openingHours: OpeningHours?
    public var phone: String?
    public var email: String?
    public var website: String?
    public var description: LocalizedString?
    public var images: [PoiImage]?
    public var badges: [PoiBadge]?
    public var externalUrl: String?
    public var reservationUrl: String?
    public var facets: [String: [String]]?
    public var rank: Double?
    public var editorialTabs: [PoiEditorialTab]?
    public var adSlot: PoiAdSlot?
    /// Opaque pass-through, never interpreted by the map.
    public var custom: [String: AnyCodable]?

    public init(
        id: String,
        coords: LngLat,
        category: String,
        name: LocalizedString,
        poiType: String? = nil,
        typeLabel: LocalizedString? = nil,
        address: String? = nil,
        city: String? = nil,
        postalCode: String? = nil,
        country: String? = nil,
        priceRange: PriceRange? = nil,
        openingHours: OpeningHours? = nil,
        phone: String? = nil,
        email: String? = nil,
        website: String? = nil,
        description: LocalizedString? = nil,
        images: [PoiImage]? = nil,
        badges: [PoiBadge]? = nil,
        externalUrl: String? = nil,
        reservationUrl: String? = nil,
        facets: [String: [String]]? = nil,
        rank: Double? = nil,
        editorialTabs: [PoiEditorialTab]? = nil,
        adSlot: PoiAdSlot? = nil,
        custom: [String: AnyCodable]? = nil
    ) {
        self.id = id
        self.coords = coords
        self.category = category
        self.name = name
        self.poiType = poiType
        self.typeLabel = typeLabel
        self.address = address
        self.city = city
        self.postalCode = postalCode
        self.country = country
        self.priceRange = priceRange
        self.openingHours = openingHours
        self.phone = phone
        self.email = email
        self.website = website
        self.description = description
        self.images = images
        self.badges = badges
        self.externalUrl = externalUrl
        self.reservationUrl = reservationUrl
        self.facets = facets
        self.rank = rank
        self.editorialTabs = editorialTabs
        self.adSlot = adSlot
        self.custom = custom
    }
}

// MARK: - Nested value types

/// `priceRange?: PriceLevel | { min?, max?, currency }`.
public enum PriceRange: Codable, Equatable, Sendable {
    case level(PriceLevel)
    case range(min: Double?, max: Double?, currency: String)

    private enum CodingKeys: String, CodingKey {
        case min, max, currency
    }

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let level = try? single.decode(PriceLevel.self) {
            self = .level(level)
            return
        }
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        self = .range(
            min: try keyed.decodeIfPresent(Double.self, forKey: .min),
            max: try keyed.decodeIfPresent(Double.self, forKey: .max),
            currency: try keyed.decode(String.self, forKey: .currency)
        )
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .level(let level):
            var single = encoder.singleValueContainer()
            try single.encode(level)
        case .range(let min, let max, let currency):
            var keyed = encoder.container(keyedBy: CodingKeys.self)
            try keyed.encodeIfPresent(min, forKey: .min)
            try keyed.encodeIfPresent(max, forKey: .max)
            try keyed.encode(currency, forKey: .currency)
        }
    }
}

/// `openingHours?: OpeningHours | string`.
///
/// The structured `OpeningHours` shape is not fixed by the carte-pilotée
/// subset, so structured values are carried as opaque JSON and passed
/// through unchanged.
public enum OpeningHours: Codable, Equatable, Sendable {
    case text(String)
    case structured(AnyCodable)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .text(string)
            return
        }
        self = .structured(try container.decode(AnyCodable.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let string):
            try container.encode(string)
        case .structured(let value):
            try container.encode(value)
        }
    }
}

public struct PoiImage: Codable, Equatable, Sendable {
    public var url: String
    public var alt: String?
    public var credit: String?

    public init(url: String, alt: String? = nil, credit: String? = nil) {
        self.url = url
        self.alt = alt
        self.credit = credit
    }
}

public struct PoiBadge: Codable, Equatable, Sendable {
    public var type: String
    public var label: String?

    public init(type: String, label: String? = nil) {
        self.type = type
        self.label = label
    }
}

public struct PoiEditorialTab: Codable, Equatable, Sendable {
    public var key: String
    public var label: LocalizedString
    public var contentMarkdown: LocalizedString

    public init(key: String, label: LocalizedString, contentMarkdown: LocalizedString) {
        self.key = key
        self.label = label
        self.contentMarkdown = contentMarkdown
    }
}

public struct PoiAdSlot: Codable, Equatable, Sendable {
    public var html: String?
    public var imageUrl: String?
    public var clickUrl: String?
    public var label: String?

    public init(
        html: String? = nil,
        imageUrl: String? = nil,
        clickUrl: String? = nil,
        label: String? = nil
    ) {
        self.html = html
        self.imageUrl = imageUrl
        self.clickUrl = clickUrl
        self.label = label
    }
}
