import MapKit
import RouteLatchCore
import SwiftUI

struct RouteDetailView: View {
    let route: Route
    @ObservedObject var model: PhoneRouteLibraryModel
    @State private var position: MapCameraPosition
    @State private var paceAlertsEnabled: Bool
    @State private var targetPace: Double

    init(route: Route, model: PhoneRouteLibraryModel) {
        self.route = route
        self.model = model
        _position = State(initialValue: .region(route.mapRegion))
        _paceAlertsEnabled = State(initialValue: route.targetPaceSecondsPerKilometer != nil)
        _targetPace = State(initialValue: route.targetPaceSecondsPerKilometer ?? PaceGoalConfiguration.defaultSecondsPerKilometer)
    }

    private var currentRoute: Route { model.routes.first(where: { $0.id == route.id }) ?? route }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Map(position: $position) {
                    ForEach(Array(route.segments.enumerated()), id: \.offset) { _, segment in
                        MapPolyline(coordinates: segment.points.map(\.coordinate)).stroke(.orange, lineWidth: 5)
                    }
                    Marker("Start", systemImage: "flag.fill", coordinate: route.start.coordinate).tint(.green)
                    Marker("Finish", systemImage: "flag.checkered", coordinate: route.finish.coordinate).tint(.red)
                }
                .frame(height: 320).clipShape(RoundedRectangle(cornerRadius: 18)).accessibilityLabel("Map of \(route.name)")
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                    metric("Distance", route.totalDistance.formattedDistance, "figure.run")
                    metric("Ascent", route.totalAscent.map { String(format: "%.0f m", $0) } ?? "—", "mountain.2")
                    metric("Points", route.pointCount.formatted(), "mappin.and.ellipse")
                    metric("Segments", route.segments.count.formatted(), "point.3.connected.trianglepath.dotted")
                }
                paceGoalCard
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Original file", value: route.originalFilename)
                    LabeledContent("Imported") { Text(route.importDate, style: .date) }
                    LabeledContent("Watch") { Text(model.connectivity.status(for: currentRoute).label) }
                }.font(.subheadline)
                Button {
                    savePaceGoal()
                    model.connectivity.send(currentRoute)
                } label: { Label("Send to Apple Watch", systemImage: "applewatch.radiowaves.left.and.right").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }.padding()
        }
        .navigationTitle(route.name).navigationBarTitleDisplayMode(.inline)
    }


    private var paceGoalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $paceAlertsEnabled) {
                Label("Target pace alerts", systemImage: "speedometer")
                    .font(.headline)
            }
            .onChange(of: paceAlertsEnabled) { _, _ in savePaceGoal() }

            HStack(alignment: .firstTextBaseline) {
                Text("Goal")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatPace(targetPace))
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(paceAlertsEnabled ? .primary : .secondary)
            }
            Slider(
                value: $targetPace,
                in: PaceGoalConfiguration.minimumSecondsPerKilometer...PaceGoalConfiguration.maximumSecondsPerKilometer,
                step: PaceGoalConfiguration.sliderStep,
                label: { Text("Target pace") },
                minimumValueLabel: { Text("3:00").font(.caption2) },
                maximumValueLabel: { Text("15:00").font(.caption2) },
                onEditingChanged: { editing in if !editing { savePaceGoal() } }
            )
            .disabled(!paceAlertsEnabled)
            .accessibilityValue(formatPace(targetPace))

            LabeledContent("Planned time") {
                Text(formatDuration(currentRoute.totalDistance / 1_000 * targetPace))
                    .monospacedDigit()
            }
            .foregroundStyle(paceAlertsEnabled ? .primary : .secondary)
            Text("After 500 m and 3 active minutes, the Watch warns when your average course pace is more than 10% behind this goal.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }

    private func savePaceGoal() {
        model.setTargetPace(paceAlertsEnabled ? targetPace : nil, for: currentRoute)
    }

    private func formatPace(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        return String(format: "%d:%02d /km", rounded / 60, rounded % 60)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        if rounded >= 3_600 { return String(format: "%d:%02d:%02d", rounded / 3_600, rounded % 3_600 / 60, rounded % 60) }
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }

    private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading) { Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary); Text(value).font(.title3.bold()) }
            .frame(maxWidth: .infinity, alignment: .leading).padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }
}

private extension RoutePoint { var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) } }
private extension Route {
    var mapRegion: MKCoordinateRegion {
        let latitudeDelta = max(0.005, (bounds.maxLatitude - bounds.minLatitude) * 1.25)
        let longitudeDelta = max(0.005, (bounds.maxLongitude - bounds.minLongitude) * 1.25)
        return MKCoordinateRegion(center: .init(latitude: (bounds.minLatitude + bounds.maxLatitude) / 2, longitude: (bounds.minLongitude + bounds.maxLongitude) / 2), span: .init(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta))
    }
}
