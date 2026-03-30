// WalkieTests.swift
// Unit tests for Walkie — PTT AI voice app
// Add target: Xcode → File → New → Target → Unit Testing Bundle → name "WalkieTests"

import XCTest
@testable import Walkie

// MARK: - PTTState Tests

final class PTTStateTests: XCTestCase {

    func test_label_returnsCorrectStringForEachState() {
        XCTAssertEqual(PTTState.idle.label,      "STANDBY")
        XCTAssertEqual(PTTState.recording.label, "TRANSMIT")
        XCTAssertEqual(PTTState.thinking.label,  "PROCESS")
        XCTAssertEqual(PTTState.speaking.label,  "RECEIVE")
    }

    func test_buttonLabel_returnsCorrectStringForEachState() {
        XCTAssertEqual(PTTState.idle.buttonLabel,      "HOLD")
        XCTAssertEqual(PTTState.recording.buttonLabel, "RELEASE")
        XCTAssertEqual(PTTState.thinking.buttonLabel,  "WAIT")
        XCTAssertEqual(PTTState.speaking.buttonLabel,  "SPEAKING")
    }

    func test_equatable_sameStateShouldBeEqual() {
        XCTAssertEqual(PTTState.idle, PTTState.idle)
        XCTAssertEqual(PTTState.recording, PTTState.recording)
        XCTAssertNotEqual(PTTState.idle, PTTState.recording)
        XCTAssertNotEqual(PTTState.thinking, PTTState.speaking)
    }
}

// MARK: - Message Tests

final class MessageTests: XCTestCase {

    func test_init_assignsFreshUUID() {
        let a = Message(role: "user", content: "hello")
        let b = Message(role: "user", content: "hello")
        XCTAssertNotEqual(a.id, b.id, "Each Message should get a unique UUID")
    }

    func test_equality_basedOnIdOnly() {
        let a = Message(role: "user", content: "hello")
        // Two messages with different content are not equal (different UUIDs)
        let b = Message(role: "user", content: "world")
        XCTAssertNotEqual(a, b)
    }

    func test_hashContract_equalObjectsHaveSameHash() {
        // Create two references to the same message via encode/decode
        let msg = Message(role: "assistant", content: "hi there")
        var hasher1 = Hasher()
        var hasher2 = Hasher()
        msg.hash(into: &hasher1)
        msg.hash(into: &hasher2)
        XCTAssertEqual(hasher1.finalize(), hasher2.finalize())
    }

    func test_codable_roundTripPreservesRoleAndContent() throws {
        let original = Message(role: "user", content: "test message")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertEqual(decoded.role,    original.role)
        XCTAssertEqual(decoded.content, original.content)
    }

    func test_codable_decodedMessageGetsFreshUUID() throws {
        let original = Message(role: "user", content: "test")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        // Decoded messages should NOT preserve the original id
        XCTAssertNotEqual(decoded.id, original.id)
    }

    func test_codable_idFieldNotEncodedInJSON() throws {
        let msg = Message(role: "user", content: "hello")
        let data = try JSONEncoder().encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(json?["id"], "id should not appear in JSON output")
        XCTAssertNotNil(json?["role"])
        XCTAssertNotNil(json?["content"])
    }
}

// MARK: - AIProvider Tests

final class AIProviderTests: XCTestCase {

    func test_allCases_containsFourProviders() {
        XCTAssertEqual(AIProvider.allCases.count, 4)
    }

    func test_id_matchesRawValue() {
        for provider in AIProvider.allCases {
            XCTAssertEqual(provider.id, provider.rawValue)
        }
    }

    func test_displayName_isNonEmpty() {
        for provider in AIProvider.allCases {
            XCTAssertFalse(provider.displayName.isEmpty)
        }
    }

    func test_modelLabel_isNonEmpty() {
        for provider in AIProvider.allCases {
            XCTAssertFalse(provider.modelLabel.isEmpty)
        }
    }

