// AIService.swift
// Unified provider abstraction for Claude (Anthropic) and OpenAI GPT.
// Switch providers and manage keys in Settings — all state persisted in UserDefaults.

import Foundation

// MARK: - Provider

enum AIProvider: String, CaseIterable, Identifiable {
    case claude = "claude"
    case openai = "openai"
    case gemini = "gemini"
    case grok   = "grok"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .openai: return "OpenAI"
        case .gemini: return "Gemini"
        case .grok:   return "Grok"
        }
    }

    var subLabel: String {
        switch self {
        case .claude: return "Anthropic"
        case .openai: return "OpenAI"
        case .gemini: return "Google"
        case .grok:   return "xAI"
        }
    }

    var modelLabel: String {
        switch self {
        case .claude: return "claude-sonnet-4-20250514"
        case .openai: return "gpt-4o"
        case .gemini: return "gemini-2.0-flash"
        case .grok:   return "grok-3-latest"
        }
    }

    var iconName: String {
        switch self {
        case .claude: return "sparkle"
        case .openai: return "circle.grid.3x3.fill"
        case .gemini: return "diamond.fill"
        case .grok:   return "bolt.fill"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .claude: return "sk-ant-..."
        case .openai: return "sk-..."
        case .gemini: return "AIza..."
        case .grok:   return "xai-..."
        }
    }

    var consoleURL: String {
        switch self {
        case .claude: return "console.anthropic.com"
        case .openai: return "platform.openai.com/api-keys"
        case .gemini: return "aistudio.google.com/apikey"
        case .grok:   return "console.x.ai"
        }
    }
}

// MARK: - Message (shared model)

struct Message: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let role: String
    let content: String

    init(role: String, content: String) {
        self.id      = UUID()
        self.role    = role
        self.content = content
    }

    // Only encode/decode role and content — id is local only, never sent to APIs
    enum CodingKeys: String, CodingKey {
        case role, content
    }

    // Explicit Decodable init so Swift knows id gets a fresh UUID on decode
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id      = UUID()
        self.role    = try container.decode(String.self, forKey: .role)
        self.content = try container.decode(String.self, forKey: .content)
    }

    // Equality and hashing are both id-based so the contract holds:
    // equal objects always produce the same hash value.
    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - AIService

@MainActor
final class AIService: ObservableObject {

    static let shared = AIService()

    // MARK: Persisted settings

    @Published var activeProvider: AIProvider {
        didSet { UserDefaults.standard.set(activeProvider.rawValue, forKey: "active_provider") }
    }

    @Published var showTextResponse: Bool {
        didSet { UserDefaults.standard.set(showTextResponse, forKey: "show_text_response") }
    }

    @Published var maxTokens: Int {
        didSet { UserDefaults.standard.set(maxTokens, forKey: "max_tokens") }
    }

    @Published var customSystemPrompt: String {
        didSet { UserDefaults.standard.set(customSystemPrompt, forKey: "custom_system_prompt") }
    }

    @Published var isThinking = false
    @Published var errorMessage: String?

    // Per-provider key storage — backed by Keychain
    var claudeKey: String {
        get { KeychainManager.load(.claudeAPIKey) }
        set { KeychainManager.save(newValue, for: .claudeAPIKey) }
    }
    var openAIKey: String {
        get { KeychainManager.load(.openAIAPIKey) }
        set { KeychainManager.save(newValue, for: .openAIAPIKey) }
    }
    var geminiKey: String {
        get { KeychainManager.load(.geminiAPIKey) }
        set { KeychainManager.save(newValue, for: .geminiAPIKey) }
    }
    var grokKey: String {
        get { KeychainManager.load(.grokAPIKey) }
        set { KeychainManager.save(newValue, for: .grokAPIKey) }
    }

    var activeKey: String {
        switch activeProvider {
        case .claude: return claudeKey
        case .openai: return openAIKey
        case .gemini: return geminiKey
        case .grok:   return grokKey
        }
    }

    // MARK: Init

    private init() {
        let saved = UserDefaults.standard.string(forKey: "active_provider") ?? ""
        activeProvider = AIProvider(rawValue: saved) ?? .claude
        showTextResponse = UserDefaults.standard.bool(forKey: "show_text_response")
        let savedTokens = UserDefaults.standard.integer(forKey: "max_tokens")
        maxTokens = savedTokens > 0 ? savedTokens : 300
        customSystemPrompt = UserDefaults.standard.string(forKey: "custom_system_prompt") ?? ""
    }

    // MARK: - Send

    func send(text: String, history: [Message]) async -> String? {
        isThinking = true
        errorMessage = nil
        defer { isThinking = false }

        let tier = TierManager.shared.tier

        // Expired trial — hard stop before anything else
        if tier == .expired {
            errorMessage = "Trial expired. Upgrade to Pro or add your own API key in ⚙ Settings."
            return nil
        }

        // Free trial and paid-shared → use proxy (Gemini Flash, pooled key)
        // Guard with activeKey.isEmpty so BYOK always wins even if tier hasn't resolved yet
        if (tier == .freeTrial || tier == .paidMonthly || tier == .paidAnnual) && activeKey.isEmpty {
            guard TierManager.shared.canSendRequest else {
                errorMessage = "Daily limit reached (\(TierManager.shared.dailyLimit)/day). Resets at midnight."
                return nil
            }

            let messages: [[String: String]] = [
                ["role": "system", "content": systemPrompt]
            ] + history.map { ["role": $0.role, "content": $0.content] }
              + [["role": "user", "content": text]]

            let result = await TierManager.shared.sendViaProxy(messages: messages)
            switch result {
            case .success(let reply):  return reply
            case .failure(let error):
                errorMessage = error.localizedDescription
                return nil
            }
        }

        // BYOK — use selected provider directly
        guard !activeKey.isEmpty else {
            errorMessage = "No API key for \(activeProvider.displayName). Open ⚙ Settings."
            return nil
        }

        switch activeProvider {
        case .claude: return await sendClaude(text: text, history: history)
        case .openai: return await sendOpenAI(text: text, history: history)
        case .gemini: return await sendGemini(text: text, history: history)
        case .grok:   return await sendGrok(text: text, history: history)
        }
    }

