import SwiftUI

/// Colors chosen for the appearance selected on iPhone.
/// Named asset colors follow the Watch's own setting, so the phone theme has to be applied directly.
struct LatchColor: Equatable {
    let canvas: Color
    let card: Color
    let ink: Color
    let muted: Color
    let accent: Color
    let onAccent: Color
    let accentSoft: Color
    let chip: Color
    let danger: Color
    let onDanger: Color
    let colorScheme: ColorScheme

    static let light = LatchColor(
        canvas: Color(red: 0.973, green: 0.929, blue: 0.894),
        card: Color(red: 1, green: 1, blue: 1),
        ink: Color(red: 0.110, green: 0.090, blue: 0.078),
        muted: Color(red: 0.345, green: 0.305, blue: 0.275),
        accent: Color(red: 0.640, green: 0.320, blue: 0.069),
        onAccent: Color(red: 1, green: 1, blue: 1),
        accentSoft: Color(red: 1, green: 0.894, blue: 0.816),
        chip: Color(red: 0.965, green: 0.925, blue: 0.886),
        danger: Color(red: 0.706, green: 0.137, blue: 0.094),
        onDanger: Color(red: 1, green: 1, blue: 1),
        colorScheme: .light
    )

    static let dark = LatchColor(
        canvas: Color(red: 0.102, green: 0.078, blue: 0.071),
        card: Color(red: 0.173, green: 0.141, blue: 0.122),
        ink: Color(red: 0.969, green: 0.941, blue: 0.910),
        muted: Color(red: 0.780, green: 0.722, blue: 0.675),
        accent: Color(red: 1, green: 0.545, blue: 0.247),
        onAccent: Color(red: 0.102, green: 0.078, blue: 0.071),
        accentSoft: Color(red: 0.302, green: 0.196, blue: 0.137),
        chip: Color(red: 0.239, green: 0.196, blue: 0.173),
        danger: Color(red: 1, green: 0.541, blue: 0.502),
        onDanger: Color(red: 0.102, green: 0.078, blue: 0.071),
        colorScheme: .dark
    )

    /// `preferred` is the iPhone selection. With none yet, the Watch's own setting is used.
    static func resolved(preferred: ColorScheme?, system: ColorScheme) -> LatchColor {
        switch preferred ?? system {
        case .light:
            .light
        case .dark:
            .dark
        @unknown default:
            .dark
        }
    }
}

private struct LatchColorKey: EnvironmentKey {
    static let defaultValue = LatchColor.dark
}

extension EnvironmentValues {
    var latchColor: LatchColor {
        get { self[LatchColorKey.self] }
        set { self[LatchColorKey.self] = newValue }
    }
}

struct LatchIconBadge: View {
    @Environment(\.latchColor) private var latch
    let systemName: String
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(latch.accent)
            .frame(width: size, height: size)
            .background(latch.accentSoft, in: Circle())
    }
}

private struct LatchCardModifier: ViewModifier {
    @Environment(\.latchColor) private var latch
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(latch.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(latch.colorScheme == .dark ? 0.14 : 0.06), lineWidth: 1)
            )
    }
}

private struct LatchScreenModifier: ViewModifier {
    @Environment(\.latchColor) private var latch

    func body(content: Content) -> some View {
        content
            .containerBackground(latch.canvas, for: .navigation)
            .background(latch.canvas)
            .environment(\.colorScheme, latch.colorScheme)
            .toolbarColorScheme(latch.colorScheme, for: .navigationBar)
    }
}

private struct LatchTabPageModifier: ViewModifier {
    @Environment(\.latchColor) private var latch

    func body(content: Content) -> some View {
        content
            .containerBackground(latch.canvas, for: .tabView)
            .background(latch.canvas)
            .environment(\.colorScheme, latch.colorScheme)
            .toolbarColorScheme(latch.colorScheme, for: .navigationBar)
    }
}

extension View {
    func latchCard(radius: CGFloat = 18) -> some View {
        modifier(LatchCardModifier(radius: radius))
    }

    func latchScreen() -> some View {
        modifier(LatchScreenModifier())
    }

    func latchTabPage() -> some View {
        modifier(LatchTabPageModifier())
    }
}

struct WatchRunButtonStyle: ButtonStyle {
    var fill: Color
    var foreground: Color

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
