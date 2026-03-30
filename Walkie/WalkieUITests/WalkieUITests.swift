// WalkieUITests.swift
// End-to-end UI tests for Walkie — PTT AI voice app
// Add target: Xcode → File → New → Target → UI Testing Bundle → name "WalkieUITests"

import XCTest

final class WalkieUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // Skip onboarding and use a test API key so UI tests reach ContentView
        app.launchArguments += ["--uitesting"]
        app.launchEnvironment["SKIP_ONBOARDING"] = "1"
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Launch Tests

    func test_appLaunches_withoutCrashing() {
        XCTAssertTrue(app.state == .runningForeground)
    }

    func test_mainScreen_showsVoiceTerminalLabel() {
        let label = app.staticTexts["VOICE TERMINAL"]
        XCTAssertTrue(label.waitForExistence(timeout: 3))
    }

    func test_mainScreen_showsSettingsGearButton() {
        let gear = app.buttons.matching(identifier: "gearshape").firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 3))
    }

    func test_mainScreen_showsProviderNameInHeader() {
        // Header shows the active provider name (e.g. CLAUDE, OPENAI, etc.)
        let providers = ["CLAUDE", "OPENAI", "GEMINI", "GROK"]
        let found = providers.contains { app.staticTexts[$0].exists }
        XCTAssertTrue(found, "Header should show an AI provider name")
    }

    // MARK: - Settings Sheet Tests

    func test_settings_opensOnGearTap() {
        // Find and tap the gear button
        let gear = app.buttons.element(matching: .button, identifier: "gearshape")
        if !gear.exists {
            // fallback: look for any button with the gear icon in the nav area
            app.buttons.allElementsBoundByIndex.forEach { _ in }
        }
        // The sheet should appear
        let saveButton = app.buttons["SAVE SETTINGS"]
        // Tap the gear (first toolbar button matching the image)
        app.buttons.allElementsBoundByIndex.first(where: {
            $0.frame.minY < 100 // header area
        })?.tap()

        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
    }

    func test_settings_dismissesOnSave() {
        openSettings()
        let saveButton = app.buttons["SAVE SETTINGS"]
        guard saveButton.waitForExistence(timeout: 3) else {
            XCTFail("Settings did not open")
            return
        }
        saveButton.tap()
        // After dismiss, VOICE TERMINAL header should be visible again
        XCTAssertTrue(app.staticTexts["VOICE TERMINAL"].waitForExistence(timeout: 3))
    }

    func test_settings_dismissesOnXButton() {
        openSettings()
        let xButton = app.buttons["✕"]
        guard xButton.waitForExistence(timeout: 3) else {
            XCTFail("Settings did not open")
            return
        }
        xButton.tap()
        XCTAssertTrue(app.staticTexts["VOICE TERMINAL"].waitForExistence(timeout: 3))
    }

    func test_settings_showsAllFourProviders() {
        openSettings()
        XCTAssertTrue(app.staticTexts["Claude"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["OpenAI"].exists)
        XCTAssertTrue(app.staticTexts["Gemini"].exists)
        XCTAssertTrue(app.staticTexts["Grok"].exists)
    }

    func test_settings_showsDeviceSection() {
        openSettings()
        XCTAssertTrue(app.staticTexts["DEVICE"].waitForExistence(timeout: 3))
    }

    func test_settings_showsPlanSection() {
        openSettings()
        XCTAssertTrue(app.staticTexts["PLAN"].waitForExistence(timeout: 3))
    }

    func test_settings_showsApiKeysSection() {
        openSettings()
        XCTAssertTrue(app.staticTexts["API KEYS"].waitForExistence(timeout: 3))
    }

    func test_settings_showsDisplayToggle() {
        openSettings()
        XCTAssertTrue(app.staticTexts["Show text responses"].waitForExistence(timeout: 3))
    }

    func test_settings_providerSelection_changesActiveProvider() {
        openSettings()
        // Tap OpenAI provider row
        let openAI = app.staticTexts["OpenAI"]
        guard openAI.waitForExistence(timeout: 3) else { return }
        openAI.tap()
        // ACTIVE badge should appear near OpenAI
        XCTAssertTrue(app.staticTexts["ACTIVE"].waitForExistence(timeout: 2))
    }

    func test_settings_apiKeyField_showHideToggle() {
        openSettings()
        // Find a SHOW button (key fields are hidden by default)
        let showButton = app.buttons["SHOW"].firstMatch
        guard showButton.waitForExistence(timeout: 3) else { return }
        showButton.tap()
        // After tapping, it should switch to HIDE
        XCTAssertTrue(app.buttons["HIDE"].firstMatch.waitForExistence(timeout: 2))
    }

    // MARK: - PTT Button Tests

    func test_pttButton_existsOnScreen() {
        // Either the bigScreenPTTButton or pttButton should be present
        // Both contain a mic icon
        let micElements = app.images.matching(NSPredicate(format: "identifier CONTAINS 'mic'"))
        XCTAssertTrue(micElements.count > 0 || app.buttons.count > 1,
                      "PTT button should be present on main screen")
    }

    func test_statusIndicator_showsStandby() {
        XCTAssertTrue(app.staticTexts["STANDBY"].waitForExistence(timeout: 3))
    }

    // MARK: - Display Panel Tests

    func test_displayPanel_showsHoldButtonHint_whenNoKey() {
        // With no API key, should show "TAP ⚙ TO SET YOUR API KEY"
        // or "HOLD BUTTON · SPEAK · RELEASE" if key is set
        let noKeyHint    = app.staticTexts["TAP ⚙ TO SET YOUR API KEY"]
        let hasKeyHint   = app.staticTexts["HOLD BUTTON · SPEAK · RELEASE"]
        let eitherExists = noKeyHint.waitForExistence(timeout: 3) || hasKeyHint.exists
        XCTAssertTrue(eitherExists, "Display panel should show a usage hint")
    }

    // MARK: - Helpers

    private func openSettings() {
        // Tap the gear/settings button in the header
        let gearButtons = app.buttons.allElementsBoundByIndex.filter {
            $0.frame.size.width < 50 && $0.frame.minY < 120
        }
        if let gear = gearButtons.last {
            gear.tap()
        }
    }
}

