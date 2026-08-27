import MapKit
import RouteLatchCore
import SwiftUI

struct NavigationView: View {
    @StateObject private var model: RouteNavigationModel
    @State private var mapPosition: MapCameraPosition
    @State private var hasCenteredOnRunner = false

    init(route: Route) {
        _model = StateObject(wrappedValue: RouteNavigationModel(route: route))
        let bounds = route.bounds
        _mapPosition = State(initialValue: .region(MKCoordinateRegion(center: .init(latitude: (bounds.minLatitude + bounds.maxLatitude) / 2, longitude: (bounds.minLongitude + bounds.maxLongitude) / 2), span: .init(latitudeDelta: max(0.005, (bounds.maxLatitude - bounds.minLatitude) * 1.3), longitudeDelta: max(0.005, (bounds.maxLongitude - bounds.minLongitude) * 1.3)))))
    }

    var body: some View {
        TabView {
            mapView
            metricsView
            controlsView
        }
        .tabViewStyle(.verticalPage)
        .containerBackground(navigationBackground, for: .navigation)
        .navigationBarBackButtonHidden(model.phase == .starting || model.phase == .active || model.phase == .paused || model.phase == .finishing)
        .alert("Guidance Unavailable", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK") {} } message: { Text(model.errorMessage ?? "Unknown error") }
    }

    private var navigationBackground: Color {
        if model.isOffCourse { return Color.red.opacity(0.28) }
        if model.isBehindPace { return Color.yellow.opacity(0.2) }
        return .black
    }

    private var mapView: some View {
        Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
            ForEach(Array(model.route.segments.enumerated()), id: \.offset) { _, segment in
                MapPolyline(coordinates: segment.points.map { .init(latitude: $0.latitude, longitude: $0.longitude) }).stroke(.orange, lineWidth: 4)
            }
            Marker("Start", systemImage: "flag.fill", coordinate: .init(latitude: model.route.start.latitude, longitude: model.route.start.longitude)).tint(.green)
            Marker("Finish", systemImage: "flag.checkered", coordinate: .init(latitude: model.route.finish.latitude, longitude: model.route.finish.longitude)).tint(.red)
            if let location = model.location { Annotation("You", coordinate: location.coordinate) { Image(systemName: "location.fill").foregroundStyle(.blue).padding(4).background(.white, in: Circle()) } }
        }
        .accessibilityLabel("Route map and current position")
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
                metric("Progress", String(format: "%.0f%%", (model.match?.progress ?? 0) * 100))
                metric("This run", watchDistance(model.distanceCompleted))
                metric("Remaining", watchDistance(max(0, model.route.totalDistance - (model.match?.distanceAlongRoute ?? 0))))
                metric("Off course", watchDistance(model.match?.distanceFromRoute ?? 0))
                metric("Elapsed", Duration.seconds(model.elapsed).formatted(.time(pattern: .minuteSecond)))
                if let target = model.route.targetPaceSecondsPerKilometer {
                    metric("Target pace", watchPace(target))
                }
                if let pace = model.paceProgress {
                    metric("Average pace", watchPace(pace.averagePaceSecondsPerKilometer))
                    metric("Schedule", scheduleText(pace.scheduleDelta))
                    metric("Projected", watchDuration(pace.projectedDuration))
                }
                if let heartRate = model.heartRate { metric("Heart rate", String(format: "%.0f bpm", heartRate)) }
            }.padding(.horizontal, 4)
        }
    }

    private var status: some View {
        Group {
            if model.match == nil {
                Label("WAITING FOR GPS", systemImage: "location.slash")
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

    private var controlsView: some View {
        VStack(spacing: 8) {
            Text(model.route.name).font(.headline).multilineTextAlignment(.center)
            switch model.phase {
            case .ready: Button("Start Run", systemImage: "figure.run") { model.start() }.buttonStyle(.borderedProminent)
            case .starting: ProgressView("Starting…")
            case .active:
                Button("Pause", systemImage: "pause.fill") { model.pause() }.tint(.yellow)
                Button("Finish", systemImage: "stop.fill", role: .destructive) { model.finish() }
            case .paused:
                Button("Resume", systemImage: "play.fill") { model.resume() }.buttonStyle(.borderedProminent)
                Button("Finish", systemImage: "stop.fill", role: .destructive) { model.finish() }
            case .finishing: ProgressView("Saving…")
            case .finished:
                if let summary = model.summary {
                    Label(summary.workoutSaved ? "Run Saved" : "Run Ended", systemImage: summary.workoutSaved ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(summary.workoutSaved ? .green : .yellow)
                    metric("Elapsed", Duration.seconds(summary.elapsed).formatted(.time(pattern: .minuteSecond)))
                    metric("Course", watchDistance(summary.distanceCompleted))
                    if let pace = summary.paceProgress {
                        metric("Average pace", watchPace(pace.averagePaceSecondsPerKilometer))
                        metric("Schedule", scheduleText(pace.scheduleDelta))
                        metric("Projected", watchDuration(pace.projectedDuration))
                    }
                    if let heartRate = summary.heartRate { metric("Heart rate", String(format: "%.0f bpm", heartRate)) }
                    if summary.workoutSaved, !summary.routeSaved {
                        Text("Workout saved without a location route.").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
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
