// ContentView.swift
// Tactical walkie-talkie UI.
// - Action Button models: minimal UI, button is mostly decorative
// - Non-Action Button models: full-screen hold-to-talk PTT button is primary

import SwiftUI
import AVFoundation

struct ContentView: View {

    @StateObject private var vm     = PTTViewModel()
    @ObservedObject private var ai  = AIService.shared
    @State private var showSettings = false

    private let device = DeviceInfo.current

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.08)
                .ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Header ──────────────────────────────────────
                header

                // ── Transcript / Response ───────────────────────
                displayPanel
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                // ── Volume bar ──────────────────────────────────
                volumeBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                Spacer()

                // ── Action Button hint OR full PTT button ────────
                if device.hasActionButton {
                    actionButtonHint
                        .padding(.bottom, 20)
                    pttButton
                        .padding(.bottom, 40)
                } else {
                    // Non-Action Button phone: make the on-screen button the hero
                    bigScreenPTTButton
                        .padding(.bottom, 40)
                }

                // ── History scroll ──────────────────────────────
                if !vm.history.isEmpty {
                    historyList
                        .frame(maxHeight: 180)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .task {
            // Request permissions here in case onboarding was skipped or permissions
            // were previously denied and need to be re-prompted.
            await SpeechManager.shared.requestPermissions()
        }
    }

    // MARK: - Action Button hint (shown on supported devices)

    var actionButtonHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "button.programmable.square.fill")
                .font(.system(size: 13))
                .foregroundColor(.amber.opacity(0.7))
            Text("PRESS ACTION BUTTON TO TRANSMIT")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.amber.opacity(0.5))
                .tracking(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.amber.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.amber.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Full-screen PTT button (non-Action Button phones — this IS the primary interaction)

    var bigScreenPTTButton: some View {
        VStack(spacing: 16) {
            ZStack {
                if vm.state == .recording || vm.state == .speaking {
                    PulseRingsView(color: vm.state.color, baseSize: 200)
                }

                Button { } label: {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: vm.state == .recording
                                        ? [Color(red: 0.50, green: 0.18, blue: 0.02),
                                           Color(red: 0.28, green: 0.08, blue: 0.01)]
                                        : vm.state == .speaking
                                        ? [Color(red: 0.04, green: 0.30, blue: 0.22),
                                           Color(red: 0.02, green: 0.14, blue: 0.10)]
                                        : [Color(red: 0.14, green: 0.14, blue: 0.20),
                                           Color(red: 0.07, green: 0.07, blue: 0.12)],
                                    center: .topLeading,
                                    startRadius: 20,
                                    endRadius: 200
                                )
                            )
                            .frame(width: 200, height: 200)
                            .overlay(
                                Circle()
                                    .stroke(vm.state.color, lineWidth: 2)
                                    .shadow(color: vm.state.color.opacity(0.6), radius: 12)
                            )

                        VStack(spacing: 12) {
                            Image(systemName: vm.state == .speaking
                                  ? "speaker.wave.2.fill" : "mic.fill")
                                .font(.system(size: 52, weight: .ultraLight))
                                .foregroundColor(vm.state.color)
                            Text(vm.state.buttonLabel)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(vm.state.color)
                                .tracking(4)
                        }
                    }
                }
                .scaleEffect(vm.state == .recording ? 0.93 : 1.0)
                .animation(.spring(response: 0.18), value: vm.state)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if vm.state == .idle { vm.startRecording() }
                        }
                        .onEnded { _ in
                            if vm.state == .recording { vm.stopRecording() }
                            else if vm.state == .speaking { SpeechManager.shared.stopSpeaking() }
                        }
                )
                .disabled(vm.state == .thinking)
            }

            Text(vm.state == .idle
                 ? "HOLD TO TALK  ·  RELEASE TO SEND"
                 : vm.state == .recording
                 ? "RELEASE OR GO SILENT TO SEND"
                 : vm.state == .thinking
                 ? "\(ai.activeProvider.displayName.uppercased()) IS THINKING..."
                 : "TAP TO INTERRUPT")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(vm.state.color.opacity(0.6))
                .tracking(2)
        }
    }

    // MARK: - Header

    var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ai.activeProvider.displayName.uppercased())
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(.amber)
                        .tracking(5)
                    Image(systemName: ai.activeProvider.iconName)
                        .font(.system(size: 9))
                        .foregroundColor(.amber.opacity(0.5))
                }
                Text("VOICE TERMINAL")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.4))
                    .tracking(4)
            }
            Spacer()
            // Status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(vm.state.color)
                    .frame(width: 7, height: 7)
                    .shadow(color: vm.state.color, radius: 4)
                Text(vm.state.label)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(vm.state.color)
                    .tracking(3)
            }
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundColor(.gray.opacity(0.4))
                    .padding(.leading, 14)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(red: 0.05, green: 0.05, blue: 0.08))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.white.opacity(0.06)),
            alignment: .bottom
        )
    }

    // MARK: - Display Panel

    var displayPanel: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.04, green: 0.04, blue: 0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .frame(minHeight: ai.showTextResponse ? 120 : 80)

            VStack(alignment: .leading, spacing: 10) {
                // Main status / transcript area
                Group {
                    if let err = ai.errorMessage {
                        Text("⚠ \(err)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.red.opacity(0.8))
                    } else if vm.state == .recording {
                        if vm.transcript.isEmpty {
                            blinkText("LISTENING...")
                                .foregroundColor(.amber.opacity(0.5))
                        } else {
                            Text(vm.transcript)
                                .font(.system(size: 14))
                                .foregroundColor(.amber)
                        }
                    } else if vm.state == .thinking {
                        dotsAnimation
                    } else if !vm.lastResponse.isEmpty {
                        // Show voice-only hint or full text
                        if ai.showTextResponse {
                            HStack(alignment: .top, spacing: 8) {
                                ScrollView {
                                    MarkdownResponseView(text: vm.lastResponse)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 260)
                                Button {
                                    UIPasteboard.general.string = vm.lastResponse
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 13))
                                        .foregroundColor(.amber.opacity(0.6))
                                }
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.green.opacity(0.5))
                                Text("RESPONSE RECEIVED")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.green.opacity(0.5))
                                    .tracking(2)
                            }
                        }
                    } else {
                        Text(ai.activeKey.isEmpty
                             ? "TAP ⚙ TO SET YOUR API KEY"
                             : "HOLD BUTTON · SPEAK · RELEASE")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.15))
                            .tracking(2)
                    }
                }

                // Transcript shown below response when text mode on and we have both
                if ai.showTextResponse && !vm.transcript.isEmpty
                    && vm.state != .recording
                    && !vm.lastResponse.isEmpty {
                    Divider().background(Color.white.opacity(0.05))
                    HStack(alignment: .top, spacing: 6) {
                        Text("YOU")
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .foregroundColor(.amber.opacity(0.5))
                            .tracking(2)
                            .padding(.top, 1)
                        Text(vm.transcript)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.35))
                            .lineSpacing(3)
                    }
                }
            }
            .padding(14)
        }
    }

    // MARK: - Volume Bar

    var volumeBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 3)
                Capsule()
                    .fill(LinearGradient(
                        colors: [.amber, .red.opacity(0.8)],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: geo.size.width * CGFloat(vm.volumeLevel), height: 3)
                    .animation(.linear(duration: 0.06), value: vm.volumeLevel)
            }
        }
        .frame(height: 3)
    }

    // MARK: - PTT Button

    var pttButton: some View {
        ZStack {
            // Pulse rings when active
            if vm.state == .recording || vm.state == .speaking {
                PulseRingsView(color: vm.state.color, baseSize: 150)
            }

            // Main button
            Button {
                // Tap: toggle
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: vm.state == .recording
                                    ? [Color(red: 0.45, green: 0.18, blue: 0.04),
                                       Color(red: 0.25, green: 0.08, blue: 0.01)]
                                    : vm.state == .speaking
                                    ? [Color(red: 0.04, green: 0.28, blue: 0.20),
                                       Color(red: 0.02, green: 0.14, blue: 0.10)]
                                    : [Color(red: 0.12, green: 0.12, blue: 0.18),
                                       Color(red: 0.06, green: 0.06, blue: 0.10)],
                                center: .topLeading,
                                startRadius: 10,
                                endRadius: 140
                            )
                        )
                        .frame(width: 148, height: 148)
                        .overlay(
                            Circle()
                                .stroke(vm.state.color, lineWidth: 1.5)
                                .shadow(color: vm.state.color.opacity(0.5), radius: 8)
                        )

                    VStack(spacing: 8) {
                        Image(systemName: vm.state == .speaking ? "speaker.wave.2.fill" : "mic.fill")
                            .font(.system(size: 34, weight: .light))
                            .foregroundColor(vm.state.color)

                        Text(vm.state.buttonLabel)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(vm.state.color)
                            .tracking(3)
                    }
                }
            }
            .scaleEffect(vm.state == .recording ? 0.94 : 1.0)
            .animation(.spring(response: 0.2), value: vm.state)
            // Long press gesture for true PTT feel
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if vm.state == .idle { vm.startRecording() }
                    }
                    .onEnded { _ in
                        if vm.state == .recording { vm.stopRecording() }
                        else if vm.state == .speaking { SpeechManager.shared.stopSpeaking() }
                    }
            )
            .disabled(vm.state == .thinking)
        }
    }

    // MARK: - History

    var historyList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TRANSMISSION LOG")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.15))
                    .tracking(3)
                Spacer()
                if !vm.exportText.isEmpty {
                    ShareLink(item: vm.exportText) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.2))
                    }
                    .padding(.trailing, 8)
                }
                Button("CLEAR") {
                    vm.clearHistory()
                }
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.15))
                .tracking(3)
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(vm.history.reversed()) { msg in
                        HStack(alignment: .top, spacing: 8) {
                            Text(msg.role == "user" ? "YOU" : "AI")
                                .font(.system(size: 7, weight: .black, design: .monospaced))
                                .foregroundColor(
                                    msg.role == "user"
                                    ? .amber.opacity(0.6)
                                    : Color.green.opacity(0.6)
                                )
                                .tracking(2)
                                .frame(width: 26, alignment: .leading)
                                .padding(.top, 2)
                            Text(msg.content)
                                .font(.system(size: 12))
                                .foregroundColor(Color.white.opacity(0.5))
                                .lineSpacing(3)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.03))
                                .overlay(
                                    Rectangle()
                                        .frame(width: 2)
                                        .foregroundColor(
                                            msg.role == "user"
                                            ? .amber.opacity(0.3)
                                            : Color.green.opacity(0.3)
                                        ),
                                    alignment: .leading
                                )
                        )
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    func blinkText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(3)
    }

    var dotsAnimation: some View {
        DotsAnimationView()
    }
}

