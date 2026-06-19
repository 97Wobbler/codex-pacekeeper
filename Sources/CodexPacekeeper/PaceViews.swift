import CodexPacekeeperCore
import SwiftUI

struct NotchHUDLayout: Equatable {
    private static let fallbackNotchWidth: CGFloat = 184
    private static let fallbackTopInset: CGFloat = 32

    let notchWidth: CGFloat
    let topInset: CGFloat

    init(notchWidth: CGFloat?, topInset: CGFloat) {
        self.notchWidth = max(notchWidth ?? Self.fallbackNotchWidth, Self.fallbackNotchWidth)
        self.topInset = max(topInset, Self.fallbackTopInset)
    }

    var compactSize: CGSize {
        CGSize(width: max(notchWidth + 144, 320), height: 32)
    }

    var expandedSize: CGSize {
        CGSize(width: max(compactSize.width + 32, 360), height: max(topInset + 126, 154))
    }

    var topBandHeight: CGFloat {
        32
    }
}

struct HUDView: View {
    let snapshot: UsageSnapshot
    let isExpanded: Bool
    let layout: NotchHUDLayout

    var body: some View {
        ZStack(alignment: .top) {
            NotchIslandShape(bottomRadius: isExpanded ? 18 : 20)
                .fill(Color.black)
                .overlay(
                    NotchIslandShape(bottomRadius: isExpanded ? 18 : 20)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )

            if isExpanded {
                NotchExpandedSummaryView(snapshot: snapshot, layout: layout)
            } else {
                NotchCompactSummaryView(snapshot: snapshot, layout: layout)
            }
        }
        .frame(
            width: isExpanded ? layout.expandedSize.width : layout.compactSize.width,
            height: isExpanded ? layout.expandedSize.height : layout.compactSize.height
        )
        .shadow(color: .black.opacity(0.20), radius: 10, y: 3)
        .environment(\.colorScheme, .dark)
    }
}

private struct NotchIslandShape: Shape {
    let bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(bottomRadius, rect.width / 2, rect.height / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()

        return path
    }
}

struct PaceSummaryView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if snapshot.hasUsageData {
                RecommendationLine(recommendation: snapshot.paceRecommendation)
                PaceRow(reading: snapshot.primary, now: snapshot.lastRefreshedAt)
                PaceRow(reading: snapshot.weekly, now: snapshot.lastRefreshedAt)
            } else {
                StatusOnlyView(snapshot: snapshot)
            }

            if snapshot.state != .fresh {
                HStack(spacing: 6) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 6, height: 6)
                    Text(snapshot.stateLabel)
                    Text(snapshot.lastRefreshedAt, style: .time)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if let message = snapshot.message {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

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
}

private struct NotchCompactSummaryView: View {
    let snapshot: UsageSnapshot
    let layout: NotchHUDLayout

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: snapshot.stateSystemImageName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(iconColor)
                .frame(width: 24, alignment: .leading)

            Spacer(minLength: 0)

            Text(compactValue)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor)
                .monospacedDigit()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .frame(height: layout.topBandHeight)
    }

    private var compactValue: String {
        snapshot.hasUsageData ? snapshot.primary.actualPercent.roundedPercent : "--%"
    }

    private var valueColor: Color {
        snapshot.hasUsageData ? snapshot.primary.status.hudColor : .secondary
    }

    private var iconColor: Color {
        switch snapshot.state {
        case .loading:
            return .blue
        case .fresh:
            return snapshot.primary.status.hudColor
        case .stale:
            return .orange
        case .error:
            return .red
        }
    }
}

private struct NotchExpandedSummaryView: View {
    let snapshot: UsageSnapshot
    let layout: NotchHUDLayout

    var body: some View {
        VStack(spacing: 8) {
            NotchCompactSummaryView(snapshot: snapshot, layout: layout)

            PaceSummaryView(snapshot: snapshot)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
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

private struct RecommendationLine: View {
    let recommendation: PaceRecommendation

    var body: some View {
        HStack(spacing: 8) {
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
