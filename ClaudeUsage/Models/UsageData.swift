import Foundation
import AppKit
import Security

// MARK: - OAuth Usage Response (from api.anthropic.com/api/oauth/usage)

struct OAuthUsageResponse: Codable {
    let fiveHour: UsageLimit?
    let sevenDay: UsageLimit?
    let sevenDayOauthApps: UsageLimit?
    let sevenDayOpus: UsageLimit?
    let sevenDaySonnet: UsageLimit?
    let sevenDayCowork: UsageLimit?
    let iguanaNecktie: UsageLimit?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOauthApps = "seven_day_oauth_apps"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayCowork = "seven_day_cowork"
        case iguanaNecktie = "iguana_necktie"
        case extraUsage = "extra_usage"
    }
}

struct UsageLimit: Codable {
    let utilization: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    var resetsAtDate: Date? {
        guard let resetsAt = resetsAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: resetsAt)
    }

    var timeUntilReset: String {
        guard let resetDate = resetsAtDate else { return "" }
        let now = Date()
        let interval = resetDate.timeIntervalSince(now)

        if interval <= 0 { return "now" }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "\(days)d \(remainingHours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    var resetDateFormatted: String {
        guard let resetDate = resetsAtDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return formatter.string(from: resetDate)
    }
}

struct ExtraUsage: Codable {
    let isEnabled: Bool
    let monthlyLimit: Double?
    let usedCredits: Double?
    let utilization: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
    }
}

// MARK: - Keychain Credentials

struct ClaudeCredentials: Codable {
    let claudeAiOauth: OAuthCredentials?

    struct OAuthCredentials: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Int64
        let subscriptionType: String?
        let rateLimitTier: String?
    }
}

// MARK: - App State

@MainActor
class UsageState: ObservableObject {
    @Published var sessionLimit: UsageLimit?
    @Published var weeklyLimit: UsageLimit?
    @Published var sonnetLimit: UsageLimit?
    @Published var opusLimit: UsageLimit?
    @Published var extraUsage: ExtraUsage?
    @Published var localStats: LocalStatsCache?

    @Published var subscriptionType: String = ""
    @Published var isLoading = false
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published var needsAuth = false

    private let refreshInterval: TimeInterval = 60 // 1 minute
    private var refreshTimer: Timer?

    init() {
        loadLocalStats()
        checkAuthAndRefresh()
        startAutoRefresh()
    }

    func refresh() {
        loadLocalStats()
        Task { @MainActor in
            await fetchUsage()
        }
    }

    private func loadLocalStats() {
        let statsPath = NSString(string: "~/.claude/stats-cache.json").expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: statsPath) else { return }
        do {
            localStats = try JSONDecoder().decode(LocalStatsCache.self, from: data)
        } catch {
            print("Failed to load local stats: \(error)")
        }
    }

    private func checkAuthAndRefresh() {
        if getOAuthToken() == nil {
            needsAuth = true
            errorMessage = "Run 'claude login' in terminal"
        } else {
            needsAuth = false
            refresh()
        }
    }

    private func getOAuthToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        do {
            let credentials = try JSONDecoder().decode(ClaudeCredentials.self, from: data)
            if let oauth = credentials.claudeAiOauth {
                subscriptionType = oauth.subscriptionType?.capitalized ?? "Pro"
            }
            return credentials.claudeAiOauth?.accessToken
        } catch {
            return nil
        }
    }

    private func fetchUsage() async {
        guard let token = getOAuthToken() else {
            needsAuth = true
            errorMessage = "Run 'claude login' in terminal"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw UsageError.invalidResponse
            }

            if httpResponse.statusCode == 401 {
                needsAuth = true
                errorMessage = "Token expired. Run 'claude login'"
                isLoading = false
                return
            }

            guard httpResponse.statusCode == 200 else {
                throw UsageError.httpError(httpResponse.statusCode)
            }

            let usage = try JSONDecoder().decode(OAuthUsageResponse.self, from: data)

            sessionLimit = usage.fiveHour
            weeklyLimit = usage.sevenDay
            sonnetLimit = usage.sevenDaySonnet
            opusLimit = usage.sevenDayOpus
            extraUsage = usage.extraUsage

            lastUpdated = Date()
            needsAuth = false
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchUsage()
            }
        }
    }
}

enum UsageError: LocalizedError {
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response"
        case .httpError(let code): return "HTTP error \(code)"
        }
    }
}

// MARK: - Local Stats Cache (from ~/.claude/stats-cache.json)

struct LocalStatsCache: Codable {
    let totalSessions: Int?
    let totalMessages: Int?
    let longestSession: LongestSession?
    let modelUsage: [String: ModelUsage]?
    let firstSessionDate: String?
    let hourCounts: [String: Int]?
    let dailyActivity: [DailyActivity]?

    struct LongestSession: Codable {
        let duration: Int?
        let messageCount: Int?
    }

    struct ModelUsage: Codable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreationInputTokens: Int?
    }

    struct DailyActivity: Codable {
        let date: String?
        let messageCount: Int?
        let sessionCount: Int?
        let toolCallCount: Int?
    }

    var totalToolCalls: Int {
        guard let activity = dailyActivity else { return 0 }
        return activity.reduce(0) { $0 + ($1.toolCallCount ?? 0) }
    }

    var totalTokens: Int {
        guard let usage = modelUsage else { return 0 }
        return usage.values.reduce(0) { sum, model in
            sum + (model.inputTokens ?? 0) + (model.outputTokens ?? 0)
        }
    }

    var mostActiveHour: String {
        guard let counts = hourCounts, !counts.isEmpty else { return "N/A" }
        let maxHour = counts.max(by: { $0.value < $1.value })
        guard let hour = maxHour?.key, let hourInt = Int(hour) else { return "N/A" }

        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        var components = DateComponents()
        components.hour = hourInt
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date).lowercased()
        }
        return "\(hourInt):00"
    }

    var daysSinceFirstSession: Int {
        guard let dateString = firstSessionDate else { return 0 }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let firstDate = formatter.date(from: dateString) else { return 0 }
        return Calendar.current.dateComponents([.day], from: firstDate, to: Date()).day ?? 0
    }
}

// MARK: - Formatting

extension Double {
    var percentFormatted: String {
        String(format: "%.0f%%", self)
    }
}

extension Int {
    var formatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
