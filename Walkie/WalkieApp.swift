// WalkieApp.swift
// Entry point for Walkie — AI voice PTT for Claude, GPT-4o, Gemini & Grok.

import SwiftUI
import Speech

@main
struct WalkieApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var onboardingComplete = UserDefaults.standard.bool(forKey: "onboarding_complete")

    var body: some Scene {
        WindowGroup {
            ZStack {
                if onboardingComplete {
                    ContentView()
                        .transition(.opacity)
                } else {
                    OnboardingView(isComplete: $onboardingComplete)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: onboardingComplete)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register Action Button shortcut with the system
        WalkieShortcuts.updateAppShortcutParameters()
        Task {
            // Pre-warm speech recognizer — avoids first-run delay
            _ = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        }
        return true
    }
}

