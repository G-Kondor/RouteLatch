import Combine
import RouteLatchCore
import SwiftUI

/// Keeps the in-progress run alive if the navigation stack drops the run screen.
/// Releasing that screen releases its `HKWorkoutSession`, and watchOS then
/// returns to the clock face instead of this app.
@MainActor
final class WorkoutSessionAnchor: ObservableObject {
    @Published private(set) var model: RouteNavigationModel?
    /// False once the navigation screen has gone away while its session must stay up.
    @Published private(set) var isAttached = false
    private var closeHandler: (() -> Void)?
    private var phaseCancellable: AnyCancellable?

    func present(_ model: RouteNavigationModel, onClose: @escaping () -> Void) {
        closeHandler = onClose
        isAttached = true
        guard self.model !== model else { return }
        self.model = model
        phaseCancellable = model.$phase.sink { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.isAttached, self.model?.phase == .ready {
                    self.dismiss()
                } else {
                    self.objectWillChange.send()
                }
            }
        }
    }

    var showsDetachedRun: Bool {
        guard let model, !isAttached else { return false }
        switch model.phase {
        case .ready:
            return false
        case .starting, .active, .paused, .finishing, .finished:
            return true
        }
    }

    func releaseIfNotRunning(_ model: RouteNavigationModel) {
        guard self.model === model else { return }
        if model.keepsDisplay {
            isAttached = false
            return
        }
        clear()
    }

    func dismiss() {
        let close = closeHandler
        clear()
        close?()
    }

    private func clear() {
        phaseCancellable = nil
        closeHandler = nil
        model = nil
        isAttached = false
    }
}

@main
struct RouteLatchWatchApp: App {
    @StateObject private var model = WatchRouteLibraryModel()
    @StateObject private var anchor = WorkoutSessionAnchor()

    var body: some Scene {
        WindowGroup {
            WatchRoot(model: model, anchor: anchor)
        }
    }
}

/// Reads the Watch's own scheme from outside the override, then paints with the iPhone selection.
private struct WatchRoot: View {
    @ObservedObject var model: WatchRouteLibraryModel
    @ObservedObject var anchor: WorkoutSessionAnchor
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let palette = LatchColor.resolved(
            preferred: colorScheme(for: model.phoneResolvedAppearance),
            system: systemColorScheme
        )
        ZStack {
            WatchRouteLibraryView(model: model)
            if anchor.showsDetachedRun, let run = anchor.model {
                NavigationStack {
                    RunScreen(model: run)
                }
                .background(palette.canvas)
                .zIndex(1)
            }
        }
        .background(palette.canvas)
        .environmentObject(anchor)
        .environment(\.latchColor, palette)
        .environment(\.colorScheme, palette.colorScheme)
        .preferredColorScheme(model.phoneResolvedAppearance == nil ? nil : palette.colorScheme)
        .tint(palette.accent)
        .onAppear { model.applyReceivedAppearance() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.applyReceivedAppearance() }
        }
    }
}

private func colorScheme(for appearance: ResolvedAppearance?) -> ColorScheme? {
    switch appearance {
    case .light:
        .light
    case .dark:
        .dark
    case nil:
        nil
    }
}
