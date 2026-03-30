// OnboardingView.swift
// 3-screen onboarding for Walkie.
// Shown once on first launch. Explains BYOK, picks a provider, requests permissions.

import SwiftUI
import Speech
import AVFoundation
import UIKit

struct OnboardingView: View {

    @Binding var isComplete: Bool
    @State private var page = 0
    @State private var selectedProvider: AIProvider = .claude
    @State private var apiKey = ""
    @State private var showKey = false
    @State private var permissionGranted = false
    @State private var permissionDenied  = false
    @State private var isRequestingPerms = false

    var body: some View {
        ZStack {
            // Background
            Color(red: 0.05, green: 0.05, blue: 0.08)
                .ignoresSafeArea()

            // Subtle radial glow behind content
            RadialGradient(
                colors: [Color.amber.opacity(0.06), Color.clear],
                center: .center,
                startRadius: 0,
                endRadius: 400
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Page indicator
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Capsule()
                            .fill(i == page ? Color.amber : Color.white.opacity(0.15))
                            .frame(width: i == page ? 20 : 6, height: 6)
                            .animation(.spring(response: 0.4), value: page)
                    }
                }
                .padding(.top, 60)
                .padding(.bottom, 40)

                // Page content
                Group {
                    switch page {
                    case 0:  welcomePage
                    case 1:  providerPage
                    default: permissionsPage
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
                .id(page)  // Forces transition on page change

                Spacer()

                // CTA Button
                ctaButton
                    .padding(.horizontal, 32)
                    .padding(.bottom, 52)
            }
        }
    }

    // MARK: - Page 0: Welcome

    var welcomePage: some View {
        VStack(spacing: 0) {
            // App icon placeholder
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.amber.opacity(0.2), Color.clear],
                            center: .center, startRadius: 0, endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                ZStack {
                    Circle()
                        .fill(Color(red: 0.12, green: 0.10, blue: 0.06))
                        .frame(width: 110, height: 110)
                        .overlay(
                            Circle().stroke(Color.amber.opacity(0.4), lineWidth: 1.5)
                        )
                    Image(systemName: "mic.fill")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundColor(.amber)
                }
            }
            .padding(.bottom, 36)

            Text("WALKIE")
                .font(.system(size: 38, weight: .black, design: .monospaced))
                .foregroundColor(.white)
                .tracking(10)
                .padding(.bottom, 8)