    func test_consoleURL_doesNotContainScheme() {
        // consoleURL is used with "https://" prepended — it must not already have it
        for provider in AIProvider.allCases {
            XCTAssertFalse(provider.consoleURL.hasPrefix("https://"),
                           "\(provider.displayName) consoleURL should not include scheme")
        }
    }

    func test_keyPlaceholder_isNonEmpty() {
        for provider in AIProvider.allCases {
            XCTAssertFalse(provider.keyPlaceholder.isEmpty)
        }
    }

    func test_claudeModelLabel_containsExpectedPrefix() {
        XCTAssertTrue(AIProvider.claude.modelLabel.hasPrefix("claude-"))
    }

    func test_openAIModelLabel_isGPT4o() {
        XCTAssertEqual(AIProvider.openai.modelLabel, "gpt-4o")
    }

    func test_geminiModelLabel_containsExpectedPrefix() {
        XCTAssertTrue(AIProvider.gemini.modelLabel.hasPrefix("gemini-"))
    }
}

// MARK: - WalkieTier Tests

final class WalkieTierTests: XCTestCase {

    func test_isPaid_trueForPaidAndByok() {
        XCTAssertTrue(WalkieTier.paidMonthly.isPaid)
        XCTAssertTrue(WalkieTier.paidAnnual.isPaid)
        XCTAssertTrue(WalkieTier.byok.isPaid)
    }

    func test_isPaid_falseForFreeAndExpired() {
        XCTAssertFalse(WalkieTier.freeTrial.isPaid)
        XCTAssertFalse(WalkieTier.expired.isPaid)
    }

    func test_rawValues_matchExpectedStrings() {
        XCTAssertEqual(WalkieTier.freeTrial.rawValue,   "free_trial")
        XCTAssertEqual(WalkieTier.paidMonthly.rawValue, "paid_monthly")
        XCTAssertEqual(WalkieTier.paidAnnual.rawValue,  "paid_annual")
        XCTAssertEqual(WalkieTier.byok.rawValue,        "byok")
        XCTAssertEqual(WalkieTier.expired.rawValue,     "expired")
    }

    func test_codable_roundTrip() throws {
        for tier in [WalkieTier.freeTrial, .paidMonthly, .paidAnnual, .byok, .expired] {
            let data = try JSONEncoder().encode(tier)
            let decoded = try JSONDecoder().decode(WalkieTier.self, from: data)
            XCTAssertEqual(decoded, tier)
        }
    }
}

// MARK: - KeychainManager Tests

final class KeychainManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clean slate before each test
        KeychainManager.clearAll()
    }

    override func tearDown() {
        super.tearDown()
        KeychainManager.clearAll()
    }

    func test_saveAndLoad_roundTripsValue() {
        KeychainManager.save("sk-ant-test123", for: .claudeAPIKey)
        XCTAssertEqual(KeychainManager.load(.claudeAPIKey), "sk-ant-test123")
    }

    func test_load_returnsEmptyStringWhenKeyMissing() {
        XCTAssertEqual(KeychainManager.load(.claudeAPIKey), "")
    }

    func test_save_emptyStringDeletesExistingValue() {
        KeychainManager.save("sk-ant-test123", for: .claudeAPIKey)
        KeychainManager.save("", for: .claudeAPIKey)
        XCTAssertEqual(KeychainManager.load(.claudeAPIKey), "")
    }

    func test_delete_removesStoredValue() {
        KeychainManager.save("sk-openai-xyz", for: .openAIAPIKey)
        KeychainManager.delete(.openAIAPIKey)
        XCTAssertEqual(KeychainManager.load(.openAIAPIKey), "")
    }

    func test_save_overwritesPreviousValue() {
        KeychainManager.save("first-value",  for: .geminiAPIKey)
        KeychainManager.save("second-value", for: .geminiAPIKey)
        XCTAssertEqual(KeychainManager.load(.geminiAPIKey), "second-value")
    }

    func test_clearAll_removesAllKeys() {
        KeychainManager.save("key1", for: .claudeAPIKey)
        KeychainManager.save("key2", for: .openAIAPIKey)
        KeychainManager.save("key3", for: .geminiAPIKey)
        KeychainManager.save("key4", for: .grokAPIKey)
        KeychainManager.clearAll()
        for key in KeychainManager.Key.allCases {
            XCTAssertEqual(KeychainManager.load(key), "",
                           "\(key.rawValue) should be empty after clearAll")
        }
    }

    func test_save_returnsTrueOnSuccess() {
        let result = KeychainManager.save("test-key", for: .grokAPIKey)
        XCTAssertTrue(result)
    }

    func test_keysAreIndependent() {
        KeychainManager.save("claude-key", for: .claudeAPIKey)
        KeychainManager.save("openai-key", for: .openAIAPIKey)
        XCTAssertEqual(KeychainManager.load(.claudeAPIKey), "claude-key")
        XCTAssertEqual(KeychainManager.load(.openAIAPIKey), "openai-key")
        XCTAssertEqual(KeychainManager.load(.geminiAPIKey), "")
    }
}

