// TierManager.swift
// Manages tier state, trial countdown, device registration, and proxy calls.
// Integrates with RevenueCat for paid subscriptions.

import Foundation

// MARK: - Tier

enum WalkieTier: String, Codable, Equatable {
    case freeTrial    = "free_trial"
    case paidMonthly  = "paid_monthly"
    case paidAnnual   = "paid_annual"
    case byok         = "byok"
    case expired      = "expired"

    var isPaid: Bool {
        self == .paidMonthly || self == .paidAnnual || self == .byok
    }
}

// MARK: - Proxy config
// Replace with your Cloudflare Worker URL after deploying

private let PROXY_BASE_URL    = "https://walkie-proxy.YOUR_SUBDOMAIN.workers.dev"
private let APP_SHARED_SECRET = "REPLACE_WITH_YOUR_SECRET"   // Must match worker env

// MARK: - TierStatus (mirrors proxy response)

struct TierStatus: Codable {
    let tier:            String
    let requestsToday:   Int
    let dailyLimit:      Int
    let canSendRequest:  Bool
    let trialEndsAt:     Double?
    let trialDaysLeft:   Int?
    let upgradeRequired: Bool
}

// MARK: - TierManager

@MainActor
final class TierManager: ObservableObject {

    static let shared = TierManager()

    @Published var tier: WalkieTier = .freeTrial
    @Published var trialDaysLeft: Int = 7
    @Published var requestsToday: Int = 0
    @Published var dailyLimit: Int = 10
    @Published var canSendRequest: Bool = true
    @Published var isLoading: Bool = false

    // Stable device ID — generated once, stored in Keychain
    var deviceId: String {
        let existing = KeychainManager.load(.deviceId)
        if !existing.isEmpty {
            return existing
        }
        let newId = UUID().uuidString
        KeychainManager.save(newId, for: .deviceId)
        return newId
    }

    // MARK: - Init

    private init() {
        Task { await registerAndRefresh() }
    }

    // MARK: - Register / refresh status

    func registerAndRefresh() async {
        isLoading = true
        defer { isLoading = false }

        // If user has BYOK set, bypass proxy entirely
        if hasByokKey() {
            tier = .byok
            canSendRequest = true
            return
        }

        guard let url = URL(string: "\(PROXY_BASE_URL)/v1/register") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["deviceId": deviceId])

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let status = try JSONDecoder().decode(TierStatus.self, from: data)
            applyStatus(status)
        } catch {
            // Proxy not reachable — normal when proxy not deployed yet; BYOK still works
            // Silently fall back: tier stays .freeTrial, canSendRequest stays true
        }
    }

    // MARK: - Send via proxy (free trial + paid shared)

    func sendViaProxy(messages: [[String: String]]) async -> Result<String, Error> {
        guard !PROXY_BASE_URL.contains("YOUR_SUBDOMAIN") else {
            return .failure(WalkieError.config("Proxy not configured. Add an API key in ⚙ Settings to use your own account."))
        }
        guard let url = URL(string: "\(PROXY_BASE_URL)/v1/chat") else {
            return .failure(WalkieError.config("Invalid proxy URL"))
        }

        let body: [String: Any] = [
            "deviceId":  deviceId,
            "appSecret": APP_SHARED_SECRET,
            "messages":  messages,
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let http = response as? HTTPURLResponse

            if http?.statusCode == 429 {
                let err = try? JSONDecoder().decode(ProxyError.self, from: data)
                return .failure(WalkieError.rateLimited(err?.error ?? "Rate limited"))
            }

            if http?.statusCode != 200 {
                let err = try? JSONDecoder().decode(ProxyError.self, from: data)
                return .failure(WalkieError.api(err?.error ?? "Proxy error \(http?.statusCode ?? 0)"))
            }

            let result = try JSONDecoder().decode(ProxyChatResponse.self, from: data)

            // Update usage display
            if let usage = result.usage {
                requestsToday = usage.requestsToday
                dailyLimit    = usage.dailyLimit
            }

            return .success(result.text)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Upgrade (call after RevenueCat purchase confirms)

    func upgradeToMonthly() {
        tier = .paidMonthly
        dailyLimit = 200
        canSendRequest = true
        Task { await registerAndRefresh() }
    }

    func upgradeToAnnual() {
        tier = .paidAnnual
        dailyLimit = 200
        canSendRequest = true
        Task { await registerAndRefresh() }
    }

    // MARK: - Switch to BYOK

    func switchToByok() {
        tier = .byok
        canSendRequest = true
    }

    // MARK: - Helpers

    private func hasByokKey() -> Bool {
        let ai = AIService.shared
        return !ai.claudeKey.isEmpty || !ai.openAIKey.isEmpty
            || !ai.geminiKey.isEmpty || !ai.grokKey.isEmpty
    }

    private func applyStatus(_ s: TierStatus) {
        tier = WalkieTier(rawValue: s.tier) ?? .expired
        requestsToday = s.requestsToday
        dailyLimit    = s.dailyLimit
        canSendRequest = s.canSendRequest
        trialDaysLeft = s.trialDaysLeft ?? 0
    }

    // MARK: - Computed display

    var tierDisplayName: String {
        switch tier {
        case .freeTrial:   return "Free Trial"
        case .paidMonthly: return "Walkie Pro"
        case .paidAnnual:  return "Walkie Pro (Annual)"
        case .byok:        return "BYOK"
        case .expired:     return "Trial Expired"
        }
    }

    var trialBadge: String? {
        guard tier == .freeTrial else { return nil }
        return trialDaysLeft > 0 ? "\(trialDaysLeft)d left" : "Expired"
    }

    var isProActive: Bool {
        tier == .paidMonthly || tier == .paidAnnual || tier == .byok
    }
}

// MARK: - Errors + Decodables

enum WalkieError: LocalizedError {
    case rateLimited(String)
    case api(String)
    case config(String)

    var errorDescription: String? {
        switch self {
        case .rateLimited(let m): return m
        case .api(let m):         return m
        case .config(let m):      return m
        }
    }
}

private struct ProxyError: Codable {
    let error: String
    let upgradeRequired: Bool?
}

private struct ProxyChatResponse: Codable {
    let text: String
    let usage: ProxyUsage?
}

private struct ProxyUsage: Codable {
    let tier: String
    let requestsToday: Int
    let dailyLimit: Int
    let trialEndsAt: Double?
}
