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

    @Published var subscriptionType: String = ""
    @Published var isLoading = false
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published var needsAuth = false

    private let refreshInterval: TimeInterval = 60 // 1 minute
    private var refreshTimer: Timer?

    init() {
        checkAuthAndRefresh()
        startAutoRefresh()
    }

    func refresh() {
        Task { @MainActor in
            await fetchUsage()
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

// MARK: - Formatting

extension Double {
    var percentFormatted: String {
        String(format: "%.0f%%", self)
    }
}
