import Foundation

struct FlexibleDate: Decodable, Equatable {
    let date: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let timestamp = try? container.decode(Double.self) {
            date = Self.date(fromTimestamp: timestamp)
            return
        }

        let string = try container.decode(String.self)

        if let timestamp = Double(string) {
            date = Self.date(fromTimestamp: timestamp)
            return
        }

        if let isoDate = Self.iso8601DateFormatter.date(from: string)
            ?? Self.iso8601DateFormatterWithFractionalSeconds.date(from: string)
        {
            date = isoDate
            return
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported date format")
    }

    private static func date(fromTimestamp timestamp: Double) -> Date {
        if timestamp > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: timestamp / 1_000)
        }

        return Date(timeIntervalSince1970: timestamp)
    }

    private static let iso8601DateFormatter = ISO8601DateFormatter()

    private static let iso8601DateFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
