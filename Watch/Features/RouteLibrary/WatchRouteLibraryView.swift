import RouteLatchCore
import SwiftUI

struct WatchRouteLibraryView: View {
    @ObservedObject var model: WatchRouteLibraryModel
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        FreeRunSetupView(
                            targetPaceSecondsPerKilometer: model.freeRunTargetPaceSecondsPerKilometer,
                            onPaceChange: model.setFreeRunTargetPace
                        )
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Free Run").font(.headline)
                                Text("Run without a route").font(.caption2).foregroundStyle(.secondary)
                                if let target = model.freeRunTargetPaceSecondsPerKilometer {
                                    Label(watchPace(target), systemImage: "speedometer")
                                        .font(.caption2).foregroundStyle(.orange)
                                }
                            }
                        } icon: {
                            Image(systemName: "figure.run.circle.fill").foregroundStyle(.green)
                        }
                    }
                }

                if model.isLoadingRoutes {
                    Section("Guided Routes") {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading routes…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if model.routes.isEmpty {
                    Section("Guided Routes") {
                        Text("Send a GPX route from RouteLatch on iPhone.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Section("Guided Routes") {
                        ForEach(model.routes) { route in
                            NavigationLink {
                                WatchRouteDetailView(
                                    route: route,
                                    onDelete: { model.delete(route) },
                                    onPaceChange: { model.setTargetPace($0, for: route) }
                                )
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(route.name).font(.headline).lineLimit(2)
                                    Label(watchDistance(route.totalDistance), systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                                    if let target = route.targetPaceSecondsPerKilometer {
                                        Label(watchPace(target), systemImage: "speedometer")
                                            .font(.caption2).foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Run")
        }
        .alert("Route Error", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK") {} } message: { Text(model.errorMessage ?? "Unknown error") }
    }
}

struct FreeRunSetupView: View {
    let onPaceChange: (Double?) -> Void
    @State private var showNavigation = false
    @State private var paceAlertsEnabled: Bool
    @State private var targetPace: Double

    init(targetPaceSecondsPerKilometer: Double?, onPaceChange: @escaping (Double?) -> Void) {
        self.onPaceChange = onPaceChange
        _paceAlertsEnabled = State(initialValue: targetPaceSecondsPerKilometer != nil)
        _targetPace = State(initialValue: targetPaceSecondsPerKilometer ?? PaceGoalConfiguration.defaultSecondsPerKilometer)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 44)).foregroundStyle(.green)
                Text("Free Run").font(.headline)
                Text("Run without a route").font(.caption).foregroundStyle(.secondary)
                Divider()
                Toggle("Pace alerts", isOn: $paceAlertsEnabled)
                    .onChange(of: paceAlertsEnabled) { _, _ in savePaceGoal() }
                Text(watchPace(targetPace))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(paceAlertsEnabled ? .primary : .secondary)
                Slider(
                    value: $targetPace,
                    in: PaceGoalConfiguration.minimumSecondsPerKilometer...PaceGoalConfiguration.maximumSecondsPerKilometer,
                    step: PaceGoalConfiguration.sliderStep,
                    onEditingChanged: { editing in if !editing { savePaceGoal() } }
                )
                .disabled(!paceAlertsEnabled)
                .accessibilityLabel("Target pace")
                .accessibilityValue(watchPace(targetPace))
                if paceAlertsEnabled {
                    Text("Alerts when average pace falls behind \(watchPace(targetPace)).")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Button("Start Free Run", systemImage: "figure.run") { showNavigation = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .navigationDestination(isPresented: $showNavigation) {
            NavigationView(
                freeRunTargetPaceSecondsPerKilometer: paceAlertsEnabled ? targetPace : nil
            )
        }
    }

    private func savePaceGoal() {
        onPaceChange(paceAlertsEnabled ? targetPace : nil)
    }
}

struct WatchRouteDetailView: View {
    let onDelete: () -> Void
    let onPaceChange: (Double?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var route: Route
    @State private var showNavigation = false
    @State private var confirmingDelete = false
    @State private var paceAlertsEnabled: Bool
    @State private var targetPace: Double

    init(route: Route, onDelete: @escaping () -> Void, onPaceChange: @escaping (Double?) -> Void) {
        self.onDelete = onDelete
        self.onPaceChange = onPaceChange
        _route = State(initialValue: route)
        _paceAlertsEnabled = State(initialValue: route.targetPaceSecondsPerKilometer != nil)
        _targetPace = State(initialValue: route.targetPaceSecondsPerKilometer ?? PaceGoalConfiguration.defaultSecondsPerKilometer)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "figure.run.circle.fill").font(.system(size: 44)).foregroundStyle(.orange)
                Text(route.name).font(.headline).multilineTextAlignment(.center)
                Text(watchDistance(route.totalDistance)).font(.title3.bold())
                Text("\(route.pointCount) points • \(route.segments.count) segments").font(.caption).foregroundStyle(.secondary)
                Divider()
                Toggle("Pace alerts", isOn: $paceAlertsEnabled)
                    .onChange(of: paceAlertsEnabled) { _, _ in savePaceGoal() }
                Text(watchPace(targetPace))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(paceAlertsEnabled ? .primary : .secondary)
                Slider(
                    value: $targetPace,
                    in: PaceGoalConfiguration.minimumSecondsPerKilometer...PaceGoalConfiguration.maximumSecondsPerKilometer,
                    step: PaceGoalConfiguration.sliderStep,
                    onEditingChanged: { editing in if !editing { savePaceGoal() } }
                )
                .disabled(!paceAlertsEnabled)
                .accessibilityLabel("Target pace")
                .accessibilityValue(watchPace(targetPace))
                if paceAlertsEnabled {
                    Text("Plan: \(watchDuration(route.totalDistance / 1_000 * targetPace))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Start Guidance", systemImage: "location.fill") { showNavigation = true }.buttonStyle(.borderedProminent)
                Button("Delete Watch Copy", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            }
        }
        .navigationDestination(isPresented: $showNavigation) { NavigationView(route: route) }
        .alert("Delete Watch Copy?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { onDelete(); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes only the copy stored on Apple Watch.")
        }
    }

    private func savePaceGoal() {
        route.targetPaceSecondsPerKilometer = paceAlertsEnabled ? targetPace : nil
        onPaceChange(route.targetPaceSecondsPerKilometer)
    }
}

func watchDistance(_ meters: Double) -> String { meters >= 1000 ? String(format: "%.1f km", meters / 1000) : String(format: "%.0f m", meters) }
func watchPace(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "—" }
    let rounded = Int(seconds.rounded())
    return String(format: "%d:%02d /km", rounded / 60, rounded % 60)
}
func watchDuration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "—" }
    let rounded = Int(seconds.rounded())
    return rounded >= 3_600
        ? String(format: "%d:%02d:%02d", rounded / 3_600, rounded % 3_600 / 60, rounded % 60)
        : String(format: "%d:%02d", rounded / 60, rounded % 60)
}