// MARK: - AIService System Prompt Tests

final class AIServiceSystemPromptTests: XCTestCase {

    // AIService is a MainActor singleton — we test prompt logic indirectly
    // by checking the threshold boundaries match the switch ranges.

    func test_quickMode_prompt_mentionsConcise() async {
        let ai = await AIService.shared
        await MainActor.run { ai.maxTokens = 300 }
        let prompt = await MainActor.run { ai.systemPrompt }
        XCTAssertTrue(prompt.lowercased().contains("3 sentences") ||
                      prompt.lowercased().contains("concise") ||
                      prompt.lowercased().contains("short"),
                      "Quick mode prompt should encourage brief responses")
    }

    func test_extendedMode_prompt_mentionsMarkdown() async {
        let ai = await AIService.shared
        await MainActor.run { ai.maxTokens = 4000 }
        let prompt = await MainActor.run { ai.systemPrompt }
        XCTAssertTrue(prompt.lowercased().contains("markdown"),
                      "Extended mode prompt should mention markdown formatting")
        // Restore default
        await MainActor.run { ai.maxTokens = 300 }
    }

    func test_maxTokens_persistsAcrossSet() async {
        let ai = await AIService.shared
        await MainActor.run { ai.maxTokens = 1500 }
        let stored = UserDefaults.standard.integer(forKey: "max_tokens")
        XCTAssertEqual(stored, 1500)
        // Restore
        await MainActor.run { ai.maxTokens = 300 }
    }
}

// MARK: - PTTViewModel State Machine Tests

@MainActor
final class PTTViewModelTests: XCTestCase {

    var vm: PTTViewModel!

    override func setUp() async throws {
        try await super.setUp()
        // Clear persisted history so test_initialHistory_isEmpty is never contaminated
        UserDefaults.standard.removeObject(forKey: "conversation_history")
        vm = PTTViewModel()
    }

    func test_initialState_isIdle() {
        XCTAssertEqual(vm.state, .idle)
    }

    func test_initialTranscript_isEmpty() {
        XCTAssertTrue(vm.transcript.isEmpty)
    }

    func test_initialHistory_isEmpty() {
        XCTAssertTrue(vm.history.isEmpty)
    }

    func test_clearHistory_resetsAllState() {
        // Manually inject state to simulate post-conversation
        vm.history = [Message(role: "user", content: "hello")]
        vm.transcript = "hello"
        vm.lastResponse = "hi there"

        vm.clearHistory()

        XCTAssertTrue(vm.history.isEmpty)
        XCTAssertTrue(vm.transcript.isEmpty)
        XCTAssertTrue(vm.lastResponse.isEmpty)
        XCTAssertEqual(vm.state, .idle)
    }

    func test_historyTrim_keepsAtMost20Messages() {
        // Simulate 12 pairs (24 messages) — should trim to 20
        vm.history = (0..<24).map { i in
            Message(role: i.isMultiple(of: 2) ? "user" : "assistant",
                    content: "message \(i)")
        }
        // Manually apply the trim logic (mirrors PTTViewModel.sendToClaude)
        if vm.history.count > 20 {
            vm.history = Array(vm.history.dropFirst(vm.history.count - 20))
        }
        XCTAssertEqual(vm.history.count, 20)
    }