            Text("Your AI. Your voice.\nAny model.")
                .font(.system(size: 16, weight: .light))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.bottom, 48)

            // Feature pills
            VStack(spacing: 10) {
                featurePill("mic.fill",              "Push-to-talk with Action Button")
                featurePill("sparkle",               "Claude, GPT-4o, Gemini, Grok")
                featurePill("key.fill",              "Your keys. Stored securely.")
                featurePill("lock.shield.fill",      "No data ever leaves your device")
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Page 1: Choose provider + enter key

    var providerPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose your AI")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                Text("Enter your API key — it's stored in your iPhone's secure Keychain and never leaves your device.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.45))
                    .lineSpacing(4)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)

            // Provider selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AIProvider.allCases) { provider in
                        providerChip(provider)
                    }
                }
                .padding(.horizontal, 28)
            }
            .padding(.bottom, 20)

            // Key entry
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(selectedProvider.displayName.uppercased() + " API KEY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.amber)
                        .tracking(3)
                    Spacer()
                    if let keyURL = URL(string: "https://\(selectedProvider.consoleURL)") {
                        Link("Get key ↗", destination: keyURL)
                            .font(.system(size: 10))
                            .foregroundColor(.blue.opacity(0.6))
                    }
                }

                HStack {
                    Group {
                        if showKey {
                            TextField(selectedProvider.keyPlaceholder, text: $apiKey)
                        } else {
                            SecureField(selectedProvider.keyPlaceholder, text: $apiKey)
                        }
                    }
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                    Button(showKey ? "HIDE" : "SHOW") {
                        showKey.toggle()
                    }
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.amber.opacity(0.6))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(apiKey.isEmpty
                                        ? Color.white.opacity(0.08)
                                        : Color.amber.opacity(0.4), lineWidth: 1)
                        )
                )

                Text("You can add other providers later in Settings.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Page 2: Permissions

    var permissionsPage: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(permissionGranted
                          ? Color.green.opacity(0.12)
                          : Color.amber.opacity(0.1))
                    .frame(width: 140, height: 140)
                    .animation(.easeInOut, value: permissionGranted)

                Image(systemName: permissionGranted
                      ? "checkmark.circle.fill"
                      : "mic.badge.plus")
                    .font(.system(size: 52, weight: .ultraLight))
                    .foregroundColor(permissionGranted ? .green : .amber)
                    .animation(.spring(response: 0.4), value: permissionGranted)
            }
            .padding(.bottom, 32)

            Text(permissionGranted ? "You're all set." : "One quick thing")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 10)
                .animation(.easeInOut, value: permissionGranted)

            Text(permissionGranted
                 ? "Walkie can hear your voice.\nPress the button below to start talking."
                 : "Walkie needs access to your microphone and speech recognition to transcribe what you say.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
                .animation(.easeInOut, value: permissionGranted)

            if permissionDenied {
                VStack(spacing: 6) {
                    Text("Permissions denied")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.red.opacity(0.8))
                    Text("Go to Settings → Walkie → enable Microphone and Speech Recognition")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.35))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.amber)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 32)
            }
        }
    }

    // MARK: - CTA Button

    var ctaButton: some View {
        Button {
            handleCTA()
        } label: {
            HStack(spacing: 10) {
                if isRequestingPerms {
                    ProgressView()
                        .tint(.black)
                        .scaleEffect(0.8)
                } else {
                    Text(ctaLabel)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .tracking(3)
                }
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(ctaEnabled ? Color.amber : Color.gray.opacity(0.3))
            )
            .animation(.easeInOut(duration: 0.2), value: ctaEnabled)
        }
        .disabled(!ctaEnabled || isRequestingPerms)
    }

    var ctaLabel: String {
        switch page {
        case 0:  return "GET STARTED"
        case 1:  return apiKey.isEmpty ? "SKIP FOR NOW" : "SAVE & CONTINUE"
        default: return permissionGranted ? "START TALKING" : "ALLOW MIC ACCESS"
        }
    }

    var ctaEnabled: Bool {
        if page == 2 && permissionDenied { return false }
        return true
    }

    // MARK: - Actions

    func handleCTA() {
        switch page {
        case 0:
            withAnimation { page = 1 }

        case 1:
            // Save the key for the selected provider
            if !apiKey.isEmpty {
                AIService.shared.activeProvider = selectedProvider
                switch selectedProvider {
                case .claude: AIService.shared.claudeKey = apiKey
                case .openai: AIService.shared.openAIKey = apiKey
                case .gemini: AIService.shared.geminiKey = apiKey
                case .grok:   AIService.shared.grokKey   = apiKey
                }
            }
            withAnimation { page = 2 }

        case 2:
            if permissionGranted {
                completeOnboarding()
            } else {
                requestPermissions()
            }

        default: break
        }
    }

    func requestPermissions() {
        isRequestingPerms = true
        Task {
            // Mic
            let micGranted = await AVAudioApplication.requestRecordPermission()
            // Speech
            let speechGranted = await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { status in
                    cont.resume(returning: status == .authorized)
                }
            }

            await MainActor.run {
                isRequestingPerms = false
                if micGranted && speechGranted {
                    withAnimation { permissionGranted = true }
                    // Auto-advance after a beat
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        completeOnboarding()
                    }
                } else {
                    permissionDenied = true
                }
            }
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarding_complete")
        withAnimation(.easeInOut(duration: 0.4)) {
            isComplete = true
        }
    }

    // MARK: - Sub-views

    func featurePill(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.amber)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
    }

    func providerChip(_ provider: AIProvider) -> some View {
        let isSelected = selectedProvider == provider
        return Button {
            withAnimation(.spring(response: 0.3)) {
                selectedProvider = provider
                apiKey = ""
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: provider.iconName)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .amber : .gray.opacity(0.4))
                Text(provider.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .gray.opacity(0.5))
                Text(provider.subLabel)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(isSelected ? .amber.opacity(0.5) : .gray.opacity(0.25))
                    .tracking(1)
            }
            .frame(width: 80, height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.amber.opacity(0.1) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.amber.opacity(0.5) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
