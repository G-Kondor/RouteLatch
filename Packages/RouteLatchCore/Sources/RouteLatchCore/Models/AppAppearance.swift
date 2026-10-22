import Foundation

/// The appearance selected on iPhone. `system` means the phone's current light or dark setting.
public enum AppAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public static let storageKey = "RouteLatch.appearance"
    public static let resolvedStorageKey = "RouteLatch.appearanceResolvedPhone"
    public static let preferenceContextKey = "RouteLatch.appearancePreference"
    public static let resolvedContextKey = "RouteLatch.appearanceResolved"

    public var id: String { rawValue }

    public static func stored(_ rawValue: String) -> AppAppearance {
        AppAppearance(rawValue: rawValue) ?? .system
    }
}

/// Light or dark as it should appear after the phone selection is applied.
public enum ResolvedAppearance: String, Codable, Sendable {
    case light
    case dark

    /// `system` follows the iPhone's current scheme. Light and dark stay fixed.
    public static func matching(preference: AppAppearance, phoneScheme: ResolvedAppearance) -> ResolvedAppearance {
        switch preference {
        case .system:
            phoneScheme
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

public struct AppearanceSnapshot: Equatable, Sendable {
    public let preference: AppAppearance
    public let resolved: ResolvedAppearance

    public init(preference: AppAppearance, resolved: ResolvedAppearance) {
        self.preference = preference
        self.resolved = resolved
    }
}

public enum AppearanceSync {
    public static let requestKey = "RouteLatch.appearanceRequest"

    public static func isRequest(_ message: [String: Any]) -> Bool {
        message[requestKey] as? String != nil
    }

    public static func payload(preference: AppAppearance, resolved: ResolvedAppearance) -> [String: String] {
        [
            AppAppearance.preferenceContextKey: preference.rawValue,
            AppAppearance.resolvedContextKey: resolved.rawValue
        ]
    }

    public static func snapshot(from context: [String: Any]) -> AppearanceSnapshot? {
        guard let preferenceRaw = context[AppAppearance.preferenceContextKey] as? String,
              let preference = AppAppearance(rawValue: preferenceRaw),
              let resolvedRaw = context[AppAppearance.resolvedContextKey] as? String,
              let resolved = ResolvedAppearance(rawValue: resolvedRaw) else { return nil }
        return AppearanceSnapshot(preference: preference, resolved: resolved)
    }
}
