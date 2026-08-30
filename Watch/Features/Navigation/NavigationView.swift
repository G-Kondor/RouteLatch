import MapKit
import RouteLatchCore
import SwiftUI

struct NavigationView: View {
    @StateObject private var model: RouteNavigationModel
    @State private var mapPosition: MapCameraPosition
    @State private var hasCenteredOnRunner = false
    @State private var selectedPage = 0
    @State private var confirmingFinish = false

    init(route: Route? = nil, freeRunTargetPaceSecondsPerKilometer: Double? = nil) {
        _model = StateObject(wrappedValue: RouteNavigationModel(
            route: route,
            freeRunTargetPaceSecondsPerKilometer: freeRunTargetPaceSecondsPerKilometer
        ))
        if let route {
            let bounds = route.bounds
            _mapPosition = State(initialValue: .region(MKCoordinateRegion(
                center: .init(
                    latitude: (bounds.minLatitude + bounds.maxLatitude) / 2,
                    longitude: (bounds.minLongitude + bounds.maxLongitude) / 2
                ),
                span: .init(
                    latitudeDelta: max(0.005, (bounds.maxLatitude - bounds.minLatitude) * 1.3),
                    longitudeDelta: max(0.005, (bounds.maxLongitude - bounds.minLongitude) * 1.3)
                )
            )))
        } else {
            _mapPosition = State(initialValue: .userLocation(followsHeading: true, fallback: .automatic))
        }
    }

