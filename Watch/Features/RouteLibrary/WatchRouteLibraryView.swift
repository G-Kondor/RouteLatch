import RouteLatchCore
import SwiftUI

struct WatchRouteLibraryView: View {
    @ObservedObject var model: WatchRouteLibraryModel
    var body: some View {
        NavigationStack {
            Group {
                if model.routes.isEmpty {
                    ContentUnavailableView("No Routes", systemImage: "point.topleft.down.to.point.bottomright.curvepath", description: Text("Send a GPX route from RouteLatch on iPhone."))
                } else {
                    List(model.routes) { route in
                        NavigationLink {
                            WatchRouteDetailView(route: route, onDelete: { model.delete(route) })
                        } label: {
                            VStack(alignment: .leading) {
                                Text(route.name).font(.headline).lineLimit(2)
                                Label(watchDistance(route.totalDistance), systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }.navigationTitle("Routes")
        }
        .alert("Route Error", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK") {} } message: { Text(model.errorMessage ?? "Unknown error") }
    }
}

struct WatchRouteDetailView: View {
    let route: Route
    let onDelete: () -> Void
    @State private var showNavigation = false
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "figure.run.circle.fill").font(.system(size: 44)).foregroundStyle(.orange)
                Text(route.name).font(.headline).multilineTextAlignment(.center)
                Text(watchDistance(route.totalDistance)).font(.title3.bold())
                Text("\(route.pointCount) points • \(route.segments.count) segments").font(.caption).foregroundStyle(.secondary)
                Button("Start Guidance", systemImage: "location.fill") { showNavigation = true }.buttonStyle(.borderedProminent)
                Button("Delete Watch Copy", systemImage: "trash", role: .destructive) { onDelete() }
            }
        }.navigationDestination(isPresented: $showNavigation) { NavigationView(route: route) }
    }
}

func watchDistance(_ meters: Double) -> String { meters >= 1000 ? String(format: "%.1f km", meters / 1000) : String(format: "%.0f m", meters) }
