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
                        HStack(spacing: 8) {
                            LatchIconBadge(systemName: "figure.run", size: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Free Run")
                                    .font(.headline)
                                    .foregroundStyle(LatchColor.ink)
                                Text("Run without a route")
                                    .font(.caption2)
                                    .foregroundStyle(LatchColor.muted)
                                if let target = model.freeRunTargetPaceSecondsPerKilometer {
                                    Label(watchPace(target), systemImage: "speedometer")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(LatchColor.accent)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(latchListRow)
                }

                if model.isLoadingRoutes {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(LatchColor.accent)
                            Text("Loading routes…")
                                .font(.caption)
                                .foregroundStyle(LatchColor.muted)
                        }
                        .listRowBackground(latchListRow)
                    } header: {
                        sectionTitle("Guided Routes")
                    }
                } else if model.routes.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            LatchIconBadge(systemName: "square.and.arrow.down", size: 32)
                            Text("Send a GPX route from RouteLatch on iPhone.")
                                .font(.caption2)
                                .foregroundStyle(LatchColor.muted)
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(latchListRow)
                    } header: {
                        sectionTitle("Guided Routes")
                    }
                } else {
                    Section {
                        ForEach(model.routes) { route in
                            NavigationLink {
                                WatchRouteDetailView(
                                    route: route,
                                    onDelete: { model.delete(route) },
                                    onPaceChange: { model.setTargetPace($0, for: route) }
                                )
                            } label: {
                                HStack(spacing: 8) {
                                    LatchIconBadge(systemName: "map", size: 32)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(route.name)
                                            .font(.headline)
                                            .foregroundStyle(LatchColor.ink)
                                            .lineLimit(2)
                                        Label(watchDistance(route.totalDistance), systemImage: "location.fill")
                                            .font(.caption2)
                                            .foregroundStyle(LatchColor.muted)
                                        if let target = route.targetPaceSecondsPerKilometer {
                                            Label(watchPace(target), systemImage: "speedometer")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(LatchColor.accent)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(latchListRow)
                        }
                    } header: {
                        sectionTitle("Guided Routes")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LatchColor.canvas)
            .navigationTitle("Run")
            .environment(\.defaultMinListRowHeight, 92)
        }
        .latchScreen()
        .tint(LatchColor.accent)
        .alert("Route Error", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK") {} } message: { Text(model.errorMessage ?? "Unknown error") }
    }

    private var latchListRow: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LatchColor.card)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(LatchColor.muted)
            .textCase(nil)
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
                        LatchIconBadge(systemName: "figure.run", size: 32)
                        Text("Free Run")
                            .font(.headline)
                            .foregroundStyle(LatchColor.ink)
                        Text("Run without a route")
                            .font(.caption2)
                            .foregroundStyle(LatchColor.muted)
                        Toggle("Pace alerts", isOn: $paceAlertsEnabled)
                            .tint(LatchColor.accent)
                            .onChange(of: paceAlertsEnabled) { _, _ in savePaceGoal() }
                        Text(watchPace(targetPace))
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(paceAlertsEnabled ? LatchColor.accent : LatchColor.muted)
                        Slider(
                            value: $targetPace,
                            in: PaceGoalConfiguration.minimumSecondsPerKilometer...PaceGoalConfiguration.maximumSecondsPerKilometer,
                            step: PaceGoalConfiguration.sliderStep,
                            onEditingChanged: { editing in if !editing { savePaceGoal() } }
                        )
                        .tint(LatchColor.accent)
                        .disabled(!paceAlertsEnabled)
                        .accessibilityLabel("Target pace")
                        .accessibilityValue(watchPace(targetPace))
                        if paceAlertsEnabled {
                            Text("Alerts when average pace falls behind \(watchPace(targetPace)).")
                                .font(.caption2)
                                .foregroundStyle(LatchColor.muted)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(8)
                    .latchCard()
                }
                Button { showNavigation = true } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "figure.run")
                            .font(.title2)
                        Text("Start Free Run")
                    }
                }
                .buttonStyle(WatchRunButtonStyle(fill: LatchColor.accent, foreground: LatchColor.onAccent))
                .frame(maxWidth: .infinity)
                .frame(height: buttonHeight)
            }
        }
        .background(LatchColor.canvas)
        .latchScreen()
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
                        Text(route.name)
                            .font(.headline)
                            .foregroundStyle(LatchColor.ink)
                            .multilineTextAlignment(.center)
                        Text(watchDistance(route.totalDistance))
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(LatchColor.accent)
                        Text("\(route.pointCount) points • \(route.segments.count) segments")
                            .font(.caption2)
                            .foregroundStyle(LatchColor.muted)
                        Toggle("Pace alerts", isOn: $paceAlertsEnabled)
                            .tint(LatchColor.accent)
                            .onChange(of: paceAlertsEnabled) { _, _ in savePaceGoal() }
                        Text(watchPace(targetPace))
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(paceAlertsEnabled ? LatchColor.accent : LatchColor.muted)
                        Slider(
                            value: $targetPace,
                            in: PaceGoalConfiguration.minimumSecondsPerKilometer...PaceGoalConfiguration.maximumSecondsPerKilometer,
                            step: PaceGoalConfiguration.sliderStep,
                            onEditingChanged: { editing in if !editing { savePaceGoal() } }
                        )
                        .tint(LatchColor.accent)
                        .disabled(!paceAlertsEnabled)
                        .accessibilityLabel("Target pace")
                        .accessibilityValue(watchPace(targetPace))
                        if paceAlertsEnabled {
                            Text("Plan: \(watchDuration(route.totalDistance / 1_000 * targetPace))")
                                .font(.caption2)
                                .foregroundStyle(LatchColor.muted)
                        }
                    }
                    .padding(8)
                    .latchCard()
                }
                Button { showNavigation = true } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "location.fill")
                            .font(.title3)
                        Text("Start Guidance")
                    }
                }
                .buttonStyle(WatchRunButtonStyle(fill: LatchColor.accent, foreground: LatchColor.onAccent))
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
        .background(LatchColor.canvas)
        .latchScreen()
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
