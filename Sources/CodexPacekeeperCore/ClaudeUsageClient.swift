import Foundation

public enum ClaudeUsageClientError: Error, LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case missingWindow(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Claude Code usage API returned an invalid response"
        case .httpStatus(let status):
            return "Claude Code usage API returned HTTP \(status)"
        case .missingWindow(let label):
            return "Claude Code usage API response is missing \(label) window data"
        }
    }
}

public final class ClaudeUsageClient {
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
            throw ClaudeUsageClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClaudeUsageClientError.httpStatus(httpResponse.statusCode)
        }

        let usageResponse = try decoder.decode(ClaudeUsageResponse.self, from: data)
        let primaryWindow = try usageResponse.fiveHour.usageWindow(
            label: "5h",
            limitWindowSeconds: 5 * 60 * 60
        )
        let weeklyWindow = try usageResponse.sevenDay.usageWindow(
            label: "week",
            limitWindowSeconds: 7 * 24 * 60 * 60
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

private struct ClaudeUsageResponse: Decodable {
    let fiveHour: ClaudeUsageWindow
    let sevenDay: ClaudeUsageWindow

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct ClaudeUsageWindow: Decodable {
    let utilization: Double?
    let usedPercent: Double?
    let resetsAt: FlexibleDate?

    enum CodingKeys: String, CodingKey {
        case utilization
        case usedPercent = "used_percent"
        case resetsAt = "resets_at"
    }

    func usageWindow(label: String, limitWindowSeconds: TimeInterval) throws -> UsageWindow {
        guard let resetAt = resetsAt?.date else {
            throw ClaudeUsageClientError.missingWindow(label)
        }

        return UsageWindow(
            label: label,
            usedPercent: utilization ?? usedPercent ?? 0,
            resetAt: resetAt,
            limitWindowSeconds: limitWindowSeconds
        )
    }
}
