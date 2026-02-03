import SwiftUI

@main
struct ClaudeUsageApp: App {
    @StateObject private var usageState = UsageState()

    var body: some Scene {
        MenuBarExtra {
            UsageMenuView(
                state: usageState,
                onRefresh: { usageState.refresh() },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarLabel: some View {
        HStack(spacing: 4) {
            ClaudeLogoView(size: 14, color: .primary)
            if let session = usageState.sessionLimit {
                Text(String(format: "%.0f%%", session.utilization))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
        }
    }
}
