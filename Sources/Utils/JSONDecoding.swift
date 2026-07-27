//
//  JSONDecoding.swift
//  Qonversion
//

import Foundation

extension JSONDecoder.DateDecodingStrategy {

    /// The v4 API sends RFC3339 dates, but not uniformly: some fields carry
    /// fractional seconds and some of the entitlement history keys inherited
    /// from the previous API generation carry unix timestamps. A strict
    /// .iso8601 decoder fails the WHOLE payload on any of those, so all three
    /// forms are accepted.
    static var qonversionTolerant: JSONDecoder.DateDecodingStrategy {
        return .custom { decoder in
            let container = try decoder.singleValueContainer()

            if let timestamp: Double = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: timestamp)
            }

            let raw: String = try container.decode(String.self)
            if let date: Date = ISO8601Parsing.date(from: raw) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an RFC3339 date or a unix timestamp, got \"" + raw + "\"")
        }
    }
}

enum ISO8601Parsing {

    private static let parser = ISO8601Parser()

    static func date(from raw: String) -> Date? {
        return parser.date(from: raw)
    }
}

// @unchecked: ISO8601DateFormatter is not Sendable, so parsing is serialized
// by the lock; the formatters themselves are configured once at init.
private final class ISO8601Parser: @unchecked Sendable {

    // Both are needed: ISO8601DateFormatter matches its option set exactly, so
    // one formatter cannot read both "…T10:00:00Z" and "…T10:00:00.123Z".
    private let plainFormatter: ISO8601DateFormatter
    private let fractionalFormatter: ISO8601DateFormatter
    private let lock = NSLock()

    init() {
        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.formatOptions = [.withInternetDateTime]
        self.plainFormatter = plainFormatter

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.fractionalFormatter = fractionalFormatter
    }

    func date(from raw: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }

        if let date: Date = fractionalFormatter.date(from: raw) {
            return date
        }

        return plainFormatter.date(from: raw)
    }
}

/// Decodes an array element by element, skipping the ones that fail: one
/// malformed row must degrade the list, not null it. Production tolerance —
/// a single bad entitlement, property or config would otherwise cost the user
/// everything the response carried.
enum LossyArray {

    static func decode<Element: Decodable>(_ elementType: Element.Type, from container: inout UnkeyedDecodingContainer) -> [Element] {
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element: Element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                // Skip the malformed element; the container must still advance.
                _ = try? container.decode(AnyDecodableValue.self)
            }
        }

        return elements
    }
}

/// Consumes one arbitrary JSON value so a lossy array can advance past it.
struct AnyDecodableValue: Decodable {

    init(from decoder: Decoder) throws { }
}