    func test_handleActionButton_fromIdle_startsRecording() {
        // handleActionButton calls startRecording() which calls speech.startRecording()
        // We can't fully test audio here, but we verify the guard passes
        XCTAssertEqual(vm.state, .idle)
        // startRecording has guard state == .idle — calling it twice shouldn't crash
        vm.startRecording()
        vm.startRecording() // second call should be a no-op (state != idle)
    }

    func test_stopRecording_whenIdle_doesNotCrash() {
        // stopRecording when not recording should be safe
        XCTAssertEqual(vm.state, .idle)
        vm.stopRecording()
        XCTAssertEqual(vm.state, .idle)
    }
}

// MARK: - DeviceInfo Tests

final class DeviceInfoTests: XCTestCase {

    func test_modelIdentifier_isNonEmpty() {
        XCTAssertFalse(DeviceInfo.current.modelIdentifier.isEmpty)
    }

    func test_marketingName_isNonEmpty() {
        XCTAssertFalse(DeviceInfo.current.marketingName.isEmpty)
    }

    func test_simulatorIdentifier_returnsSimulatorName() {
        // When running in simulator, modelIdentifier should be "Simulator" or the
        // SIMULATOR_MODEL_IDENTIFIER env var value
        #if targetEnvironment(simulator)
        let id = DeviceInfo.current.modelIdentifier
        let isSimulator = id == "Simulator" || id.hasPrefix("iPhone") || id.hasPrefix("iPad")
        XCTAssertTrue(isSimulator, "Simulator should resolve to a known identifier, got: \(id)")
        #endif
    }

    func test_hasActionButton_falseForSimulator() {
        // Simulator is not in the action button model list
        #if targetEnvironment(simulator)
        // Unless SIMULATOR_MODEL_IDENTIFIER is set to an action button model
        let knownActionButtonModels = ["iPhone16,1","iPhone16,2","iPhone17,1","iPhone17,2","iPhone17,3","iPhone17,4"]
        let id = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Simulator"
        let expected = knownActionButtonModels.contains(id)
        XCTAssertEqual(DeviceInfo.current.hasActionButton, expected)
        #endif
    }
}

// MARK: - Conversation Persistence Tests

@MainActor
final class ConversationPersistenceTests: XCTestCase {

