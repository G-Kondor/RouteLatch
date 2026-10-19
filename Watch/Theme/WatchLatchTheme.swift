import SwiftUI

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
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(LatchColor.accent)
            .frame(width: size, height: size)
            .background(LatchColor.accentSoft, in: Circle())
    }
}

private struct LatchCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(LatchColor.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.06), lineWidth: 1)
            )
    }
}

extension View {
    func latchCard(radius: CGFloat = 18) -> some View {
        modifier(LatchCardModifier(radius: radius))
    }

    func latchScreen() -> some View {
        containerBackground(LatchColor.canvas, for: .navigation)
            .background(LatchColor.canvas)
    }

    func latchTabPage() -> some View {
        containerBackground(LatchColor.canvas, for: .tabView)
            .background(LatchColor.canvas)
    }
}

struct WatchRunButtonStyle: ButtonStyle {
    var fill: Color
    var foreground: Color = LatchColor.onAccent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.7)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(fill.opacity(configuration.isPressed ? 0.72 : 1))
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
