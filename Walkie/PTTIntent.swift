// PTTIntent.swift
// Registers Walkie as an Action Button handler (iOS 17+)
// On device: Settings → Action Button → App Actions → choose "Walkie PTT"

import AppIntents
import UIKit

struct PTTIntent: AppIntent {
    static var title: LocalizedStringResource = "Walkie PTT"
    static var description = IntentDescription("Press Action Button to talk to your AI")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Brief delay so the app UI and PTTViewModel are fully initialized
        // before the notification fires — prevents the first press being silently dropped
        // on a cold launch.
        try await Task.sleep(for: .milliseconds(600))
        NotificationCenter.default.post(name: .actionButtonPressed, object: nil)
        return .result()
    }
}

struct WalkieShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PTTIntent(),
            phrases: [
                "Talk to \(.applicationName)",
                "Ask \(.applicationName)",
                "Open \(.applicationName)",
                "\(.applicationName) PTT"
            ],
            shortTitle: "Walkie PTT",
            systemImageName: "mic.fill"
        )
    }
}

extension Notification.Name {
    static let actionButtonPressed = Notification.Name("actionButtonPressed")
    static let startRecordingNow   = Notification.Name("startRecordingNow")
}