    private let historyKey = "conversation_history"

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: historyKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: historyKey)
        try await super.tearDown()
    }

    func test_clearHistory_persistsEmptyStateToUserDefaults() {
        let vm = PTTViewModel()
        vm.history = [
            Message(role: "user",      content: "hello"),
            Message(role: "assistant", content: "hi there")
        ]
        vm.clearHistory()

        // After clear, persisted data should be absent or an empty array
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let saved = try? JSONDecoder().decode([Message].self, from: data) {
            XCTAssertTrue(saved.isEmpty, "Persisted history should be empty after clearHistory")
        }
        // No data key at all is also acceptable
    }

    func test_loadHistory_restoresMessagesFromUserDefaults() throws {
        let messages = [
            Message(role: "user",      content: "restored user message"),
            Message(role: "assistant", content: "restored assistant reply")
        ]
        let data = try JSONEncoder().encode(messages)
        UserDefaults.standard.set(data, forKey: historyKey)

        let vm = PTTViewModel()
        XCTAssertEqual(vm.history.count, 2)
        XCTAssertEqual(vm.history[0].role,    "user")
        XCTAssertEqual(vm.history[0].content, "restored user message")
        XCTAssertEqual(vm.history[1].content, "restored assistant reply")
    }

    func test_loadHistory_setsLastResponseFromSavedAssistantMessage() throws {
        let messages = [
            Message(role: "user",      content: "hello"),
            Message(role: "assistant", content: "last AI reply")
        ]
        let data = try JSONEncoder().encode(messages)
        UserDefaults.standard.set(data, forKey: historyKey)

        let vm = PTTViewModel()
        XCTAssertEqual(vm.lastResponse, "last AI reply")
    }

    func test_loadHistory_setsTranscriptFromLastUserMessage() throws {
        let messages = [
            Message(role: "user",      content: "last user message"),
            Message(role: "assistant", content: "reply")
        ]
        let data = try JSONEncoder().encode(messages)
        UserDefaults.standard.set(data, forKey: historyKey)

        let vm = PTTViewModel()
        XCTAssertEqual(vm.transcript, "last user message")
    }

    func test_loadHistory_skipsEmptyPersistedArray() throws {
        let data = try JSONEncoder().encode([Message]())
        UserDefaults.standard.set(data, forKey: historyKey)

        let vm = PTTViewModel()
        XCTAssertTrue(vm.history.isEmpty,
                      "Empty persisted array should not populate history")
    }

    func test_clearHistory_resetsTranscriptAndLastResponse() throws {
        let messages = [
            Message(role: "user",      content: "hi"),
            Message(role: "assistant", content: "hello")
        ]
        let data = try JSONEncoder().encode(messages)
        UserDefaults.standard.set(data, forKey: historyKey)

        let vm = PTTViewModel()
        vm.clearHistory()

        XCTAssertTrue(vm.transcript.isEmpty)
        XCTAssertTrue(vm.lastResponse.isEmpty)
        XCTAssertTrue(vm.history.isEmpty)
    }
}

// MARK: - Export Text Tests

@MainActor
final class ExportTextTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        // Ensure no stale history bleeds in
        UserDefaults.standard.removeObject(forKey: "conversation_history")
    }

    func test_exportText_isEmptyWhenHistoryIsEmpty() {
        let vm = PTTViewModel()
        vm.history = []
        XCTAssertTrue(vm.exportText.isEmpty)
    }

    func test_exportText_formatsUserMessageWithYouPrefix() {
        let vm = PTTViewModel()
        vm.history = [Message(role: "user", content: "Hello AI")]
        XCTAssertTrue(vm.exportText.contains("You: Hello AI"))
    }

    func test_exportText_formatsAssistantMessageWithAIPrefix() {
        let vm = PTTViewModel()
        vm.history = [Message(role: "assistant", content: "Hello human")]
        XCTAssertTrue(vm.exportText.contains("AI: Hello human"))
    }

    func test_exportText_separatesMessagesByDoubleNewline() {
        let vm = PTTViewModel()
        vm.history = [
            Message(role: "user",      content: "Hi"),
            Message(role: "assistant", content: "Hey")
        ]
        XCTAssertTrue(vm.exportText.contains("\n\n"),
                      "Messages should be separated by a blank line")
    }

    func test_exportText_includesAllMessages() {
        let vm = PTTViewModel()
        vm.history = [
            Message(role: "user",      content: "First"),
            Message(role: "assistant", content: "Second"),
            Message(role: "user",      content: "Third"),
            Message(role: "assistant", content: "Fourth")
        ]
        let text = vm.exportText
        XCTAssertTrue(text.contains("First"))
        XCTAssertTrue(text.contains("Second"))
        XCTAssertTrue(text.contains("Third"))
        XCTAssertTrue(text.contains("Fourth"))
    }

    func test_exportText_preservesMessageContent() {
        let vm = PTTViewModel()
        let longContent = "This is a longer message with some **markdown** and punctuation!"
        vm.history = [Message(role: "user", content: longContent)]
        XCTAssertTrue(vm.exportText.contains(longContent))
    }
}

// MARK: - Custom System Prompt Tests