// Standalone dots animation that owns its own @State trigger.
// Using animation(value:) on a parent state that doesn't change while .thinking
// is active means the animation never fires after first entry. This view solves
// that by toggling its own local @State on appearance.
private struct DotsAnimationView: View {
    @State private var animating = false
    private let letters = Array("PROCESSING")

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<letters.count, id: \.self) { i in
                Text(String(letters[i]))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.blue.opacity(0.8))
                    .opacity(animating ? 1.0 : 0.2)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.07),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
        .onDisappear { animating = false }
    }
}

// Pulse rings that own their own animation trigger — driven by onAppear/onDisappear
// so the animation fires correctly when the state transitions (not value-comparison based).
private struct PulseRingsView: View {
    let color: Color
    let baseSize: CGFloat
    @State private var animating = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(color.opacity(0.35), lineWidth: 1.5)
                    .frame(width: baseSize, height: baseSize)
                    .scaleEffect(animating ? 1.6 : 1.0)
                    .opacity(animating ? 0 : 0.7)
                    .animation(
                        .easeOut(duration: 1.8)
                            .repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.5),
                        value: animating
                    )
            }
        }
        .onAppear  { animating = true  }
        .onDisappear { animating = false }
    }
}

// Renders AI response text with full markdown support — bold, italic, code, bullet lists,
// numbered lists, headers. Falls back to plain text if parsing fails.
private struct MarkdownResponseView: View {
    let text: String
    private let responseColor = Color(red: 0.8, green: 0.8, blue: 0.88)

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full
            )
        ) {
            Text(attributed)
                .font(.system(size: 14))
                .foregroundColor(responseColor)
                .lineSpacing(4)
                .tint(.amber)           // links render in amber
        } else {
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(responseColor)
                .lineSpacing(4)
        }
    }
}