    var body: some View {
        TabView(selection: $selectedPage) {
            workoutView.tag(0)
            if model.isGuidedRun {
                mapView.tag(1)
            }
            metricsView.tag(model.isGuidedRun ? 2 : 1)
        }
        .tabViewStyle(.verticalPage)
        .containerBackground(navigationBackground, for: .navigation)
        .navigationBarBackButtonHidden(model.phase == .starting || model.phase == .active || model.phase == .paused || model.phase == .finishing)
        .alert("Run Error", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK") {} } message: { Text(model.errorMessage ?? "Unknown error") }
        .alert("Finish Run?", isPresented: $confirmingFinish) {
            Button("Finish", role: .destructive) { model.finish() }
            Button("Keep Running", role: .cancel) {}
        } message: {
            Text("The workout and the route you actually ran will be saved to Health.")
        }
    }

    private var navigationBackground: Color {
        if model.isOffCourse { return Color.red.opacity(0.28) }
        if model.isBehindPace { return Color.yellow.opacity(0.2) }
        return .black
    }

    private var mapView: some View {
        Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
            if let route = model.route {
                ForEach(Array(route.segments.enumerated()), id: \.offset) { _, segment in
                    MapPolyline(coordinates: segment.points.map { .init(latitude: $0.latitude, longitude: $0.longitude) })
                        .stroke(.orange, lineWidth: 4)
                }
                Marker("Start", systemImage: "flag.fill", coordinate: .init(latitude: route.start.latitude, longitude: route.start.longitude)).tint(.green)
                Marker("Finish", systemImage: "flag.checkered", coordinate: .init(latitude: route.finish.latitude, longitude: route.finish.longitude)).tint(.red)
            }
            if let location = model.location { Annotation("You", coordinate: location.coordinate) { Image(systemName: "location.fill").foregroundStyle(.blue).padding(4).background(.white, in: Circle()) } }
        }
        .accessibilityLabel(model.isGuidedRun ? "Route map and current position" : "Current running position")
        .overlay(alignment: .bottomTrailing) {
            if model.location != nil {
                Button { mapPosition = .userLocation(followsHeading: true, fallback: mapPosition) } label: {
                    Image(systemName: "location.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Recenter map on runner")
            }
        }
        .onChange(of: model.location?.timestamp) { _, _ in
            if !hasCenteredOnRunner, model.location != nil {
                hasCenteredOnRunner = true
                mapPosition = .userLocation(followsHeading: true, fallback: mapPosition)
            }
        }
    }

    private var metricsView: some View {
        ScrollView {
            VStack(spacing: 7) {
                status
                metric("Distance", watchDistance(model.actualDistance))
                metric("Elapsed", Duration.seconds(model.elapsed).formatted(.time(pattern: .minuteSecond)))
                metric("Average pace", model.averagePace.map(watchPace) ?? "—")
                if let route = model.route {
                    metric("Route progress", String(format: "%.0f%%", (model.match?.progress ?? 0) * 100))
                    metric("Remaining", watchDistance(max(0, route.totalDistance - (model.match?.distanceAlongRoute ?? 0))))
                    metric("Off course", watchDistance(model.match?.distanceFromRoute ?? 0))
                }
                if let target = model.targetPaceSecondsPerKilometer {
                    metric("Target pace", watchPace(target))
                }
                if let pace = model.paceProgress {
                    metric("Schedule", scheduleText(pace.scheduleDelta))
                    if model.isGuidedRun { metric("Projected", watchDuration(pace.projectedDuration)) }
                }
                if let heartRate = model.heartRate { metric("Heart rate", String(format: "%.0f bpm", heartRate)) }
            }.padding(.horizontal, 4)
        }
    }

    private var status: some View {
        Group {
            if model.match == nil {
                Label(model.phase == .active ? "TRACKING RUN" : "WAITING FOR GPS", systemImage: model.phase == .active ? "location.fill" : "location.slash")
            } else if model.isOffCourse {
                Label("OFF COURSE", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            } else if model.isBehindPace {
                Label("BEHIND GOAL", systemImage: "clock.badge.exclamationmark.fill").foregroundStyle(.yellow)
            } else {
                Label("ON ROUTE", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .font(.headline)
    }

    private var workoutView: some View {
        VStack(spacing: 8) {
            Text(model.runName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            switch model.phase {
            case .ready:
                Image(systemName: model.isGuidedRun ? "location.fill" : "figure.run")
                    .font(.system(size: 34)).foregroundStyle(.orange)
                Button("Start Run", systemImage: "figure.run") { model.start() }.buttonStyle(.borderedProminent)
            case .starting:
                ProgressView(model.startStage?.message ?? "Starting…")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                if model.startStage != .workout {
                    Button("Cancel", role: .cancel) { model.cancelStart() }
                        .font(.caption)
                }
            case .active, .paused:
                Text(watchDuration(model.elapsed))
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                HStack(spacing: 6) {
                    workoutMetric("Distance", watchDistance(model.actualDistance), color: .green)
                    workoutMetric("Avg pace", model.averagePace.map(watchPace) ?? "—", color: .orange)
                }
                HStack(spacing: 18) {
                    Button {
                        model.phase == .active ? model.pause() : model.resume()
                    } label: {
                        Image(systemName: model.phase == .active ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.phase == .active ? .yellow : .green)
                    .accessibilityLabel(model.phase == .active ? "Pause run" : "Resume run")

                    Button(role: .destructive) { confirmingFinish = true } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Finish run")
                }
            case .finishing: ProgressView("Saving…")
            case .finished:
                if let summary = model.summary {
                    Label(summary.workoutSaved ? "Run Saved" : "Run Ended", systemImage: summary.workoutSaved ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(summary.workoutSaved ? .green : .yellow)
                    metric("Elapsed", Duration.seconds(summary.elapsed).formatted(.time(pattern: .minuteSecond)))
                    metric("Distance", watchDistance(summary.actualDistance))
                    metric("Average pace", summary.averagePace.map(watchPace) ?? "—")
                    if let pace = summary.paceProgress {
                        metric("Schedule", scheduleText(pace.scheduleDelta))
                        if model.isGuidedRun { metric("Projected", watchDuration(pace.projectedDuration)) }
                    }
                    if let heartRate = summary.heartRate { metric("Heart rate", String(format: "%.0f bpm", heartRate)) }
                    if summary.workoutSaved, !summary.routeSaved {
                        Text("Workout saved without a location route.").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func workoutMetric(_ title: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(title.uppercased()).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            Text(value).font(.caption.bold().monospacedDigit()).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).font(.headline.monospacedDigit()) }.font(.caption)
    }

    private func scheduleText(_ delta: TimeInterval) -> String {
        let magnitude = watchDuration(abs(delta))
        if abs(delta) < 1 { return "On plan" }
        return delta > 0 ? "\(magnitude) behind" : "\(magnitude) ahead"
    }
}
