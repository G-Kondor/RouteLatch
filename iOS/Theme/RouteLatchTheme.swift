import SwiftUI

/// Phone-wide appearance. `system` clears the override so iOS follows the device setting.
enum PhoneAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "RouteLatch.appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static func stored(_ rawValue: String) -> PhoneAppearance {
        PhoneAppearance(rawValue: rawValue) ?? .system
    }
}

enum LatchColor {
    static let canvas = Color("LatchCanvas")
    static let card = Color("LatchCard")
    static let ink = Color("LatchInk")
    static let muted = Color("LatchMuted")
    static let accent = Color("LatchAccent")
    static let onAccent = Color("LatchOnAccent")
    static let accentSoft = Color("LatchAccentSoft")
    static let chip = Color("LatchChip")
}

struct LatchIconBadge: View {
    let systemName: String
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(LatchColor.accent)
            .frame(width: size, height: size)
            .background(LatchColor.accentSoft, in: Circle())
    }
}

private struct LatchCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(LatchColor.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.05), lineWidth: 1)
            )
            .compositingGroup()
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.07), radius: colorScheme == .dark ? 12 : 16, y: 8)
    }
}

private struct LatchScreenModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(LatchColor.canvas.ignoresSafeArea())
    }
}

extension View {
    func latchCard() -> some View {
        modifier(LatchCardModifier())
    }

    func latchScreen() -> some View {
        modifier(LatchScreenModifier())
    }
}
