import CodexPacekeeperCore
import SwiftUI

struct HUDView: View {
    let dashboard: UsageDashboardSnapshot

    init(dashboard: UsageDashboardSnapshot) {
        self.dashboard = dashboard
    }

    init(snapshot: UsageSnapshot) {
        self.dashboard = UsageDashboardSnapshot(
            providers: [ProviderUsageSnapshot(provider: .codex, snapshot: snapshot)],
            fallback: snapshot
        )
    }

    var body: some View {
        PaceSummaryView(dashboard: dashboard)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .frame(width: 280)
    }
}

struct PaceSummaryView: View {
    let dashboard: UsageDashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if dashboard.hasUsageData {
                ForEach(Array(dashboard.providers.enumerated()), id: \.element.id) { index, providerSnapshot in
                    if index > 0 {
                        Divider()
                            .opacity(0.6)
                    }

                    ProviderSummaryView(providerSnapshot: providerSnapshot)
                }
            } else {
                StatusOnlyView(snapshot: dashboard.fallback)
            }
        }
    }
}

private struct ProviderSummaryView: View {
    let providerSnapshot: ProviderUsageSnapshot

    private var snapshot: UsageSnapshot {
        providerSnapshot.snapshot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProviderRecommendationLine(
                provider: providerSnapshot.provider,
                recommendation: snapshot.paceRecommendation
            )
            PaceRow(reading: snapshot.primary, now: snapshot.lastRefreshedAt)
            PaceRow(reading: snapshot.weekly, now: snapshot.lastRefreshedAt)

            if snapshot.state != .fresh {
                StaleStatusView(snapshot: snapshot)
            }
        }
    }
}

private struct StaleStatusView: View {
    let snapshot: UsageSnapshot

    private var stateColor: Color {
        switch snapshot.state {
        case .loading:
            return .blue
        case .fresh:
            return .green
        case .stale:
            return .orange
        case .error:
            return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 6, height: 6)
                Text(snapshot.stateLabel)
                Text(snapshot.lastRefreshedAt, style: .time)
            }

            if let message = snapshot.message {
                Text(message)
                    .lineLimit(2)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

private struct StatusOnlyView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: snapshot.stateSystemImageName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.stateLabel.capitalized)
                    .font(.headline)

                if let message = snapshot.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

private struct ProviderRecommendationLine: View {
    let provider: UsageProvider
    let recommendation: PaceRecommendation

    var body: some View {
        HStack(spacing: 8) {
            Text(provider.displayName.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 78, alignment: .leading)

            Image(systemName: recommendation.direction.systemImageName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 18)

            Text(recommendation.action)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(statusColor)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private var statusColor: Color {
        switch recommendation.status {
        case .easy:
            return .orange
        case .steady:
            return .green
        case .tempo:
            return .orange
        case .threshold:
            return .orange
        case .redline:
            return .red
        }
    }
}

private struct PaceRow: View {
    let reading: PaceReading
    let now: Date

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
            GridRow {
                WindowLabel(text: reading.label)

                HStack(spacing: 0) {
                    Text(reading.actualPercent.roundedPercent)
                        .foregroundStyle(statusColor)
                        .fontWeight(.semibold)
                    Text(" used · \(reading.recommendedPercent.roundedPercent) target | reset \(reading.resetTimeRemaining(from: now))")
                        .foregroundStyle(.secondary)
                }
                .font(.caption2)
                .monospacedDigit()
            }

            GridRow {
                Color.clear
                    .frame(width: WindowLabel.width, height: 1)

                GaugeBar(reading: reading)
            }
        }
    }
}

private struct WindowLabel: View {
    static let width: CGFloat = 30

    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .monospaced()
            .frame(width: Self.width, alignment: .trailing)
    }
}

private struct GaugeBar: View {
    let reading: PaceReading

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let actualX = width * reading.actualPercent / 100
            let paceX = width * reading.recommendedPercent / 100

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: 6)

                Capsule()
                    .fill(statusColor)
                    .frame(width: max(6, actualX), height: 6)

                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 2, height: 14)
                    .offset(x: paceX)
                    .accessibilityLabel("Recommended pace")
            }
        }
        .frame(height: 14)
    }

    private var statusColor: Color {
        reading.status.hudColor
    }
}

private extension PaceRow {
    var statusColor: Color {
        reading.status.hudColor
    }
}

private extension PaceStatus {
    var hudColor: Color {
        switch self {
        case .easy:
            return .orange
        case .steady:
            return .green
        case .tempo:
            return .orange
        case .threshold:
            return .orange
        case .redline:
            return .red
        }
    }
}

private extension Double {
    var roundedPercent: String {
        "\(Int(rounded()))%"
    }

}

private extension PaceReading {
    func resetTimeRemaining(from now: Date) -> String {
        let remaining = max(0, resetAt.timeIntervalSince(now))
        let totalMinutes = Int((remaining / 60).rounded())

        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours < 24 {
            return minutes == 0 ? "\(hours)h" : "\(hours)h\(minutes)m"
        }

        let days = hours / 24
        let remainingHours = hours % 24

        return remainingHours == 0 ? "\(days)d" : "\(days)d\(remainingHours)h"
    }
}
