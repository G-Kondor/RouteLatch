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
    @State private var selectedRoute: Route?

    var body: some View {
        NavigationStack {
            List {
                plainRow { dashboardHeader }
                if model.routes.isEmpty && model.completedRuns.isEmpty {
                    plainRow { emptyState }
                } else {
                    plainRow { summaryCard }
                }
                if !model.routes.isEmpty {
                    Section {
                        ForEach(model.routes) { route in
                            routeRow(route)
                        }
                    } header: {
                        sectionTitle("Routes")
                    }
                }
                if !model.completedRuns.isEmpty {
                    Section {
                        ForEach(model.completedRuns) { run in
                            CompletedRunRow(run: run, strava: model.strava, runStore: model.runStore)
                                .padding(16)
                                .latchCard()
                                .padding(.vertical, 4)
                                .swipeActions {
                                    Button("Delete", systemImage: "trash", role: .destructive) { runToDelete = run }
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    } header: {
                        sectionTitle("Completed Runs")
                    }
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(14)
            .listSectionSeparator(.hidden)
            .scrollContentBackground(.hidden)
            .background(LatchColor.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedRoute) { route in
                RouteDetailView(route: route, model: model)
            }
            .sheet(isPresented: $showingStrava) {
                StravaSettingsView(strava: model.strava, pendingRuns: model.completedRuns)
                    .presentationBackground(LatchColor.canvas)
                    .presentationDragIndicator(.visible)
            }
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
            .safeAreaInset(edge: .bottom, spacing: 8) { bottomChrome }
        }
        .latchScreen()
    }

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                LatchIconBadge(systemName: "figure.run", size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("RouteLatch")
                        .font(.headline)
                        .foregroundStyle(LatchColor.ink)
                    HStack(spacing: 4) {
                        Text("Get ready")
                        Image(systemName: "flame.fill")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LatchColor.accent)
                }
                Spacer(minLength: 0)
            }
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                .font(.subheadline)
                .foregroundStyle(LatchColor.muted)
            Text("Your routes")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(LatchColor.ink)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Label("Library", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LatchColor.ink)
                Spacer(minLength: 8)
                Text(model.routes.isEmpty ? "Saved" : "Ready")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LatchColor.canvas)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(LatchColor.ink, in: Capsule())
            }
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summaryCount)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(LatchColor.ink)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(summarySubtitle)
                        .font(.subheadline)
                        .foregroundStyle(LatchColor.muted)
                }
                Spacer(minLength: 8)
                if !model.routes.isEmpty {
                    routeDistanceBars
                }
            }
        }
        .padding(18)
        .latchCard()
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var summaryCount: String {
        if model.routes.isEmpty {
            return "\(model.completedRuns.count) runs"
        }
        return "\(model.routes.count) routes"
    }

    private var summarySubtitle: String {
        let savedDistance = model.routes.reduce(0) { $0 + $1.totalDistance }
        if model.routes.isEmpty {
            return "\(model.completedRuns.count) completed on this iPhone"
        }
        return "\(savedDistance.formattedDistance) saved · \(model.completedRuns.count) completed"
    }

    private var routeDistanceBars: some View {
        let distances = Array(model.routes.prefix(7).map(\.totalDistance))
        let peak = max(distances.max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(distances.enumerated()), id: \.offset) { _, distance in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(LatchColor.accent)
                    .frame(width: 8, height: max(10, 48 * distance / peak))
            }
        }
        .frame(height: 48, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            LatchIconBadge(systemName: "point.topleft.down.to.point.bottomright.curvepath", size: 68)
            Text("No Routes Yet")
                .font(.title3.bold())
                .foregroundStyle(LatchColor.ink)
            Text("Import a GPX course to keep it available on your phone and Apple Watch.")
                .font(.subheadline)
                .foregroundStyle(LatchColor.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .latchCard()
        .padding(.vertical, 4)
    }

    private var bottomChrome: some View {
        VStack(spacing: 8) {
            if let warning = model.storageWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(LatchColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(LatchColor.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("Storage warning: \(warning)")
            }
            actionBar
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            barAction(title: "Strava", systemImage: "bolt.horizontal.fill", emphasized: false) {
                showingStrava = true
            }
            .accessibilityLabel("Strava")
            if model.isImporting {
                VStack(spacing: 4) {
                    ProgressView()
                        .tint(LatchColor.accent)
                        .frame(width: 52, height: 36)
                    Text("Import")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LatchColor.muted)
                    Circle().fill(Color.clear).frame(width: 5, height: 5)
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Importing GPX")
            } else {
                barAction(title: "Import", systemImage: "square.and.arrow.down", emphasized: true) {
                    importing = true
                }
                .accessibilityLabel("Import GPX")
                .accessibilityHint("Choose a GPX course file")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .latchCard()
    }

    private func barAction(title: String, systemImage: String, emphasized: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(emphasized ? LatchColor.onAccent : LatchColor.accent)
                    .frame(width: 52, height: 36)
                    .background(emphasized ? LatchColor.accent : LatchColor.accentSoft, in: Capsule())
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(emphasized ? LatchColor.accent : LatchColor.muted)
                Circle()
                    .fill(emphasized ? LatchColor.accent : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(LatchColor.ink)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func routeRow(_ route: Route) -> some View {
        Button {
            selectedRoute = route
        } label: {
            routeCard(route)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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

    @ViewBuilder
    private func plainRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private func routeListPace(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        return String(format: "Target %d:%02d /km", rounded / 60, rounded % 60)
    }
}

extension Double {
    var formattedDistance: String { self >= 1000 ? String(format: "%.1f km", self / 1000) : String(format: "%.0f m", self) }
}
