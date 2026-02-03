import SwiftUI
import AppKit

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
            MenuBarIconView()
            if let session = usageState.sessionLimit {
                Text(String(format: "%.0f%%", session.utilization))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
        }
    }
}

struct MenuBarIconView: View {
    var body: some View {
        if let image = loadMenuBarIcon() {
            Image(nsImage: image)
        } else {
            ClaudeLogoView(size: 14, color: .primary)
        }
    }

    private func loadMenuBarIcon() -> NSImage? {
        if let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        return nil
    }
}
