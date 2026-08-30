import RouteLatchCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType { static let gpx = UTType(importedAs: "com.topografix.gpx", conformingTo: .xml) }

struct RouteLibraryView: View {
    @ObservedObject var model: PhoneRouteLibraryModel
    @State private var importing = false
    @State private var routeToDelete: Route?
    @State private var routeToRename: Route?
    @State private var runToDelete: RecordedRun?
    @State private var newName = ""
    @State private var showingStrava = false

    var body: some View {
        NavigationStack {
            List {
                if model.routes.isEmpty && model.completedRuns.isEmpty {
                    ContentUnavailableView("No Routes Yet", systemImage: "point.topleft.down.to.point.bottomright.curvepath", description: Text("Import a GPX course to keep it available on your phone and Apple Watch."))
                }
                if !model.routes.isEmpty {
                    Section("Routes") {
                        ForEach(model.routes) { route in
                        NavigationLink(value: route) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(route.name).font(.headline)
                                HStack {
                                    Text(route.totalDistance.formattedDistance)
                                    Text("•")
                                    Text(route.importDate, style: .date)
                                    Spacer()
                                    Text(model.connectivity.status(for: route).label).font(.caption).foregroundStyle(.secondary)
                                }.font(.subheadline).foregroundStyle(.secondary)
                                if let target = route.targetPaceSecondsPerKilometer {
                                    Label(routeListPace(target), systemImage: "speedometer")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }.padding(.vertical, 4)
                        }
                        .swipeActions(edge: .leading) { Button("Rename", systemImage: "pencil") { routeToRename = route; newName = route.name }.tint(.blue) }
                        .swipeActions { Button("Delete", systemImage: "trash", role: .destructive) { routeToDelete = route } }
                        }
                    }
                }
                if !model.completedRuns.isEmpty {
                    Section("Completed Runs") {
                        ForEach(model.completedRuns) { run in
                            CompletedRunRow(run: run, strava: model.strava, runStore: model.runStore)
                                .swipeActions {
                                    Button("Delete", systemImage: "trash", role: .destructive) { runToDelete = run }
                                }
                        }
                    }
                }
            }
            .navigationTitle("RouteLatch")
            .navigationDestination(for: Route.self) { RouteDetailView(route: $0, model: model) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Strava", systemImage: "bolt.horizontal.circle") { showingStrava = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if model.isImporting { ProgressView().accessibilityLabel("Importing GPX") }
                    else { Button("Import GPX", systemImage: "square.and.arrow.down") { importing = true }.accessibilityHint("Choose a GPX course file") }
                }
            }
            .sheet(isPresented: $showingStrava) { StravaSettingsView(strava: model.strava, pendingRuns: model.completedRuns) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.gpx, .xml], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first { model.importRoute(from: url) }
                if case .failure(let error) = result { model.errorMessage = error.localizedDescription }
            }
            .alert("Couldn’t Complete Action", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK") {} } message: { Text(model.errorMessage ?? "Unknown error") }
            .alert("Delete Route?", isPresented: Binding(get: { routeToDelete != nil }, set: { if !$0 { routeToDelete = nil } })) {
                Button("Delete", role: .destructive) { if let routeToDelete { model.delete(routeToDelete) } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("The route will be removed from this iPhone. Its Watch copy is managed separately.") }
            .alert("Rename Route", isPresented: Binding(get: { routeToRename != nil }, set: { if !$0 { routeToRename = nil } })) {
                TextField("Route name", text: $newName)
                Button("Save") { if let routeToRename { model.rename(routeToRename, to: newName) } }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Delete Completed Run?", isPresented: Binding(get: { runToDelete != nil }, set: { if !$0 { runToDelete = nil } })) {
                Button("Delete", role: .destructive) { if let runToDelete { model.delete(runToDelete) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes RouteLatch’s local TCX copy. It does not delete the workout from Health or Strava.")
            }
            .safeAreaInset(edge: .bottom) { if let warning = model.storageWarning { Text(warning).font(.caption).padding(8).background(.thinMaterial).accessibilityLabel("Storage warning: \(warning)") } }
        }
    }

    private func routeListPace(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        return String(format: "Target %d:%02d /km", rounded / 60, rounded % 60)
    }
}

extension Double {
    var formattedDistance: String { self >= 1000 ? String(format: "%.1f km", self / 1000) : String(format: "%.0f m", self) }
}
