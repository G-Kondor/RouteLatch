import RouteLatchCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType { static let gpx = UTType(importedAs: "com.topografix.gpx", conformingTo: .xml) }

struct RouteLibraryView: View {
    @ObservedObject var model: PhoneRouteLibraryModel
    @Binding var tab: PhoneTab
    @Binding var importing: Bool
    @State private var routeToDelete: Route?
    @State private var routeToRename: Route?
    @State private var newName = ""
    @State private var selectedRoute: Route?

    var body: some View {
        NavigationStack {
            List {
                plainRow { header }
                if model.routes.isEmpty {
                    plainRow { emptyState }
                } else {
                    ForEach(model.routes) { route in
                        routeRow(route)
                    }
                }
            }
            .listStyle(.plain)
            .listSectionSeparator(.hidden)
            .scrollContentBackground(.hidden)
            .background(LatchColor.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedRoute) { route in
                RouteDetailView(route: route, model: model)
            }
            .phoneChrome(tab: $tab, warning: model.storageWarning)
            .alert("Delete Route?", isPresented: Binding(get: { routeToDelete != nil }, set: { if !$0 { routeToDelete = nil } })) {
                Button("Delete", role: .destructive) { if let routeToDelete { model.delete(routeToDelete) } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("The route will be removed from this iPhone. Its Watch copy is managed separately.") }
            .alert("Rename Route", isPresented: Binding(get: { routeToRename != nil }, set: { if !$0 { routeToRename = nil } })) {
                TextField("Route name", text: $newName)
                Button("Save") { if let routeToRename { model.rename(routeToRename, to: newName) } }
                Button("Cancel", role: .cancel) {}
            }
        }
        .latchScreen()
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Routes")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(LatchColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("GPX courses on this iPhone")
                    .font(.subheadline)
                    .foregroundStyle(LatchColor.muted)
            }
            Spacer(minLength: 8)
            if importing || model.isImporting {
                ProgressView()
                    .tint(LatchColor.accent)
                    .accessibilityLabel("Importing GPX")
            } else {
                Button { importing = true } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LatchColor.onAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(LatchColor.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Import GPX")
                .accessibilityHint("Choose a GPX course file")
            }
        }
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            LatchIconBadge(systemName: "point.topleft.down.to.point.bottomright.curvepath", size: 68)
            Text("No Routes Yet")
                .font(.title3.bold())
                .foregroundStyle(LatchColor.ink)
            Text("Import a GPX course, then send it to Apple Watch from Home.")
                .font(.subheadline)
                .foregroundStyle(LatchColor.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .latchCard()
    }

    private func routeRow(_ route: Route) -> some View {
        Button {
            selectedRoute = route
        } label: {
            routeCard(route)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .leading) {
            Button("Rename", systemImage: "pencil") {
                routeToRename = route
                newName = route.name
            }
            .tint(.blue)
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { routeToDelete = route }
        }
        .accessibilityHint("Opens route details")
    }

    private func plainRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private func routeCard(_ route: Route) -> some View {
        HStack(alignment: .center, spacing: 14) {
            LatchIconBadge(systemName: "figure.run", size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(route.name)
                    .font(.headline)
                    .foregroundStyle(LatchColor.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text("\(route.totalDistance.formattedDistance) · \(route.importDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .foregroundStyle(LatchColor.muted)
                Text(model.connectivity.status(for: route).label)
                    .font(.caption)
                    .foregroundStyle(LatchColor.muted)
                if let target = route.targetPaceSecondsPerKilometer {
                    Label(routeListPace(target), systemImage: "speedometer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LatchColor.accent)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(LatchColor.muted)
                .accessibilityHidden(true)
        }
        .padding(16)
        .latchCard()
    }

    private func routeListPace(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        return String(format: "Target %d:%02d /km", rounded / 60, rounded % 60)
    }
}

extension Double {
    var formattedDistance: String { self >= 1000 ? String(format: "%.1f km", self / 1000) : String(format: "%.0f m", self) }
}
