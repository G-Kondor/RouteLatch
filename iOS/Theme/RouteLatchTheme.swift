import RouteLatchCore
import SwiftUI

extension AppAppearance {
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `system` leaves the override unset so the phone follows its own setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
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
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(LatchColor.card.opacity(colorScheme == .dark ? 0.55 : 0.72))
                    }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.2 : 0.72),
                                Color.white.opacity(colorScheme == .dark ? 0.04 : 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .compositingGroup()
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.07), radius: colorScheme == .dark ? 12 : 16, y: 8)
    }
}

private struct LatchGlassModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat
    var interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            liquidGlass(content)
        } else {
            material(content)
        }
    }

    @available(iOS 26, *)
    private func liquidGlass(_ content: Content) -> some View {
        content.glassEffect(
            interactive ? .regular.interactive() : .regular,
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
    }

    private func material(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.55), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.1), radius: 18, y: 8)
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

    /// Blurred glass for floating controls such as the tab bar. Cards stay a lighter frost.
    func latchGlass(radius: CGFloat = 28, interactive: Bool = false) -> some View {
        modifier(LatchGlassModifier(radius: radius, interactive: interactive))
    }

    func latchNavigationBar() -> some View {
        modifier(LatchNavigationBarModifier())
    }
}

private struct LatchNavigationBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
        } else {
            content
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
