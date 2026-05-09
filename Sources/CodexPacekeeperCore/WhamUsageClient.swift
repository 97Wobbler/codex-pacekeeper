import Foundation

public enum WhamUsageClientError: Error, LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case missingWindow(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Usage API returned an invalid response"
        case .httpStatus(let status):
            return "Usage API returned HTTP \(status)"
        case .missingWindow(let label):
            return "Usage API response is missing \(label) window data"
        }
    }
}

public final class WhamUsageClient {
    private let endpoint: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(
        endpoint: URL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.session = session
        self.decoder = JSONDecoder()
    }

    public func fetchSnapshot(accessToken: String, now: Date = Date()) async throws -> UsageSnapshot {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhamUsageClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw WhamUsageClientError.httpStatus(httpResponse.statusCode)
        }

        let usageResponse = try decoder.decode(WhamUsageResponse.self, from: data)

        return try UsageSnapshot(
            primary: usageResponse.rateLimit.primaryWindow.usageWindow(label: "5h", now: now).pace(at: now),
            weekly: usageResponse.rateLimit.secondaryWindow.usageWindow(label: "week", now: now).pace(at: now),
            lastRefreshedAt: now,
            state: .fresh,
            message: nil
        )
    }
}

private struct WhamUsageResponse: Decodable {
    let rateLimit: WhamRateLimit

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
    }
}

private struct WhamRateLimit: Decodable {
    let primaryWindow: WhamUsageWindow
    let secondaryWindow: WhamUsageWindow

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct WhamUsageWindow: Decodable {
    let usedPercent: Double
    let limitWindowSeconds: TimeInterval
    let resetAt: FlexibleDate?
    let resetAfterSeconds: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
        case resetAfterSeconds = "reset_after_seconds"
    }

    func usageWindow(label: String, now: Date) throws -> UsageWindow {
        let resetDate: Date

        if let resetAt {
            resetDate = resetAt.date
        } else if let resetAfterSeconds {
            resetDate = now.addingTimeInterval(resetAfterSeconds)
        } else {
            throw WhamUsageClientError.missingWindow(label)
        }

        return UsageWindow(
            label: label,
            usedPercent: usedPercent,
            resetAt: resetDate,
            limitWindowSeconds: limitWindowSeconds
        )
    }
}

private struct FlexibleDate: Decodable {
    let date: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let timestamp = try? container.decode(Double.self) {
            if timestamp > 1_000_000_000_000 {
                date = Date(timeIntervalSince1970: timestamp / 1_000)
            } else {
                date = Date(timeIntervalSince1970: timestamp)
            }
            return
        }

        let string = try container.decode(String.self)

        if let timestamp = Double(string) {
            if timestamp > 1_000_000_000_000 {
                date = Date(timeIntervalSince1970: timestamp / 1_000)
            } else {
                date = Date(timeIntervalSince1970: timestamp)
            }
            return
        }

        if let isoDate = ISO8601DateFormatter().date(from: string) {
            date = isoDate
            return
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported date format")
    }
}
