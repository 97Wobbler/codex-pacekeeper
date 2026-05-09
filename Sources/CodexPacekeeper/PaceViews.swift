import CodexPacekeeperCore
import SwiftUI

struct HUDView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        PaceSummaryView(snapshot: snapshot)
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
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if snapshot.hasUsageData {
                PaceRow(reading: snapshot.primary, isPrimary: true)
                PaceRow(reading: snapshot.weekly, isPrimary: false)
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

private struct PaceRow: View {
    let reading: PaceReading
    let isPrimary: Bool

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
            GridRow {
                WindowLabel(text: reading.label)

                HStack {
                    Text(reading.guidance)
                        .font(.subheadline.weight(isPrimary ? .semibold : .medium))
                        .lineLimit(1)

                    Spacer()
                }
            }

            GridRow {
                Color.clear
                    .frame(width: WindowLabel.width, height: 1)

                GaugeBar(reading: reading)
            }

            GridRow {
                Color.clear
                    .frame(width: WindowLabel.width, height: 1)

                Text("\(reading.actualPercent.roundedPercent) used · \(reading.recommendedPercent.roundedPercent) target")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
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
        switch reading.status {
        case .easy:
            return .blue
        case .steady:
            return .green
        case .tempo:
            return .yellow
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