    // MARK: - Claude

    private func sendClaude(text: String, history: [Message]) async -> String? {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let messages = history.map { ["role": $0.role, "content": $0.content] }
                     + [["role": "user", "content": text]]

        let body: [String: Any] = [
            "model":      AIProvider.claude.modelLabel,
            "max_tokens": maxTokens,
            "system":     systemPrompt,
            "messages":   messages
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(claudeKey,          forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let msg = String(data: data, encoding: .utf8) ?? "unknown"
                errorMessage = "Claude error: \(msg.prefix(120))"
                return nil
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let content = (json?["content"] as? [[String: Any]])?.first
            return content?["text"] as? String
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - OpenAI

    private func sendOpenAI(text: String, history: [Message]) async -> String? {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        messages += history.map { ["role": $0.role, "content": $0.content] }
        messages.append(["role": "user", "content": text])

        let body: [String: Any] = [
            "model":      AIProvider.openai.modelLabel,
            "max_tokens": maxTokens,
            "messages":   messages
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",      forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(openAIKey)",   forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let msg = String(data: data, encoding: .utf8) ?? "unknown"
                errorMessage = "OpenAI error: \(msg.prefix(120))"
                return nil
            }
            let json   = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let choices = json?["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            return message?["content"] as? String
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Gemini (Google)
    // Uses the Gemini generateContent REST API

    private func sendGemini(text: String, history: [Message]) async -> String? {
        // API key sent as a header — safer than a query param (doesn't appear in server logs)
        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(AIProvider.gemini.modelLabel):generateContent"
        guard let url = URL(string: urlStr) else { return nil }

        // Gemini uses "user"/"model" roles (not "assistant")
        var contents: [[String: Any]] = history.map { msg in
            [
                "role":  msg.role == "assistant" ? "model" : "user",
                "parts": [["text": msg.content]]
            ]
        }
        contents.append(["role": "user", "parts": [["text": text]]])

        // systemInstruction applies to every turn — fixes system prompt being lost after turn 1
        // google_search grounding gives the model live web results for current-events queries
        let body: [String: Any] = [
            "contents": contents,
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "generationConfig": [
                "maxOutputTokens": maxTokens,
                "temperature": 0.7
            ],
            "tools": [["google_search": [:] as [String: Any]]]
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(geminiKey,          forHTTPHeaderField: "x-goog-api-key")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let msg = String(data: data, encoding: .utf8) ?? "unknown"
                errorMessage = "Gemini error: \(msg.prefix(120))"
                return nil
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let candidates = json?["candidates"] as? [[String: Any]]
            let content    = candidates?.first?["content"] as? [String: Any]
            let parts      = content?["parts"] as? [[String: Any]]
            return parts?.first?["text"] as? String
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Grok (xAI)
    // xAI uses an OpenAI-compatible endpoint

    private func sendGrok(text: String, history: [Message]) async -> String? {
        let url = URL(string: "https://api.x.ai/v1/chat/completions")!

        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        messages += history.map { ["role": $0.role, "content": $0.content] }
        messages.append(["role": "user", "content": text])

        let body: [String: Any] = [
            "model":      AIProvider.grok.modelLabel,
            "max_tokens": maxTokens,
            "messages":   messages
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json",    forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(grokKey)",   forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let msg = String(data: data, encoding: .utf8) ?? "unknown"
                errorMessage = "Grok error: \(msg.prefix(120))"
                return nil
            }
            let json    = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let choices = json?["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            return message?["content"] as? String
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - System prompt (custom overrides default; default adapts to token setting)

    var systemPrompt: String {
        let datePrefix = currentDateContext()
        let custom = customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return datePrefix + custom }
        switch maxTokens {
        case ..<400:
            return datePrefix + "You are a helpful voice assistant. Keep all responses under 3 sentences. No markdown, no bullet points. Speak naturally."
        case 400..<800:
            return datePrefix + "You are a helpful assistant. Keep responses clear and conversational. Avoid heavy markdown formatting."
        case 800..<2000:
            return datePrefix + "You are a helpful assistant. Provide detailed, well-structured responses. Use formatting like bullet points when it aids clarity."
        default:
            return datePrefix + "You are a helpful assistant. Provide comprehensive, thorough responses. Use markdown formatting freely — headers, bullet points, numbered lists — as responses will be displayed as text."
        }
    }

    private func currentDateContext() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        let dateStr = formatter.string(from: Date())
        return "Today's date is \(dateStr). Use this to reason correctly about whether past events have occurred, current ages, elapsed time, and recent news. Your training data has a cutoff — defer to this date when assessing recency.\n\n"
    }
}
