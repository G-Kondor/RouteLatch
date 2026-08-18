import MapKit
import RouteLatchCore
import SwiftUI

struct NavigationView: View {
    @StateObject private var model: RouteNavigationModel
    @State private var mapPosition: MapCameraPosition

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
        .containerBackground(model.match.map { $0.distanceFromRoute > 40 } == true ? Color.red.opacity(0.28) : Color.black, for: .navigation)
        .navigationBarBackButtonHidden(model.phase == .active || model.phase == .paused)
        .alert("Guidance Unavailable", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK") {} } message: { Text(model.errorMessage ?? "Unknown error") }
    }

    private var mapView: some View {
        Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
            ForEach(Array(model.route.segments.enumerated()), id: \.offset) { _, segment in
                MapPolyline(coordinates: segment.points.map { .init(latitude: $0.latitude, longitude: $0.longitude) }).stroke(.orange, lineWidth: 4)
            }
            Marker("Start", systemImage: "flag.fill", coordinate: .init(latitude: model.route.start.latitude, longitude: model.route.start.longitude)).tint(.green)
            Marker("Finish", systemImage: "flag.checkered", coordinate: .init(latitude: model.route.finish.latitude, longitude: model.route.finish.longitude)).tint(.red)
            if let location = model.location { Annotation("You", coordinate: location.coordinate) { Image(systemName: "location.fill").foregroundStyle(.blue).padding(4).background(.white, in: Circle()) } }
        }.accessibilityLabel("Route map and current position")
    }

    private var metricsView: some View {
        ScrollView {
            VStack(spacing: 7) {
                status
                metric("Progress", String(format: "%.0f%%", (model.match?.progress ?? 0) * 100))
                metric("Remaining", watchDistance(max(0, model.route.totalDistance - (model.match?.distanceAlongRoute ?? 0))))
                metric("Off course", watchDistance(model.match?.distanceFromRoute ?? 0))
                metric("Elapsed", Duration.seconds(model.elapsed).formatted(.time(pattern: .minuteSecond)))
                if let heartRate = model.workout.heartRate { metric("Heart rate", String(format: "%.0f bpm", heartRate)) }
            }.padding(.horizontal, 4)
        }
    }

    private var status: some View {
        Label(model.match.map { $0.distanceFromRoute > 40 } == true ? "OFF COURSE" : "ON ROUTE", systemImage: model.match.map { $0.distanceFromRoute > 40 } == true ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .font(.headline).foregroundStyle(model.match.map { $0.distanceFromRoute > 40 } == true ? .red : .green).accessibilityLabel(model.match.map { $0.distanceFromRoute > 40 } == true ? "Off course" : "On route")
    }

    private var controlsView: some View {
        VStack(spacing: 8) {
            Text(model.route.name).font(.headline).multilineTextAlignment(.center)
            switch model.phase {
            case .ready: Button("Start Run", systemImage: "figure.run") { model.start() }.buttonStyle(.borderedProminent)
            case .active:
                Button("Pause", systemImage: "pause.fill") { model.pause() }.tint(.yellow)
                Button("Finish", systemImage: "stop.fill", role: .destructive) { model.finish() }
            case .paused:
                Button("Resume", systemImage: "play.fill") { model.resume() }.buttonStyle(.borderedProminent)
                Button("Finish", systemImage: "stop.fill", role: .destructive) { model.finish() }
            case .finished: Label("Run Saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).font(.headline.monospacedDigit()) }.font(.caption)
    }
}
