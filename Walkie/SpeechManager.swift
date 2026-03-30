// SpeechManager.swift
// Handles mic recording, live transcription via SFSpeechRecognizer,
// silence detection to auto-stop, and TTS playback.

import AVFoundation
import Speech
import Combine

@MainActor
final class SpeechManager: NSObject, ObservableObject {

    static let shared = SpeechManager()

    // Published state for UI
    @Published var isRecording    = false
    @Published var isSpeaking     = false
    @Published var liveTranscript = ""
    @Published var volumeLevel: Float = 0

    // Internal
    private var audioEngine        = AVAudioEngine()
    private var recognitionTask:    SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private let speechRecognizer   = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let synthesizer        = AVSpeechSynthesizer()
    private var audioPlayer:        AVAudioPlayer?
    private var silenceTimer:       Timer?
    private let silenceThreshold:   TimeInterval = 2.5
    private var onFinalTranscript:  ((String) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Permissions
    // Uses AVAudioApplication — correct API for iOS 17+ (our minimum target)

    func requestPermissions() async {
        // Microphone — use AVAudioSession which works on all supported iOS versions
        _ = await AVAudioApplication.requestRecordPermission()
        // Speech recognition
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { _ in
                cont.resume()
            }
        }
    }

    // MARK: - Start Recording

    func startRecording(onFinished: @escaping (String) -> Void) {
        guard !isRecording else { return }
        onFinalTranscript = onFinished
        liveTranscript = ""

        do {
            let session = AVAudioSession.sharedInstance()
            // .allowBluetoothA2DP works on all iOS versions; .allowBluetooth deprecated iOS 8
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest else { return }
            recognitionRequest.shouldReportPartialResults = true
            recognitionRequest.taskHint = .dictation

            let inputNode = audioEngine.inputNode

            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) {
                [weak self] result, error in
                guard let self else { return }
                if let result {
                    Task { @MainActor in
                        self.liveTranscript = result.bestTranscription.formattedString
                        self.resetSilenceTimer()
                    }
                }
                // Don't stop on isFinal — iOS's internal silence detection is too
                // aggressive. Let our silence timer control when recording ends so
                // the user has time to pause mid-sentence. Stop only on hard error.
                if let error, (error as NSError).code != 216 {
                    Task { @MainActor in self.stopRecording() }
                }
            }

            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) {
                [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)

                // Volume metering
                guard let channelData = buffer.floatChannelData?[0] else { return }
                let frameCount = Int(buffer.frameLength)
                let rms = (0..<frameCount).reduce(0.0) { $0 + channelData[$1] * channelData[$1] }
                let level = sqrt(rms / Float(frameCount))
                Task { @MainActor [weak self] in
                    self?.volumeLevel = min(level * 30, 1.0)
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            resetSilenceTimer()

        } catch {
            print("[SpeechManager] startRecording failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Stop Recording

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        silenceTimer?.invalidate()
        silenceTimer = nil
        volumeLevel = 0

        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        let finalText = liveTranscript
        // Always invoke — even empty string so the caller can reset state to idle
        onFinalTranscript?(finalText)
        onFinalTranscript = nil
    }

    // MARK: - Silence Detection

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(
            withTimeInterval: silenceThreshold,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopRecording()
            }
        }
    }

    // MARK: - Gemini PCM Audio Playback

    /// Play raw PCM audio returned by Gemini 2.5 Flash TTS.
    /// Wraps the PCM in a WAV header so AVAudioPlayer can decode it.
    func playAudio(_ pcmData: Data) {
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil

        let wavData = pcmToWAV(pcmData)
        do {
            let player = try AVAudioPlayer(data: wavData)
            audioPlayer = player
            player.delegate = self
            isSpeaking = true
            player.prepareToPlay()
            player.play()
        } catch {
            print("[SpeechManager] playAudio failed: \(error.localizedDescription)")
            isSpeaking = false
        }
    }

    /// Build a minimal WAV header around raw signed-16-bit mono PCM at 24 kHz.
    private func pcmToWAV(_ pcmData: Data, sampleRate: UInt32 = 24_000) -> Data {
        let numChannels: UInt16  = 1
        let bitsPerSample: UInt16 = 16
        let byteRate   = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample) / 8
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize   = UInt32(pcmData.count)

        var header = Data()

        func appendLE<T: FixedWidthInteger>(_ v: T) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { header.append(contentsOf: $0) }
        }

        header.append(contentsOf: "RIFF".utf8)
        appendLE(UInt32(36 + dataSize))   // ChunkSize
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        appendLE(UInt32(16))              // Subchunk1Size (PCM)
        appendLE(UInt16(1))              // AudioFormat = PCM
        appendLE(numChannels)
        appendLE(sampleRate)
        appendLE(byteRate)
        appendLE(blockAlign)
        appendLE(bitsPerSample)
        header.append(contentsOf: "data".utf8)
        appendLE(dataSize)

        return header + pcmData
    }

    // MARK: - Text to Speech

    func speak(_ text: String) {
        speak(text, voiceIdentifier: UserDefaults.standard.string(forKey: "tts_voice_id"))
    }

    func speak(_ text: String, voiceIdentifier: String?) {
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil

        let useOpenAI = UserDefaults.standard.bool(forKey: "use_openai_tts")
            && !KeychainManager.load(.openAIAPIKey).isEmpty

        if useOpenAI {
            isSpeaking = true
            Task { await self.speakViaOpenAI(text) }
        } else {
            speakViaApple(text, voiceIdentifier: voiceIdentifier)
        }
    }

    private func speakViaApple(_ text: String, voiceIdentifier: String?) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.0
        utterance.voice = resolveVoice(identifier: voiceIdentifier)
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    private func speakViaOpenAI(_ text: String) async {
        let key   = KeychainManager.load(.openAIAPIKey)
        let voice = UserDefaults.standard.string(forKey: "openai_tts_voice") ?? "nova"
        guard let url = URL(string: "https://api.openai.com/v1/audio/speech") else { return }

        let body: [String: Any] = ["model": "tts-1-hd", "input": text, "voice": voice]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)",    forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                speakViaApple(text, voiceIdentifier: UserDefaults.standard.string(forKey: "tts_voice_id"))
                return
            }
            let player = try AVAudioPlayer(data: data, fileTypeHint: "mp3")
            audioPlayer = player
            player.delegate = self
            player.play()
        } catch {
            speakViaApple(text, voiceIdentifier: UserDefaults.standard.string(forKey: "tts_voice_id"))
        }
    }

    // Returns the best available voice: user pick → premium → enhanced → default
    private func resolveVoice(identifier: String?) -> AVSpeechSynthesisVoice? {
        let language = UserDefaults.standard.string(forKey: "tts_language") ?? "en-US"
        if let id = identifier, let voice = AVSpeechSynthesisVoice(identifier: id) {
            return voice
        }
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        return candidates.first(where: { $0.quality == .premium })
            ?? candidates.first(where: { $0.quality == .enhanced })
            ?? AVSpeechSynthesisVoice(language: language)
    }

    // Returns all voices for the current language sorted by quality (best first)
    static func availableVoices(for language: String = "en-US") -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil
        isSpeaking = false
    }
}

// MARK: - AVAudioPlayerDelegate (OpenAI TTS playback completion)

extension SpeechManager: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
