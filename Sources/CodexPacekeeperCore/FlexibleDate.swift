import Foundation

struct FlexibleDate: Decodable {
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

        if let isoDate = Self.iso8601Date(from: string) {
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

    private static func iso8601Date(from string: String) -> Date? {
        let standardFormatter = ISO8601DateFormatter()
        if let date = standardFormatter.date(from: string) {
            return date
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: string)
    }
}
