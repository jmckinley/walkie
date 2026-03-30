// PTTViewModel.swift
// Orchestrates the full PTT loop: record → transcribe → Claude → speak

import SwiftUI
import Combine

enum PTTState: Equatable {
    case idle
    case recording
    case thinking
    case speaking
}

@MainActor
final class PTTViewModel: ObservableObject {

    @Published var state: PTTState   = .idle
    @Published var transcript        = ""
    @Published var lastResponse      = ""
    @Published var history: [Message] = []
    @Published var volumeLevel: Float = 0

    private let speech  = SpeechManager.shared
    private let ai      = AIService.shared
    private var cancellables = Set<AnyCancellable>()
    private let historyKey = "conversation_history"

    // Formatted text for the share sheet
    var exportText: String {
        guard !history.isEmpty else { return "" }
        return history.map { msg in
            "\(msg.role == "user" ? "You" : "AI"): \(msg.content)"
        }.joined(separator: "\n\n")
    }

    init() {
        loadHistory()
        // Mirror SpeechManager state into our state
        speech.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] recording in
                guard let self else { return }
                if recording { self.state = .recording }
            }.store(in: &cancellables)

        speech.$isSpeaking
            .receive(on: RunLoop.main)
            .sink { [weak self] speaking in
                guard let self else { return }
                if speaking { self.state = .speaking }
                else if self.state == .speaking { self.state = .idle }
            }.store(in: &cancellables)

        speech.$volumeLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] v in self?.volumeLevel = v }
            .store(in: &cancellables)

        speech.$liveTranscript
            .receive(on: RunLoop.main)
            .sink { [weak self] t in self?.transcript = t }
            .store(in: &cancellables)

        // Listen for Action Button notification
        NotificationCenter.default.publisher(for: .actionButtonPressed)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.handleActionButton() }
            .store(in: &cancellables)
    }

    // MARK: - Action Button handler

    func handleActionButton() {
        switch state {
        case .idle:            startRecording()
        case .recording:       speech.stopRecording()
        case .speaking:        speech.stopSpeaking()
        case .thinking:        break  // Can't interrupt Claude mid-flight
        }
    }

    // MARK: - PTT Controls

    func startRecording() {
        guard state == .idle else { return }
        speech.startRecording { [weak self] finalText in
            guard let self else { return }
            guard !finalText.isEmpty else {
                // Nothing was heard — reset to idle so the button works again
                self.state = .idle
                return
            }
            Task { await self.sendToClaude(finalText) }
        }
    }

    func stopRecording() {
        speech.stopRecording()
    }

    // MARK: - AI call

    private func sendToClaude(_ text: String) async {
        state = .thinking
        transcript = text

        let response = await ai.send(text: text, history: history)

        if let response {
            // Only commit to history on success — keeps history balanced
            history.append(Message(role: "user",      content: text))
            history.append(Message(role: "assistant", content: response.text))
            // Keep history bounded to 20 messages (10 pairs) to avoid context-window overflow
            if history.count > 20 { history = Array(history.dropFirst(history.count - 20)) }
            lastResponse = response.text
            saveHistory()

            if let audioData = response.audioData {
                // Gemini 2.5 Flash native audio — play PCM directly
                speech.playAudio(audioData)
            } else {
                // Claude / OpenAI / Grok — route through SpeechManager (OpenAI TTS or Apple TTS)
                speech.speak(response.text)
            }
        } else {
            // AI failed — leave history unchanged, return to idle
            state = .idle
        }
    }

    // MARK: - Clear session

    func clearHistory() {
        history = []
        transcript = ""
        lastResponse = ""
        state = .idle
        speech.stopSpeaking()
        saveHistory()
    }

    // MARK: - Persistence

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let saved = try? JSONDecoder().decode([Message].self, from: data),
              !saved.isEmpty
        else { return }
        history     = saved
        lastResponse = saved.last(where: { $0.role == "assistant" })?.content ?? ""
        transcript   = saved.last(where: { $0.role == "user" })?.content ?? ""
    }
}
