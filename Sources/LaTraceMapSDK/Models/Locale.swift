import Foundation

/// UI / content locale supported by the LaTrace Explore surface.
///
/// Mirrors the wire contract `type Locale = 'fr' | 'en' | 'nl'`.
public enum Locale: String, Codable, CaseIterable, Sendable {
    case fr
    case en
    case nl
}

/// Price bracket for a POI, mirroring the wire contract
/// `type PriceLevel = '€' | '€€' | '€€€' | '€€€€'`.
public enum PriceLevel: String, Codable, Equatable, Sendable {
    case one = "€"
    case two = "€€"
    case three = "€€€"
    case four = "€€€€"
}

/// A string that is either language-neutral or localised per ``Locale``.
///
/// Mirrors the wire contract
/// `type LocalizedString = string | Partial<Record<Locale, string>>`.
/// A bare JSON string decodes to ``plain``; a `{ fr, en, nl }` object
/// decodes to ``localized``.
public enum LocalizedString: Codable, Equatable, Sendable {
    case plain(String)
    case localized([Locale: String])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .plain(string)
            return
        }
        // Locale keys are raw strings on the wire; decode into a
        // `[String: String]` first, then keep only recognised locales.
        let raw = try container.decode([String: String].self)
        var byLocale: [Locale: String] = [:]
        for (key, value) in raw {
            if let locale = Locale(rawValue: key) {
                byLocale[locale] = value
            }
        }
        self = .localized(byLocale)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .plain(let string):
            try container.encode(string)
        case .localized(let byLocale):
            var raw: [String: String] = [:]
            for (locale, value) in byLocale {
                raw[locale.rawValue] = value
            }
            try container.encode(raw)
        }
    }

    /// Best-effort resolution for display. For ``localized`` values,
    /// prefers `locale`, then `fr`, then `en`, then any available value.
    public func resolved(for locale: Locale? = nil) -> String {
        switch self {
        case .plain(let string):
            return string
        case .localized(let byLocale):
            if let locale, let value = byLocale[locale] { return value }
            if let value = byLocale[.fr] { return value }
            if let value = byLocale[.en] { return value }
            return byLocale.values.first ?? ""
        }
    }
}
