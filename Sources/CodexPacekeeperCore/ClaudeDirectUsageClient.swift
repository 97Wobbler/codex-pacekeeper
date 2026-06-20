import Foundation

public enum ClaudeDirectUsageClientError: Error, LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case missingWindow(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Claude direct usage fallback returned an invalid response"
        case .httpStatus(401), .httpStatus(403):
            return "Claude direct usage fallback is not authorized"
        case .httpStatus(let status):
            return "Claude direct usage fallback returned HTTP \(status)"
        case .missingWindow(let label):
            return "Claude direct usage fallback is missing \(label) window data"
        }
    }
}

public final class ClaudeDirectUsageClient {
    private let endpoint: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(
        endpoint: URL = URL(string: "https://api.anthropic.com/api/oauth/usage")!,
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
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeDirectUsageClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClaudeDirectUsageClientError.httpStatus(httpResponse.statusCode)
        }

        let usageResponse = try decoder.decode(ClaudeDirectUsageResponse.self, from: data)
        let primaryWindow = try usageResponse.fiveHour.usageWindow(
            label: "5h",
            limitWindowSeconds: 5 * 60 * 60,
            now: now
        )
        let weeklyWindow = try usageResponse.sevenDay.usageWindow(
            label: "week",
            limitWindowSeconds: 7 * 24 * 60 * 60,
            now: now
        )

        return UsageSnapshot(
            primary: primaryWindow.pace(at: now),
            weekly: weeklyWindow.pace(at: now),
            lastRefreshedAt: now,
            state: .fresh,
            message: nil
        )
    }
}

private struct ClaudeDirectUsageResponse: Decodable {
    let fiveHour: ClaudeDirectUsageWindow
    let sevenDay: ClaudeDirectUsageWindow

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct ClaudeDirectUsageWindow: Decodable {
    let utilization: Double?
    let usedPercent: Double?
    let usedPercentage: Double?
    let resetAt: FlexibleDate?
    let resetsAt: FlexibleDate?

    enum CodingKeys: String, CodingKey {
        case utilization
        case usedPercent = "used_percent"
        case usedPercentage = "used_percentage"
        case resetAt = "reset_at"
        case resetsAt = "resets_at"
    }

    func usageWindow(label: String, limitWindowSeconds: TimeInterval, now: Date) throws -> UsageWindow {
        guard let usedPercent = utilization ?? usedPercent ?? usedPercentage else {
            throw ClaudeDirectUsageClientError.missingWindow(label)
        }

        let resetAt: Date
        if let responseResetAt = resetsAt?.date ?? self.resetAt?.date {
            resetAt = responseResetAt
        } else if usedPercent == 0 {
            resetAt = now.addingTimeInterval(limitWindowSeconds)
        } else {
            throw ClaudeDirectUsageClientError.missingWindow(label)
        }

        return UsageWindow(
            label: label,
            usedPercent: usedPercent,
            resetAt: resetAt,
            limitWindowSeconds: limitWindowSeconds
        )
    }
}
