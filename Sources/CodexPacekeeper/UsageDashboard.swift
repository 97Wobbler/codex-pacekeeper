import CodexPacekeeperCore
import Foundation

enum UsageProvider: String, CaseIterable, Hashable {
    case codex
    case claudeCode

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claudeCode:
            return "Claude Code"
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

        return "PK \(mostUrgentProvider.snapshot.primary.deltaPercentagePoints.signedRounded)"
    }

    var stateSystemImageName: String {
        mostUrgentProvider?.snapshot.stateSystemImageName ?? fallback.stateSystemImageName
    }

    static var placeholder: UsageDashboardSnapshot {
        UsageDashboardSnapshot(providers: [], fallback: .placeholder)
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
        providers.max { lhs, rhs in
            lhs.snapshot.paceRecommendation.status.urgencyRank < rhs.snapshot.paceRecommendation.status.urgencyRank
        }
    }
}

private extension PaceStatus {
    var urgencyRank: Int {
        switch self {
        case .steady:
            return 0
        case .easy:
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