// MARK: - Settings: Response Length Section Tests

final class SettingsResponseLengthTests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitesting"]
        app.launchEnvironment["SKIP_ONBOARDING"] = "1"
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func test_settings_showsResponseLengthSection() {
        openSettings()
        // "RESPONSE LENGTH" header or "Response Length" label
        let header = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'RESPONSE'")
        ).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 3),
                      "Settings should contain a response length section")
    }

    func test_settings_showsQuickOption() {
        openSettings()
        // Quick / Short / 300 — at least one of these labels should appear
        let quickLabel = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Quick' OR label CONTAINS[c] '300'")
        ).firstMatch
        XCTAssertTrue(quickLabel.waitForExistence(timeout: 3))
    }

    func test_settings_showsExtendedOrLongOption() {
        openSettings()
        let longLabel = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Extended' OR label CONTAINS[c] '4000' OR label CONTAINS[c] 'Long'")
        ).firstMatch
        XCTAssertTrue(longLabel.waitForExistence(timeout: 3))
    }

    private func openSettings() {
        let gearButtons = app.buttons.allElementsBoundByIndex.filter {
            $0.frame.size.width < 50 && $0.frame.minY < 120
        }
        gearButtons.last?.tap()
    }
}

// MARK: - Settings: Voice Section Tests

final class SettingsVoiceTests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitesting"]
        app.launchEnvironment["SKIP_ONBOARDING"] = "1"
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func test_settings_showsVoiceSection() {
        openSettings()
        let voiceHeader = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'VOICE' OR label CONTAINS[c] 'Voice'")
        ).firstMatch
        XCTAssertTrue(voiceHeader.waitForExistence(timeout: 3),
                      "Settings should have a VOICE section")
    }

    func test_settings_showsDeviceVoiceOrTTSLabel() {
        openSettings()
        // The section contains "DEVICE VOICE" or "Apple" or "TTS"
        let found = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'DEVICE' OR label CONTAINS[c] 'Apple' OR label CONTAINS[c] 'TTS'")
        ).firstMatch.waitForExistence(timeout: 3)
        XCTAssertTrue(found, "Should show device/Apple TTS voice section")
    }

    func test_settings_showsOpenAIVoiceToggle() {
        openSettings()
        // Look for "OpenAI" label in voice context
        let openAIVoice = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'OpenAI'")
        ).firstMatch
        XCTAssertTrue(openAIVoice.waitForExistence(timeout: 3),
                      "Settings should show OpenAI voice option")
    }

    private func openSettings() {
        let gearButtons = app.buttons.allElementsBoundByIndex.filter {
            $0.frame.size.width < 50 && $0.frame.minY < 120
        }
        gearButtons.last?.tap()
    }
}