// MARK: - Settings Sheet

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var ai   = AIService.shared
    @ObservedObject private var tier = TierManager.shared

    @State private var claudeKey  = AIService.shared.claudeKey
    @State private var openAIKey  = AIService.shared.openAIKey
    @State private var geminiKey  = AIService.shared.geminiKey
    @State private var grokKey    = AIService.shared.grokKey
    @State private var maxTokens   = AIService.shared.maxTokens
    @State private var selectedVoiceId    = UserDefaults.standard.string(forKey: "tts_voice_id") ?? ""
    @State private var useOpenAITTS       = UserDefaults.standard.bool(forKey: "use_openai_tts")
    @State private var openAITTSVoice     = UserDefaults.standard.string(forKey: "openai_tts_voice") ?? "nova"
    @State private var customSystemPrompt = AIService.shared.customSystemPrompt
    private let availableVoices           = SpeechManager.availableVoices(for: "en-US")
    private let openAIVoices              = ["alloy", "echo", "fable", "onyx", "nova", "shimmer"]
    @State private var showClaude = false
    @State private var showOpenAI = false
    @State private var showGemini = false
    @State private var showGrok   = false

    private let device = DeviceInfo.current

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.08).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {

                        // ── Subscription ─────────────────────────
                        settingsSection(title: "PLAN") {
                            tierCard
                        }
                        settingsSection(title: "DEVICE") {
                            HStack(spacing: 14) {
                                Image(systemName: "iphone")
                                    .font(.system(size: 28, weight: .ultraLight))
                                    .foregroundColor(.amber.opacity(0.7))
                                    .frame(width: 36)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.marketingName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.85))
                                    Text(device.modelIdentifier)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.gray.opacity(0.4))
                                        .tracking(2)
                                }
                                Spacer()
                                VStack(spacing: 3) {
                                    Image(systemName: device.hasActionButton
                                          ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(device.hasActionButton ? .green : .gray.opacity(0.4))
                                    Text("ACTION\nBUTTON")
                                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                                        .foregroundColor(device.hasActionButton
                                                         ? .green.opacity(0.7) : .gray.opacity(0.3))
                                        .multilineTextAlignment(.center)
                                        .tracking(1)
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(device.hasActionButton
                                                    ? Color.amber.opacity(0.2)
                                                    : Color.white.opacity(0.06), lineWidth: 1)
                                    )
                            )
                        }

                        // ── Action Button setup ──────────────────
                        if device.hasActionButton {
                            settingsSection(title: "ACTION BUTTON SETUP") {
                                VStack(alignment: .leading, spacing: 10) {
                                    actionStep("1", "Open  Settings → Action Button")
                                    actionStep("2", "Scroll to  App Actions")
                                    actionStep("3", "Select  Walkie PTT")
                                    actionStep("4", "Press to talk — silence auto-sends")
                                }
                            }
                        } else {
                            settingsSection(title: "PTT MODE") {
                                HStack(spacing: 10) {
                                    Image(systemName: "hand.tap.fill")
                                        .foregroundColor(.amber.opacity(0.6))
                                    Text("Hold the on-screen button to talk. Silence auto-sends, or release early to send immediately.")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray.opacity(0.6))
                                        .lineSpacing(4)
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.03)))
                            }
                        }

                        // ── AI Provider ──────────────────────────
                        settingsSection(title: "AI PROVIDER") {
                            VStack(spacing: 8) {
                                ForEach(AIProvider.allCases) { provider in
                                    providerRow(provider)
                                }
                            }
                        }

                        // ── API Keys ─────────────────────────────
                        settingsSection(title: "API KEYS") {
                            VStack(spacing: 16) {
                                keyField(
                                    label: "CLAUDE  (Anthropic)",
                                    placeholder: AIProvider.claude.keyPlaceholder,
                                    key: $claudeKey, show: $showClaude,
                                    url: AIProvider.claude.consoleURL,
                                    isActive: ai.activeProvider == .claude
                                )
                                Divider().background(Color.white.opacity(0.06))
                                keyField(
                                    label: "OPENAI  (GPT-4o)",
                                    placeholder: AIProvider.openai.keyPlaceholder,
                                    key: $openAIKey, show: $showOpenAI,
                                    url: AIProvider.openai.consoleURL,
                                    isActive: ai.activeProvider == .openai
                                )
                                Divider().background(Color.white.opacity(0.06))
                                keyField(
                                    label: "GEMINI  (Google)",
                                    placeholder: AIProvider.gemini.keyPlaceholder,
                                    key: $geminiKey, show: $showGemini,
                                    url: AIProvider.gemini.consoleURL,
                                    isActive: ai.activeProvider == .gemini
                                )
                                Divider().background(Color.white.opacity(0.06))
                                keyField(
                                    label: "GROK  (xAI)",
                                    placeholder: AIProvider.grok.keyPlaceholder,
                                    key: $grokKey, show: $showGrok,
                                    url: AIProvider.grok.consoleURL,
                                    isActive: ai.activeProvider == .grok
                                )
                            }
                        }

                        // ── Voice ────────────────────────────────
                        settingsSection(title: "VOICE") {
                            VStack(spacing: 0) {
                                ForEach(availableVoices, id: \.identifier) { voice in
                                    Button {
                                        selectedVoiceId = voice.identifier
                                        // Preview the voice immediately
                                        SpeechManager.shared.speak("Hello, I'm \(voice.name).",
                                                                    voiceIdentifier: voice.identifier)
                                    } label: {
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(voice.name)
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(selectedVoiceId == voice.identifier
                                                                     ? .white.opacity(0.9) : .gray.opacity(0.5))
                                                Text(qualityLabel(voice.quality))
                                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                    .foregroundColor(qualityColor(voice.quality))
                                                    .tracking(1)
                                            }
                                            Spacer()
                                            Image(systemName: selectedVoiceId == voice.identifier
                                                  ? "largecircle.fill.circle" : "circle")
                                                .font(.system(size: 20))
                                                .foregroundColor(selectedVoiceId == voice.identifier
                                                                 ? .amber : .gray.opacity(0.3))
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(selectedVoiceId == voice.identifier
                                                    ? Color.amber.opacity(0.07) : Color.clear)
                                    }
                                    .buttonStyle(.plain)
                                    if voice.identifier != availableVoices.last?.identifier {
                                        Divider().background(Color.white.opacity(0.05))
                                            .padding(.leading, 14)
                                    }
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.03))
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.06), lineWidth: 1))
                            )
                            if availableVoices.contains(where: { $0.quality == .premium }) == false {
                                Text("Download Premium voices in Settings → Accessibility → Spoken Content → Voices for the best quality.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray.opacity(0.4))
                                    .lineSpacing(3)
                                    .padding(.top, 4)
                            }
                        }

                        // ── OpenAI TTS (shown only when OpenAI key is set) ──
                        if !openAIKey.isEmpty {
                            settingsSection(title: "OPENAI VOICE") {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("Use OpenAI TTS")
                                                .font(.system(size: 14))
                                                .foregroundColor(.white.opacity(0.75))
                                            Text("Neural quality · tts-1-hd model")
                                                .font(.system(size: 11))
                                                .foregroundColor(.gray.opacity(0.45))
                                        }
                                        Spacer()
                                        Toggle("", isOn: $useOpenAITTS)
                                            .tint(.amber)
                                            .labelsHidden()
                                    }
                                    if useOpenAITTS {
                                        Divider().background(Color.white.opacity(0.06))
                                        Picker("Voice", selection: $openAITTSVoice) {
                                            ForEach(openAIVoices, id: \.self) { v in
                                                Text(v.capitalized).tag(v)
                                            }
                                        }
                                        .pickerStyle(.segmented)
                                        Text("alloy/echo = neutral · fable/onyx = deep · nova/shimmer = bright")
                                            .font(.system(size: 10))
                                            .foregroundColor(.gray.opacity(0.4))
                                            .lineSpacing(2)
                                    }
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.03))
                                        .overlay(RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.06), lineWidth: 1))
                                )
                            }
                        }

                        // ── Custom Prompt ─────────────────────────
                        settingsSection(title: "ASSISTANT PERSONA") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Custom system prompt (overrides default)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray.opacity(0.45))
                                TextEditor(text: $customSystemPrompt)
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.75))
                                    .frame(minHeight: 90)
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.white.opacity(0.04))
                                            .overlay(RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.white.opacity(0.08), lineWidth: 1))
                                    )
                                    .scrollContentBackground(.hidden)
                                if customSystemPrompt.isEmpty {
                                    Text("e.g. \"You are my sous chef. Give concise, practical cooking advice.\"")
                                        .font(.system(size: 10))
                                        .foregroundColor(.gray.opacity(0.35))
                                        .padding(.horizontal, 2)
                                }
                            }
                        }

                        // ── Display ───────────────────────────────
                        settingsSection(title: "DISPLAY") {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Show text responses")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.75))
                                    Text("Display AI reply as text in addition to speaking it")
                                        .font(.system(size: 11))
                                        .foregroundColor(.gray.opacity(0.45))
                                        .lineSpacing(2)
                                }
                                Spacer()
                                Toggle("", isOn: $ai.showTextResponse)
                                    .tint(.amber)
                                    .labelsHidden()
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.03))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                                    )
                            )
                        }

                        // ── Response Length (BYOK only) ───────────
                        if tier.tier == .byok {
                            settingsSection(title: "RESPONSE LENGTH") {
                                VStack(alignment: .leading, spacing: 10) {
                                    Picker("", selection: $maxTokens) {
                                        Text("Quick").tag(300)
                                        Text("Standard").tag(600)
                                        Text("Long").tag(1500)
                                        Text("Extended").tag(4000)
                                    }
                                    .pickerStyle(.segmented)
                                    Text(responseLengthDescription)
                                        .font(.system(size: 10))
                                        .foregroundColor(.gray.opacity(0.5))
                                        .lineSpacing(2)
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.03))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                                        )
                                )
                            }
                        }

                        // ── Save ─────────────────────────────────
                        Button("SAVE SETTINGS") {
                            ai.claudeKey  = claudeKey
                            ai.openAIKey  = openAIKey
                            ai.geminiKey  = geminiKey
                            ai.grokKey    = grokKey
                            ai.maxTokens  = maxTokens
                            UserDefaults.standard.set(
                                selectedVoiceId.isEmpty ? nil : selectedVoiceId,
                                forKey: "tts_voice_id"
                            )
                            UserDefaults.standard.set(useOpenAITTS,   forKey: "use_openai_tts")
                            UserDefaults.standard.set(openAITTSVoice, forKey: "openai_tts_voice")
                            ai.customSystemPrompt = customSystemPrompt
                            // Re-evaluate tier so newly added keys take effect immediately
                            Task { await TierManager.shared.registerAndRefresh() }
                            dismiss()
                        }
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(4)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.amber)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(24)
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("✕") { dismiss() }
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
        }
    }

    // MARK: - Tier Card

    var tierCard: some View {
        VStack(spacing: 10) {
            // Current plan row
            HStack(spacing: 12) {
                Image(systemName: tierIcon)
                    .font(.system(size: 22))
                    .foregroundColor(tierColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(tier.tierDisplayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        if let badge = tier.trialBadge {
                            Text(badge)
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .foregroundColor(tier.trialDaysLeft > 2 ? .amber : .red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    (tier.trialDaysLeft > 2 ? Color.amber : Color.red)
                                        .opacity(0.15)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text(tierSubtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.gray.opacity(0.5))
                }

                Spacer()

                // Usage meter (non-BYOK only)
                if tier.tier != .byok {
                    VStack(spacing: 3) {
                        Text("\(tier.requestsToday)/\(tier.dailyLimit)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(tierColor)
                        Text("today")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.gray.opacity(0.4))
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(tierColor.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(tierColor.opacity(0.2), lineWidth: 1)
                    )
            )

            // Upgrade CTA (shown for trial/expired)
            if tier.tier == .freeTrial || tier.tier == .expired {
                VStack(spacing: 10) {
                    // Annual — hero option
                    Button {
                        // RevenueCat: Purchases.shared.purchase(package: annualPackage)
                        tier.upgradeToAnnual()
                    } label: {
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 12))
                                    Text("WALKIE PRO — ANNUAL")
                                        .font(.system(size: 11, weight: .black, design: .monospaced))
                                        .tracking(1)
                                }
                                Text("200 requests/day · BYOK unlimited")
                                    .font(.system(size: 10))
                                    .opacity(0.75)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("$24.99")
                                    .font(.system(size: 16, weight: .black))
                                Text("per year")
                                    .font(.system(size: 9))
                                    .opacity(0.7)
                            }
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.amber)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            // "BEST VALUE" badge
                            Text("BEST VALUE")
                                .font(.system(size: 7, weight: .black, design: .monospaced))
                                .foregroundColor(.amber)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .padding(8),
                            alignment: .topTrailing
                        )
                    }

                    // Monthly — secondary option
                    Button {
                        // RevenueCat: Purchases.shared.purchase(package: monthlyPackage)
                        tier.upgradeToMonthly()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Monthly")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.7))
                                Text("200 requests/day · BYOK unlimited")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray.opacity(0.5))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("$3.99")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                                Text("per month")
                                    .font(.system(size: 9))
                                    .foregroundColor(.gray.opacity(0.4))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }

                    // Savings callout
                    Text("Annual saves $22.89 vs monthly · ~$2.08/mo")
                        .font(.system(size: 9))
                        .foregroundColor(.amber.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .center)

                    // BYOK escape hatch
                    Text("Or add your own API key below for unlimited access")
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.35))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
            }
        }
    }

    private func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium:  return "PREMIUM"
        case .enhanced: return "ENHANCED"
        default:        return "STANDARD"
        }
    }

    private func qualityColor(_ quality: AVSpeechSynthesisVoiceQuality) -> Color {
        switch quality {
        case .premium:  return .green.opacity(0.8)
        case .enhanced: return .amber.opacity(0.7)
        default:        return .gray.opacity(0.4)
        }
    }

    private var responseLengthDescription: String {
        switch maxTokens {
        case ..<400:   return "Under 3 sentences · voice-optimized"
        case 400..<800: return "A few paragraphs · conversational"
        case 800..<2000: return "Detailed responses · good for lists and explanations"
        default:        return "Full-length · emails, documents, long-form content"
        }
    }

    private var tierIcon: String {
        switch tier.tier {
        case .freeTrial:   return "clock.fill"
        case .paidMonthly: return "crown.fill"
        case .paidAnnual:  return "crown.fill"
        case .byok:        return "key.fill"
        case .expired:     return "xmark.circle.fill"
        }
    }

    private var tierColor: Color {
        switch tier.tier {
        case .freeTrial:   return .amber
        case .paidMonthly: return .green
        case .paidAnnual:  return .green
        case .byok:        return .blue
        case .expired:     return .red
        }
    }

    private var tierSubtitle: String {
        switch tier.tier {
        case .freeTrial:   return "Powered by Gemini Flash · \(tier.dailyLimit) req/day"
        case .paidMonthly: return "Powered by Gemini Flash · \(tier.dailyLimit) req/day"
        case .paidAnnual:  return "Powered by Gemini Flash · \(tier.dailyLimit) req/day · Annual"
        case .byok:        return "Using your \(AIService.shared.activeProvider.displayName) key · Unlimited"
        case .expired:     return "Upgrade to keep talking"
        }
    }

    // MARK: - Provider row

    @ViewBuilder
    func providerRow(_ provider: AIProvider) -> some View {
        let isActive = ai.activeProvider == provider
        let hasKey: Bool = {
            switch provider {
            case .claude: return !claudeKey.isEmpty
            case .openai: return !openAIKey.isEmpty
            case .gemini: return !geminiKey.isEmpty
            case .grok:   return !grokKey.isEmpty
            }
        }()

        Button {
            ai.activeProvider = provider
        } label: {
            HStack(spacing: 12) {
                Image(systemName: provider.iconName)
                    .font(.system(size: 18))
                    .foregroundColor(isActive ? .amber : .gray.opacity(0.35))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(provider.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(isActive ? .white.opacity(0.9) : .gray.opacity(0.5))
                        Text(provider.subLabel)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(isActive ? .amber.opacity(0.45) : .gray.opacity(0.25))
                    }
                    Text(provider.modelLabel)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(isActive ? .amber.opacity(0.4) : .gray.opacity(0.2))
                        .tracking(1)
                }

                Spacer()

                // Key status dot
                Circle()
                    .fill(hasKey ? Color.green : Color.gray.opacity(0.25))
                    .frame(width: 6, height: 6)

                // Active indicator
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isActive ? .amber : .gray.opacity(0.3))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.amber.opacity(0.07) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isActive ? Color.amber.opacity(0.25) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Key field

    @ViewBuilder
    func keyField(
        label: String,
        placeholder: String,
        key: Binding<String>,
        show: Binding<Bool>,
        url: String,
        isActive: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(isActive ? .amber.opacity(0.8) : .gray.opacity(0.4))
                    .tracking(2)
                if isActive {
                    Text("ACTIVE")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .foregroundColor(.amber)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.amber.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .tracking(2)
                }
            }
            HStack {
                Group {
                    if show.wrappedValue {
                        TextField(placeholder, text: key)
                    } else {
                        SecureField(placeholder, text: key)
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.65))
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isActive
                                        ? Color.amber.opacity(0.2)
                                        : Color.white.opacity(0.06), lineWidth: 1)
                        )
                )
                Button(show.wrappedValue ? "HIDE" : "SHOW") {
                    show.wrappedValue.toggle()
                }
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.amber.opacity(0.5))
            }
            if let fullURL = URL(string: "https://\(url)") {
                Link(url, destination: fullURL)
                    .font(.system(size: 10))
                    .foregroundColor(.blue.opacity(0.45))
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.amber)
                .tracking(3)
            content()
        }
    }

    func actionStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.amber.opacity(0.6))
                .frame(width: 14)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.gray.opacity(0.65))
                .lineSpacing(3)
        }
    }
}

// MARK: - Extensions

extension PTTState {
    var color: Color {
        switch self {
        case .idle:      return Color(red: 0.28, green: 0.28, blue: 0.36)
        case .recording: return .amber
        case .thinking:  return .blue
        case .speaking:  return .green
        }
    }
    var label: String {
        switch self {
        case .idle:      return "STANDBY"
        case .recording: return "TRANSMIT"
        case .thinking:  return "PROCESS"
        case .speaking:  return "RECEIVE"
        }
    }
    var buttonLabel: String {
        switch self {
        case .idle:      return "HOLD"
        case .recording: return "RELEASE"
        case .thinking:  return "WAIT"
        case .speaking:  return "SPEAKING"
        }
    }
}

extension Color {
    static let amber = Color(red: 0.96, green: 0.62, blue: 0.04)
}
