import Combine
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
            ZStack {
                WatchRouteLibraryView(model: model)
                if anchor.showsDetachedRun, let run = anchor.model {
                    NavigationStack {
                        RunScreen(model: run)
                    }
                    .background(LatchColor.canvas)
                    .zIndex(1)
                }
            }
            .environmentObject(anchor)
            .tint(LatchColor.accent)
        }
    }
}