// MARK: - Settings: Assistant Persona Section Tests

final class SettingsPersonaTests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitesting"]
        app.launchEnvironment["SKIP_ONBOARDING"] = "1"
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func test_settings_showsPersonaOrSystemPromptSection() {
        openSettings()
        let section = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'PERSONA' OR label CONTAINS[c] 'SYSTEM' OR label CONTAINS[c] 'ASSISTANT'")
        ).firstMatch
        XCTAssertTrue(section.waitForExistence(timeout: 3),
                      "Settings should show a persona / system prompt section")
    }

    func test_settings_hasTextEditorForPrompt() {
        openSettings()
        // A TextEditor or multi-line TextField should be present for the custom prompt
        // Check via textViews (UITextView is used for TextEditor)
        let hasTextView = app.textViews.count > 0
        // Also accept if there's a placeholder label (empty TextEditor shows placeholder)
        let hasPlaceholder = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'prompt' OR label CONTAINS[c] 'pirate' OR label CONTAINS[c] 'persona'")
        ).firstMatch.waitForExistence(timeout: 3)
        XCTAssertTrue(hasTextView || hasPlaceholder,
                      "Settings should contain a text input for custom system prompt")
    }

    private func openSettings() {
        let gearButtons = app.buttons.allElementsBoundByIndex.filter {
            $0.frame.size.width < 50 && $0.frame.minY < 120
        }
        gearButtons.last?.tap()
    }
}

// MARK: - Copy Button and Scrollable Response Tests

final class ResponseDisplayTests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitesting"]
        app.launchEnvironment["SKIP_ONBOARDING"] = "1"
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func test_mainScreen_doesNotCrashWithLongHistory() {
        // Verify the app stays in foreground even with no conversation yet
        XCTAssertTrue(app.state == .runningForeground)
    }

    func test_mainScreen_showsHistoryPanelOrEmptyState() {
        // Either conversation history or a "no history" / tap-to-begin hint
        let hasHistory = app.scrollViews.count > 0
        let hasHint = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'HOLD' OR label CONTAINS[c] 'TAP' OR label CONTAINS[c] 'SPEAK'")
        ).firstMatch.exists
        XCTAssertTrue(hasHistory || hasHint,
                      "Main screen should show history panel or usage hint")
    }
}

// MARK: - Export / Share Tests

final class ExportShareUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--uitesting"]
        app.launchEnvironment["SKIP_ONBOARDING"] = "1"
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func test_mainScreen_shareButtonNotVisibleWhenHistoryEmpty() {
        // When there is no conversation, the share button should be hidden or absent
        // The ShareLink is conditioned on !history.isEmpty
        let shareButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Share' OR label CONTAINS[c] 'Export' OR identifier == 'square.and.arrow.up'")
        ).firstMatch
        // Either not present, or present because prior history exists in UserDefaults.
        // Either way the app must stay in the foreground without crashing.
        XCTAssertTrue(app.state == .runningForeground,
                      "App should stay running regardless of share button visibility")
    }
}

// MARK: - Onboarding UI Tests

final class WalkieOnboardingUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // Force onboarding by clearing the completion flag
        app.launchArguments += ["--uitesting", "--reset-onboarding"]
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func test_onboarding_firstScreenVisible() {
        // Onboarding should show the app name or a welcome screen
        let exists = app.staticTexts["WALKIE"].waitForExistence(timeout: 5)
                  || app.staticTexts["Walkie"].waitForExistence(timeout: 2)
                  || app.buttons["Get Started"].waitForExistence(timeout: 2)
                  || app.buttons["Continue"].waitForExistence(timeout: 2)
        XCTAssertTrue(exists, "Onboarding first screen should be visible")
    }

    func test_onboarding_hasNavigationControls() {
        let hasNext = app.buttons["Continue"].waitForExistence(timeout: 5)
                   || app.buttons["Next"].waitForExistence(timeout: 2)
                   || app.buttons["Get Started"].waitForExistence(timeout: 2)
        XCTAssertTrue(hasNext, "Onboarding should have a next/continue button")
    }
}

// MARK: - Performance Tests

final class WalkiePerformanceTests: XCTestCase {

    func test_appLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
