import SwiftUI

struct UsageBucketRow: View {
    let label: String
    let bucket: UsageBucket?

    private var pct: Double { bucket?.usedPercentage ?? 0 }

    private var color: Color {
        if pct >= 90 { return .red }
        if pct >= 70 { return .orange }
        return .green
    }

    private var resetText: String {
        guard let bucket, let date = bucket.resetsAtDate else { return "" }
        let seconds = Int(max(0, date.timeIntervalSinceNow))
        if seconds <= 0 { return "Reset now" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        }
        return "Resets in \(minutes)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text(String(format: "%.0f%%", pct))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
            }

            ProgressView(value: min(pct, 100), total: 100)
                .tint(color)

            if !resetText.isEmpty {
                Text(resetText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
