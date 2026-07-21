import Foundation

/// Type-erased Codable wrapper used to carry arbitrary JSON payloads
/// (custom `data` blobs, opaque event payloads, etc.) across the bridge
/// without forcing a specific shape on the integrator.
///
/// Decoding accepts the JSON primitive types (`null`, `Bool`, `Int`,
/// `Double`, `String`, arrays and dictionaries). Encoding writes the value
/// back as its underlying JSON-compatible type.
public struct AnyCodable: Codable, Equatable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any?) {
        self.value = value ?? ()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = ()
            return
        }
        if let bool = try? container.decode(Bool.self) {
            self.value = bool
            return
        }
        if let int = try? container.decode(Int.self) {
            self.value = int
            return
        }
        if let double = try? container.decode(Double.self) {
            self.value = double
            return
        }
        if let string = try? container.decode(String.self) {
            self.value = string
            return
        }
        if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
            return
        }
        if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary.mapValues { $0.value }
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "AnyCodable cannot decode value"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is Void:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map(AnyCodable.init))
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues(AnyCodable.init))
        case let codable as AnyCodable:
            try codable.encode(to: encoder)
        case Optional<Any>.none:
            try container.encodeNil()
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "AnyCodable cannot encode value of type \(type(of: value))"
                )
            )
        }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case is (Void, Void):
            return true
        case let (l as Bool, r as Bool):
            return l == r
        case let (l as Int, r as Int):
            return l == r
        case let (l as Double, r as Double):
            return l == r
        case let (l as String, r as String):
            return l == r
        case let (l as [Any], r as [Any]):
            return l.map(AnyCodable.init) == r.map(AnyCodable.init)
        case let (l as [String: Any], r as [String: Any]):
            return l.mapValues(AnyCodable.init) == r.mapValues(AnyCodable.init)
        default:
            return false
        }
    }
}
