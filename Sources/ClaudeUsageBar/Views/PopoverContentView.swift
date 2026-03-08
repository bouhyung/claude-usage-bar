import SwiftUI

struct PopoverContentView: View {
    @ObservedObject var service: AuthService
    @State private var codeInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Claude Usage")
                .font(.headline)

            if !service.isAuthenticated {
                signInView
            } else {
                usageView
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: - Sign In

    @ViewBuilder
    private var signInView: some View {
        if service.isAwaitingCode {
            Text("Paste the code from your browser:")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField("code#state", text: $codeInput)
                    .textFieldStyle(.roundedBorder)
                Button("Submit") {
                    Task { await service.submitOAuthCode(codeInput) }
                }
                .disabled(codeInput.isEmpty)
            }
        } else {
            Text("Sign in to view your usage.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Sign in with Claude") {
                service.startOAuthFlow()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }

        if let error = service.lastError {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.caption)
        }

        Divider()
        quitButton
    }

    // MARK: - Usage

    @ViewBuilder
    private var usageView: some View {
        if let usage = service.usage {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                VStack(spacing: 10) {
                    UsageBucketRow(label: "5-Hour Window", bucket: usage.fiveHour)
                    UsageBucketRow(label: "7-Day Window", bucket: usage.sevenDay)

                    if let extra = usage.extraUsage, extra.isEnabled {
                        Divider()
                        extraUsageView(extra)
                    }
                }
            }
        } else if service.lastError == nil {
            HStack {
                Spacer()
                ProgressView("Loading...")
                Spacer()
            }
            .padding(.vertical, 10)
        }

        if let error = service.lastError {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.caption)
        }

        if let updated = service.lastUpdated {
            Text("Updated: \(updated.formatted(.dateTime.hour().minute().second()))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }

        Divider()
        HStack {
            Button("Refresh") {
                Task { await service.fetchUsage() }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Spacer()
            Button("Sign Out") {
                service.signOut()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            quitButton
        }
    }

    @ViewBuilder
    private func extraUsageView(_ extra: ExtraUsage) -> some View {
        HStack {
            Text("Extra Usage")
                .font(.caption)
                .fontWeight(.medium)
            Spacer()
            if let used = extra.usedCreditsAmount, let limit = extra.monthlyLimitAmount {
                Text(String(format: "$%.2f / $%.2f", used, limit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        if let pct = extra.utilization {
            ProgressView(value: min(pct, 100), total: 100)
                .tint(pct >= 90 ? .red : pct >= 70 ? .orange : .blue)
        }
    }

    private var quitButton: some View {
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
