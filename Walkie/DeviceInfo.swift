// DeviceInfo.swift
// Detects device model and Action Button capability automatically.
// No user input needed — we read the hardware identifier at runtime.

import UIKit

struct DeviceInfo {

    // MARK: - Singleton

    static let current = DeviceInfo()

    // MARK: - Properties

    let modelIdentifier: String   // e.g. "iPhone17,1"
    let marketingName: String     // e.g. "iPhone 16 Pro"
    let hasActionButton: Bool

    // MARK: - Init

    private init() {
        modelIdentifier = DeviceInfo.getModelIdentifier()
        marketingName   = DeviceInfo.resolveMarketingName(modelIdentifier)
        hasActionButton = DeviceInfo.actionButtonModels.contains(modelIdentifier)
    }

    // MARK: - Action Button model list
    // Action Button introduced: iPhone 15 Pro / Pro Max
    // Available on all iPhone 16 models

    private static let actionButtonModels: Set<String> = [
        // iPhone 15 Pro / Pro Max
        "iPhone16,1",
        "iPhone16,2",
        // iPhone 16
        "iPhone17,3",
        "iPhone17,4",
        // iPhone 16 Pro / Pro Max
        "iPhone17,1",
        "iPhone17,2",
    ]

    // MARK: - Hardware identifier

    private static func getModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children
            .compactMap { $0.value as? Int8 }
            .filter { $0 != 0 }
            .map { String(UnicodeScalar(UInt8(bitPattern: $0))) }
            .joined()
        // Simulator override
        if identifier == "x86_64" || identifier == "arm64" {
            return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]
                ?? "Simulator"
        }
        return identifier
    }

    // MARK: - Human-readable names

    private static func resolveMarketingName(_ id: String) -> String {
        let names: [String: String] = [
            // iPhone 16 family
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            // iPhone 15 family
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone16,3": "iPhone 15",
            "iPhone16,4": "iPhone 15 Plus",
            // iPhone 14
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone15,4": "iPhone 14",
            "iPhone15,5": "iPhone 14 Plus",
            // iPhone 13
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            // iPhone 12
            "iPhone13,1": "iPhone 12 mini",
            "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",
            // Simulator
            "Simulator":  "Simulator",
        ]
        return names[id] ?? "iPhone (\(id))"
    }
}
