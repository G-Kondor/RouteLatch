import MapKit
import RouteLatchCore
import SwiftUI

struct RouteDetailView: View {
    let route: Route
    @ObservedObject var model: PhoneRouteLibraryModel
    @State private var position: MapCameraPosition

    init(route: Route, model: PhoneRouteLibraryModel) {
        self.route = route
        self.model = model
        _position = State(initialValue: .region(route.mapRegion))
    }

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
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Original file", value: route.originalFilename)
                    LabeledContent("Imported") { Text(route.importDate, style: .date) }
                    LabeledContent("Watch") { Text(model.connectivity.status(for: route).label) }
                }.font(.subheadline)
                Button { model.connectivity.send(route) } label: { Label("Send to Apple Watch", systemImage: "applewatch.radiowaves.left.and.right").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }.padding()
        }
        .navigationTitle(route.name).navigationBarTitleDisplayMode(.inline)
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