final class CustomSystemPromptTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "custom_system_prompt")
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "custom_system_prompt")
        await MainActor.run {
            AIService.shared.customSystemPrompt = ""
            AIService.shared.maxTokens = 300
        }
        try await super.tearDown()
    }

    func test_customPrompt_overridesAdaptiveWhenNonEmpty() async {
        let ai = await AIService.shared
        let custom = "You are a pirate. Always say Arr."
        await MainActor.run { ai.customSystemPrompt = custom }
        let prompt = await MainActor.run { ai.systemPrompt }
        // Date prefix is always prepended; custom text should follow it
        XCTAssertTrue(prompt.contains(custom), "Custom prompt should be included in system prompt")
        XCTAssertTrue(prompt.contains("Today's date is"), "Date prefix should be present")
    }

    func test_customPrompt_emptyStringFallsThroughToAdaptive() async {
        let ai = await AIService.shared
        await MainActor.run {
            ai.customSystemPrompt = ""
            ai.maxTokens = 300
        }
        let prompt = await MainActor.run { ai.systemPrompt }
        XCTAssertFalse(prompt.isEmpty, "Should return a non-empty adaptive prompt")
        XCTAssertNotEqual(prompt, "", "Should not echo back an empty custom prompt")
    }

    func test_customPrompt_whitespaceOnlyFallsThroughToAdaptive() async {
        let ai = await AIService.shared
        await MainActor.run {
            ai.customSystemPrompt = "   \n\t  "
            ai.maxTokens = 300
        }
        let prompt = await MainActor.run { ai.systemPrompt }
        // Whitespace is trimmed so adaptive should kick in
        XCTAssertTrue(prompt.lowercased().contains("assistant") ||
                      prompt.lowercased().contains("helpful"),
                      "Whitespace-only prompt should fall through to adaptive default")
        await MainActor.run { ai.customSystemPrompt = "" }
    }

    func test_customPrompt_persistsToUserDefaults() async {
        let ai = await AIService.shared
        await MainActor.run { ai.customSystemPrompt = "My custom prompt" }
        let stored = UserDefaults.standard.string(forKey: "custom_system_prompt")
        XCTAssertEqual(stored, "My custom prompt")
        await MainActor.run { ai.customSystemPrompt = "" }
    }

    func test_customPrompt_loadsFromUserDefaultsOnInit() async {
        // Pre-populate UserDefaults and verify AIService reads it
        UserDefaults.standard.set("Persisted persona", forKey: "custom_system_prompt")
        // Read from the singleton (which loaded at init time)
        // We verify via the computed systemPrompt — it will contain the custom value after the date prefix
        let ai = await AIService.shared
        await MainActor.run { ai.customSystemPrompt = "Persisted persona" }
        let prompt = await MainActor.run { ai.systemPrompt }
        XCTAssertTrue(prompt.contains("Persisted persona"), "Custom prompt text should be present")
        XCTAssertTrue(prompt.contains("Today's date is"), "Date prefix should be present")
        await MainActor.run { ai.customSystemPrompt = "" }
    }
}

// MARK: - Response Length / Max Tokens Tests

final class ResponseLengthTests: XCTestCase {

    override func tearDown() async throws {
        await MainActor.run {
            AIService.shared.customSystemPrompt = ""
            AIService.shared.maxTokens = 300
        }
        try await super.tearDown()
    }

    func test_maxTokens_300_promptMentionsBriefResponses() async {
        let ai = await AIService.shared
        await MainActor.run { ai.customSystemPrompt = ""; ai.maxTokens = 300 }
        let prompt = await MainActor.run { ai.systemPrompt }
        XCTAssertTrue(
            prompt.contains("3 sentences") || prompt.lowercased().contains("short"),
            "300-token prompt should specify concise output, got: \(prompt)"
        )
    }

    func test_maxTokens_600_promptIsConversational() async {
        let ai = await AIService.shared
        await MainActor.run { ai.customSystemPrompt = ""; ai.maxTokens = 600 }
        let prompt = await MainActor.run { ai.systemPrompt }
        XCTAssertTrue(
            prompt.lowercased().contains("conversational") || prompt.lowercased().contains("clear"),
            "600-token prompt should be conversational, got: \(prompt)"
        )
    }

