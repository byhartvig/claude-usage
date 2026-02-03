import SwiftUI

struct UsageMenuView: View {
    @ObservedObject var state: UsageState
    let onRefresh: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                ClaudeLogoView(size: 22, color: Color(red: 0.85, green: 0.47, blue: 0.34))

                Text("Claude")
                    .font(.system(size: 18, weight: .semibold))

                Spacer()

                Text(state.subscriptionType)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)

            if state.needsAuth {
                authPrompt
            } else {
                // Usage sections
                VStack(alignment: .leading, spacing: 20) {
                    if let session = state.sessionLimit {
                        UsageSection(
                            title: "Session",
                            percentage: session.utilization,
                            resetText: "Resets in \(session.timeUntilReset)"
                        )
                    }

                    if let weekly = state.weeklyLimit {
                        UsageSection(
                            title: "Weekly",
                            percentage: weekly.utilization,
                            resetText: "Resets in \(weekly.timeUntilReset)"
                        )
                    }

                    if let sonnet = state.sonnetLimit {
                        UsageSection(
                            title: "Sonnet",
                            percentage: sonnet.utilization,
                            resetText: "Resets in \(sonnet.timeUntilReset)"
                        )
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer(minLength: 32)

            // Footer
            VStack(spacing: 12) {
                HStack {
                    Button(action: onRefresh) {
                        Text("Refresh")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.85, green: 0.47, blue: 0.34))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(state.isLoading)
                    .opacity(state.isLoading ? 0.6 : 1)

                    Spacer()

                    if let lastUpdated = state.lastUpdated {
                        Text(updateText(from: lastUpdated))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                Button(action: onQuit) {
                    Text("Quit")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 300, height: 410)
    }

    private var authPrompt: some View {
        VStack(spacing: 12) {
            Text("Run 'claude login' in terminal")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }

    private func updateText(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "Updated just now"
        } else {
            let minutes = Int(interval / 60)
            return "Updated \(minutes)m ago"
        }
    }
}

struct UsageSection: View {
    let title: String
    let percentage: Double
    let resetText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.1))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: 0.15, green: 0.15, blue: 0.2))
                        .frame(width: max(geometry.size.width * (percentage / 100), percentage > 0 ? 8 : 0))
                }
            }
            .frame(height: 8)

            // Stats
            HStack {
                Text(String(format: "%.0f%%", percentage))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                Spacer()

                Text(resetText)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    UsageMenuView(
        state: UsageState(),
        onRefresh: {},
        onQuit: {}
    )
}
