import CodexPacekeeperCore
import Foundation

enum UsageProvider: String, CaseIterable, Hashable, Identifiable {
    case codex
    case claudeCode

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claudeCode:
            return "Claude"
        }
    }

    var menuBarCode: String {
        switch self {
        case .codex:
            return "CX"
        case .claudeCode:
            return "CL"
        }
    }

    var sortIndex: Int {
        switch self {
        case .codex:
            return 0
        case .claudeCode:
            return 1
        }
    }
}

struct ProviderUsageSnapshot: Equatable, Identifiable {
    let provider: UsageProvider
    let snapshot: UsageSnapshot

    var id: UsageProvider {
        provider
    }
}

struct UsageDashboardSnapshot: Equatable {
    let providers: [ProviderUsageSnapshot]
    let fallback: UsageSnapshot

    var hasUsageData: Bool {
        !providers.isEmpty
    }

    var menuBarTitle: String {
        guard let mostUrgentProvider else {
            return fallback.menuBarTitle
        }

        if providers.count == 1 {
            return mostUrgentProvider.snapshot.menuBarTitle
        }

        return "PK \(mostUrgentProvider.provider.menuBarCode) \(mostUrgentProvider.snapshot.primary.deltaPercentagePoints.signedRounded)"
    }

    var stateSystemImageName: String {
        mostUrgentProvider?.snapshot.stateSystemImageName ?? fallback.stateSystemImageName
    }

    var primarySnapshot: UsageSnapshot {
        mostUrgentProvider?.snapshot ?? fallback
    }

    var primaryProviderSnapshot: ProviderUsageSnapshot? {
        mostUrgentProvider
    }

    var staleProviderCount: Int {
        providers.filter { $0.snapshot.state != .fresh }.count
    }

    static var placeholder: UsageDashboardSnapshot {
        UsageDashboardSnapshot(
            providers: [ProviderUsageSnapshot(provider: .codex, snapshot: .placeholder)],
            fallback: .placeholder
        )
    }

    func withPaused(_ paused: Bool) -> UsageDashboardSnapshot {
        UsageDashboardSnapshot(
            providers: providers.map {
                ProviderUsageSnapshot(provider: $0.provider, snapshot: $0.snapshot.withPaused(paused))
            },
            fallback: fallback.withPaused(paused)
        )
    }

    private var mostUrgentProvider: ProviderUsageSnapshot? {
        let candidates = providers.filter { $0.snapshot.hasUsageData }
        let rankedProviders = candidates.isEmpty ? providers : candidates

        return rankedProviders.max { lhs, rhs in
            lhs.snapshot.paceRecommendation.status.urgencyRank < rhs.snapshot.paceRecommendation.status.urgencyRank
        }
    }
}

private extension PaceStatus {
    var urgencyRank: Int {
        switch self {
        case .easy:
            return 0
        case .steady:
            return 1
        case .tempo:
            return 2
        case .threshold:
            return 3
        case .redline:
            return 4
        }
    }
}

private extension Double {
    var signedRounded: String {
        let roundedValue = Int(rounded())
        return roundedValue >= 0 ? "+\(roundedValue)" : "\(roundedValue)"
    }
}
