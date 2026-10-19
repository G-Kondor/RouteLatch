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
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Free Run").font(.title3.bold())
                                Text("Run without a route").font(.caption).foregroundStyle(.secondary)
                                if let target = model.freeRunTargetPaceSecondsPerKilometer {
                                    Label(watchPace(target), systemImage: "speedometer")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                            .padding(.vertical, 8)
                        } icon: {
                            Image(systemName: "figure.run.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
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
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(route.name).font(.title3.bold()).lineLimit(2)
                                    Label(watchDistance(route.totalDistance), systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                                    if let target = route.targetPaceSecondsPerKilometer {
                                        Label(watchPace(target), systemImage: "speedometer")
                                            .font(.caption).foregroundStyle(.orange)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Run")
            .environment(\.defaultMinListRowHeight, 92)
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
        GeometryReader { proxy in
            let buttonHeight = max(proxy.size.height * 0.5, 1)
            VStack(spacing: 6) {
                ScrollView {
                    VStack(spacing: 8) {
                        Text("Free Run").font(.headline)
                        Text("Run without a route").font(.caption2).foregroundStyle(.secondary)
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
                    }
                }
                Button { showNavigation = true } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "figure.run")
                            .font(.title2)
                        Text("Start Free Run")
                    }
                }
                .buttonStyle(WatchRunButtonStyle(fill: .green, foreground: .black))
                .frame(maxWidth: .infinity)
                .frame(height: buttonHeight)
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
        GeometryReader { proxy in
            let startHeight = max(proxy.size.height * 0.36, 1)
            let deleteHeight = max(proxy.size.height * 0.28, 1)
            VStack(spacing: 6) {
                ScrollView {
                    VStack(spacing: 8) {
                        Text(route.name).font(.headline).multilineTextAlignment(.center)
                        Text(watchDistance(route.totalDistance)).font(.title3.bold())
                        Text("\(route.pointCount) points • \(route.segments.count) segments").font(.caption2).foregroundStyle(.secondary)
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
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Button { showNavigation = true } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "location.fill")
                            .font(.title3)
                        Text("Start Guidance")
                    }
                }
                .buttonStyle(WatchRunButtonStyle(fill: .orange, foreground: .black))
                .frame(maxWidth: .infinity)
                .frame(height: startHeight)
                Button { confirmingDelete = true } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "trash")
                            .font(.title3)
                        Text("Delete Watch Copy")
                            .font(.caption.bold())
                    }
                }
                .buttonStyle(WatchRunButtonStyle(fill: .red, foreground: .white))
                .frame(maxWidth: .infinity)
                .frame(height: deleteHeight)
                .accessibilityLabel("Delete Watch Copy")
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

struct WatchRunButtonStyle: ButtonStyle {
    var fill: Color
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.7)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(fill.opacity(configuration.isPressed ? 0.72 : 1))
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
