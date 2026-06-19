import CodexPacekeeperCore
import SwiftUI

enum HUDDisplayMode: String, CaseIterable, Identifiable {
    case notchIsland
    case floating

    static let defaultsKey = "hudDisplayMode"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .notchIsland:
            return "Notch Island"
        case .floating:
            return "Floating"
        }
    }
}

enum FloatingHUDLayout {
    static let collapsedSize = CGSize(width: 220, height: 44)
    static let expandedSize = CGSize(width: 280, height: 120)
}

enum NotchHUDAnimation {
    static let duration: Double = 0.18
}

enum HUDDockingInteraction {
    static let notchDetachThreshold: CGFloat = 28
    static let notchDetachMaxOffset: CGFloat = 24
}

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
    let displayMode: HUDDisplayMode
    let isNotchExpanded: Bool
    let notchLayout: NotchHUDLayout
    let notchDragOffset: CGFloat
    let isNotchDetachReady: Bool
    let isFloatingCollapsed: Bool

    var body: some View {
        switch displayMode {
        case .notchIsland:
            notchBody
        case .floating:
            floatingBody
        }
    }

    private var notchBody: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                NotchIslandShape(bottomRadius: isNotchExpanded ? 18 : 20)
                    .fill(Color.black)
                    .overlay(
                        NotchIslandShape(bottomRadius: isNotchExpanded ? 18 : 20)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )

                if isNotchExpanded {
                    NotchExpandedSummaryView(snapshot: snapshot, layout: notchLayout)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    NotchCompactSummaryView(snapshot: snapshot, layout: notchLayout)
                        .transition(.opacity)
                }
            }
            .frame(width: notchVisibleSize.width, height: notchVisibleSize.height, alignment: .top)
            .clipped()
            .shadow(color: .black.opacity(0.20), radius: 10, y: 3)
            .scaleEffect(isNotchDetachReady ? 0.985 : 1, anchor: .top)
            .offset(y: notchDragOffset)
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.easeOut(duration: NotchHUDAnimation.duration), value: isNotchExpanded)
            .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.82), value: isNotchDetachReady)
            .environment(\.colorScheme, .dark)
    }

    private var notchVisibleSize: CGSize {
        isNotchExpanded ? notchLayout.expandedSize : notchLayout.compactSize
    }

    private var floatingBody: some View {
        Group {
            if isFloatingCollapsed {
                FloatingCollapsedSummaryView(snapshot: snapshot)
            } else {
                PaceSummaryView(snapshot: snapshot)
            }
        }
            .padding(isFloatingCollapsed ? 8 : 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .frame(width: isFloatingCollapsed ? FloatingHUDLayout.collapsedSize.width : FloatingHUDLayout.expandedSize.width)
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

private struct FloatingCollapsedSummaryView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: snapshot.stateSystemImageName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 16)

            if snapshot.hasUsageData {
                Text(snapshot.primary.label.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospaced()

                Text(snapshot.primary.actualPercent.roundedPercent)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.primary.status.hudColor)
                    .monospacedDigit()

                Text(snapshot.paceRecommendation.action)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(snapshot.stateLabel.capitalized)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
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