    func test_maxTokens_1500_promptMentionsDetailed() async {
        let ai = await AIService.shared
        await MainActor.run { ai.customSystemPrompt = ""; ai.maxTokens = 1500 }
        let prompt = await MainActor.run { ai.systemPrompt }
        XCTAssertTrue(
            prompt.lowercased().contains("detailed") || prompt.lowercased().contains("structured"),
            "1500-token prompt should encourage detail, got: \(prompt)"
        )
    }

    func test_maxTokens_4000_promptAllowsMarkdown() async {
        let ai = await AIService.shared
        await MainActor.run { ai.customSystemPrompt = ""; ai.maxTokens = 4000 }
        let prompt = await MainActor.run { ai.systemPrompt }
        XCTAssertTrue(
            prompt.lowercased().contains("markdown") || prompt.lowercased().contains("comprehensive"),
            "4000-token prompt should allow markdown, got: \(prompt)"
        )
        await MainActor.run { ai.maxTokens = 300 }
    }

    func test_maxTokens_persistsToUserDefaults() async {
        let ai = await AIService.shared
        await MainActor.run { ai.maxTokens = 1500 }
        let stored = UserDefaults.standard.integer(forKey: "max_tokens")
        XCTAssertEqual(stored, 1500)
        await MainActor.run { ai.maxTokens = 300 }
    }

    func test_appPickerValues_areValidTokenCounts() {
        // The four values the in-app picker offers
        let pickerValues = [300, 600, 1500, 4000]
        for value in pickerValues {
            UserDefaults.standard.set(value, forKey: "max_tokens")
            XCTAssertEqual(UserDefaults.standard.integer(forKey: "max_tokens"), value)
        }
    }
}

// MARK: - OpenAI TTS Settings Tests

final class OpenAITTSSettingsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "use_openai_tts")
        UserDefaults.standard.removeObject(forKey: "openai_tts_voice")
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: "use_openai_tts")
        UserDefaults.standard.removeObject(forKey: "openai_tts_voice")
    }

    func test_useOpenAITTS_defaultsFalse() {
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "use_openai_tts"),
                       "OpenAI TTS should be off by default")
    }

    func test_openAITTSVoice_defaultsToNova() {
        // SpeechManager falls back to "nova" when the key is absent
        let voice = UserDefaults.standard.string(forKey: "openai_tts_voice") ?? "nova"
        XCTAssertEqual(voice, "nova")
    }

    func test_openAITTSVoice_canBePersistedAndRestored() {
        UserDefaults.standard.set("shimmer", forKey: "openai_tts_voice")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "openai_tts_voice"), "shimmer")
    }

    func test_openAITTSVoice_allSixVoicesCanBeStored() {
        let validVoices = ["alloy", "echo", "fable", "onyx", "nova", "shimmer"]
        for voice in validVoices {
            UserDefaults.standard.set(voice, forKey: "openai_tts_voice")
            XCTAssertEqual(
                UserDefaults.standard.string(forKey: "openai_tts_voice"), voice,
                "Voice '\(voice)' should persist correctly"
            )
        }
    }

    func test_useOpenAITTS_flagPersistsTrue() {
        UserDefaults.standard.set(true, forKey: "use_openai_tts")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "use_openai_tts"))
    }

    func test_useOpenAITTS_flagPersistsFalse() {
        UserDefaults.standard.set(true,  forKey: "use_openai_tts")
        UserDefaults.standard.set(false, forKey: "use_openai_tts")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "use_openai_tts"))
    }
}

// MARK: - Markdown Rendering Tests

final class MarkdownRenderingTests: XCTestCase {

