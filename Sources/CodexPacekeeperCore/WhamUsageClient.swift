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
        let readings = usageResponse.rateLimit.windows
            .compactMap { $0.usageWindow(now: now) }
            .sorted { $0.limitWindowSeconds < $1.limitWindowSeconds }
            .map { $0.pace(at: now) }

        guard !readings.isEmpty else {
            throw WhamUsageClientError.missingWindow("usage")
        }

        return UsageSnapshot(
            readings: readings,
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
    let primaryWindow: WhamUsageWindow?
    let secondaryWindow: WhamUsageWindow?

    var windows: [WhamUsageWindow] {
        [primaryWindow, secondaryWindow].compactMap { $0 }
    }

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primaryWindow = try? container.decodeIfPresent(WhamUsageWindow.self, forKey: .primaryWindow)
        secondaryWindow = try? container.decodeIfPresent(WhamUsageWindow.self, forKey: .secondaryWindow)
    }
}

private struct WhamUsageWindow: Decodable {
    let usedPercent: Double?
    let limitWindowSeconds: TimeInterval?
    let resetAt: FlexibleDate?
    let resetAfterSeconds: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
        case resetAfterSeconds = "reset_after_seconds"
    }

    func usageWindow(now: Date) -> UsageWindow? {
        guard
            let usedPercent,
            usedPercent.isFinite,
            let limitWindowSeconds,
            limitWindowSeconds.isFinite,
            limitWindowSeconds > 0,
            let windowMinutes = Int(exactly: max(1, (limitWindowSeconds / 60).rounded()))
        else {
            return nil
        }

        let label = Self.windowLabel(minutes: windowMinutes)
        let resetDate: Date

        if let resetAt {
            resetDate = resetAt.date
        } else if let resetAfterSeconds, resetAfterSeconds.isFinite {
            resetDate = now.addingTimeInterval(resetAfterSeconds)
        } else {
            return nil
        }

        guard resetDate.timeIntervalSinceReferenceDate.isFinite else {
            return nil
        }

        return UsageWindow(
            label: label,
            usedPercent: usedPercent,
            resetAt: resetDate,
            limitWindowSeconds: limitWindowSeconds
        )
    }

    private static func windowLabel(minutes: Int) -> String {
        switch minutes {
        case 5 * 60:
            return "5h"
        case 7 * 24 * 60:
            return "week"
        default:
            if minutes.isMultiple(of: 24 * 60) {
                return "\(minutes / (24 * 60))d"
            }

            if minutes.isMultiple(of: 60) {
                return "\(minutes / 60)h"
            }

            return "\(minutes)m"
        }
    }
}