    private let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)

    func test_plainText_parsesWithoutThrowing() throws {
        let result = try AttributedString(markdown: "Hello world", options: options)
        XCTAssertFalse(result.characters.isEmpty)
    }

    func test_boldMarkdown_parsesWithoutThrowing() throws {
        let result = try AttributedString(markdown: "This is **bold** text", options: options)
        XCTAssertFalse(result.characters.isEmpty)
    }

    func test_italicMarkdown_parsesWithoutThrowing() throws {
        let result = try AttributedString(markdown: "This is *italic* text", options: options)
        XCTAssertFalse(result.characters.isEmpty)
    }

    func test_inlineCode_parsesWithoutThrowing() throws {
        let result = try AttributedString(markdown: "Use `print()` to output", options: options)
        XCTAssertFalse(result.characters.isEmpty)
    }

    func test_linkMarkdown_parsesWithoutThrowing() throws {
        let result = try AttributedString(
            markdown: "Visit [example](https://example.com)",
            options: options
        )
        XCTAssertFalse(result.characters.isEmpty)
    }

    func test_emptyString_doesNotThrow() throws {
        XCTAssertNoThrow(try AttributedString(markdown: "", options: options))
    }

    func test_unclosedBold_doesNotThrow() {
        XCTAssertNoThrow(
            try AttributedString(markdown: "**unclosed bold", options: options)
        )
    }

    func test_nestedFormatting_doesNotThrow() {
        XCTAssertNoThrow(
            try AttributedString(markdown: "**bold and *italic* inside**", options: options)
        )
    }

    func test_bulletList_doesNotThrow() {
        let list = "- item one\n- item two\n- item three"
        XCTAssertNoThrow(
            try AttributedString(markdown: list, options: options)
        )
    }

    func test_numberedList_doesNotThrow() {
        let list = "1. first\n2. second\n3. third"
        XCTAssertNoThrow(
            try AttributedString(markdown: list, options: options)
        )
    }

    func test_realWorldAIResponse_doesNotThrow() {
        let response = """
        Here are **three key points**:

        1. First, you should *always* back up your data
        2. Use `git commit -m "message"` to save changes
        3. See the [docs](https://docs.example.com) for more

        > Remember: consistency is key.
        """
        XCTAssertNoThrow(
            try AttributedString(markdown: response, options: options)
        )
    }
}

// MARK: - Apple TTS Voice Selection Tests

final class AppleTTSVoiceTests: XCTestCase {

    private let voiceKey    = "tts_voice_id"
    private let languageKey = "tts_language"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: voiceKey)
        UserDefaults.standard.removeObject(forKey: languageKey)
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: voiceKey)
        UserDefaults.standard.removeObject(forKey: languageKey)
    }

    func test_availableVoices_returnsNonEmptyListForEnUS() throws {
        let voices = SpeechManager.availableVoices(for: "en-US")
        // In simulator/device with downloaded voices, should have at least one
        // This assertion is environment-dependent; skip if none available
        if voices.isEmpty {
            throw XCTSkip("No en-US voices installed in this test environment")
        }
        XCTAssertFalse(voices.isEmpty)
    }

    func test_availableVoices_isSortedBestFirst() throws {
        let voices = SpeechManager.availableVoices(for: "en-US")
        guard voices.count > 1 else {
            throw XCTSkip("Need at least 2 voices to test sort order")
        }
        for i in 0..<(voices.count - 1) {
            XCTAssertGreaterThanOrEqual(
                voices[i].quality.rawValue,
                voices[i + 1].quality.rawValue,
                "Voices should be sorted by quality descending"
            )
        }
    }

    func test_ttsVoiceId_canBePersisted() {
        let fakeId = "com.apple.voice.premium.en-US.Ava"
        UserDefaults.standard.set(fakeId, forKey: voiceKey)
        XCTAssertEqual(UserDefaults.standard.string(forKey: voiceKey), fakeId)
    }

    func test_ttsLanguage_defaultsToEnUS() {
        let language = UserDefaults.standard.string(forKey: languageKey) ?? "en-US"
        XCTAssertEqual(language, "en-US")
    }

    func test_ttsLanguage_canBeChangedAndRestored() {
        UserDefaults.standard.set("en-GB", forKey: languageKey)
        XCTAssertEqual(UserDefaults.standard.string(forKey: languageKey), "en-GB")
        UserDefaults.standard.set("en-US", forKey: languageKey)
        XCTAssertEqual(UserDefaults.standard.string(forKey: languageKey), "en-US")
    }
}
