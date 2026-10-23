import RouteLatchCore
import SwiftUI
import UniformTypeIdentifiers

enum PhoneTab: String, CaseIterable, Identifiable {
    case home
    case routes
    case runs
    case analytics
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .routes: "Routes"
        case .runs: "Runs"
        case .analytics: "Analytics"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .routes: "map.fill"
        case .runs: "figure.run"
        case .analytics: "chart.bar.fill"
        case .settings: "gearshape.fill"
        }
    }
}

struct PhoneShellView: View {
    @ObservedObject var model: PhoneRouteLibraryModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = PhoneTab.home
    @State private var importing = false
    @State private var homeRoute: Route?
    @State private var libraryRoute: Route?
    @State private var analyticsRange = AnalyticsRange.week
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue

    var body: some View {
        selectedPage
            .latchScreen()
        .fileImporter(isPresented: $importing, allowedContentTypes: [.gpx, .xml], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { model.importRoute(from: url) }
            if case .failure(let error) = result { model.errorMessage = error.localizedDescription }
        }
        .alert("Couldn’t Complete Action", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
        .alert("Strava Error", isPresented: Binding(get: { model.strava.errorMessage != nil }, set: { if !$0 { model.strava.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.strava.errorMessage ?? "Unknown error")
        }
        .preferredColorScheme(AppAppearance.stored(appearanceRaw).colorScheme)
        .onAppear { publishAppearance() }
        .onChange(of: appearanceRaw) { _, _ in publishAppearance() }
        .onChange(of: colorScheme) { _, _ in publishAppearance() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { publishAppearance() }
        }
    }

    private func publishAppearance() {
        let preference = AppAppearance.stored(appearanceRaw)
        let phoneScheme: ResolvedAppearance
        switch colorScheme {
        case .dark:
            phoneScheme = .dark
        case .light:
            phoneScheme = .light
        @unknown default:
            phoneScheme = .light
        }
        model.syncWatchAppearance(
            preference: preference,
            resolved: ResolvedAppearance.matching(preference: preference, phoneScheme: phoneScheme)
        )
    }

    /// One page at a time. Hidden tabs used to stay in the tree, so opening the app built
    /// Analytics (and started Apple Health) and every menu change rebuilt all five pages.
    @ViewBuilder
    private var selectedPage: some View {
        switch tab {
        case .home:
            DashboardView(model: model, tab: $tab, importing: $importing, selectedRoute: $homeRoute)
        case .routes:
            RouteLibraryView(model: model, tab: $tab, importing: $importing, selectedRoute: $libraryRoute)
        case .runs:
            CompletedRunsView(model: model, tab: $tab)
        case .analytics:
            AnalyticsView(model: model, health: model.health, tab: $tab, range: $analyticsRange)
        case .settings:
            PhoneSettingsView(model: model, tab: $tab)
        }
    }
}

struct LibraryLoadingCard: View {
    var title = "Loading your courses"

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(LatchColor.accent)
            Text(title)
                .font(.headline)
                .foregroundStyle(LatchColor.ink)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .latchCard()
    }
}

struct PhoneTabBar: View {
    @Binding var selection: PhoneTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PhoneTab.allCases) { item in
                let selected = selection == item
                Button {
                    selection = item
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.systemImage)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(selected ? LatchColor.onAccent : LatchColor.muted)
                            .frame(width: 44, height: 32)
                            .background(selected ? LatchColor.accent : Color.clear, in: Capsule())
                        Text(item.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(selected ? LatchColor.accent : LatchColor.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Circle()
                            .fill(selected ? LatchColor.accent : Color.clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .latchGlass(radius: 32, interactive: true)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}

extension View {
    func phoneChrome(tab: Binding<PhoneTab>, warning: String?) -> some View {
        safeAreaInset(edge: .bottom, spacing: 8) {
            VStack(spacing: 8) {
                if let warning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(LatchColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .latchGlass(radius: 16)
                        .padding(.horizontal, 16)
                        .accessibilityLabel("Storage warning: \(warning)")
                }
                PhoneTabBar(selection: tab)
            }
        }
    }
}

struct CompletedRunsView: View {
    @ObservedObject var model: PhoneRouteLibraryModel
    @Binding var tab: PhoneTab
    @State private var runToDelete: RecordedRun?

    var body: some View {
        NavigationStack {
            List {
                screenHeader("Runs", subtitle: "Finished on your Watch")
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                if !model.areRunsReady {
                    LibraryLoadingCard(title: "Loading your runs")
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else if model.completedRuns.isEmpty {
                    emptyRuns
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
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
                }
            }
            .listStyle(.plain)
            .listSectionSeparator(.hidden)
            .scrollContentBackground(.hidden)
            .background(LatchColor.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .phoneChrome(tab: $tab, warning: model.storageWarning)
            .alert("Delete Completed Run?", isPresented: Binding(get: { runToDelete != nil }, set: { if !$0 { runToDelete = nil } })) {
                Button("Delete", role: .destructive) { if let runToDelete { model.delete(runToDelete) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes RouteLatch’s local TCX copy. It does not delete the workout from Health or Strava.")
            }
        }
        .latchScreen()
    }

    private var emptyRuns: some View {
        VStack(spacing: 12) {
            LatchIconBadge(systemName: "applewatch", size: 64)
            Text("No runs yet")
                .font(.title3.bold())
                .foregroundStyle(LatchColor.ink)
            Text("Finish a free run or a guided course on Apple Watch. It will show up here, ready to share or upload to Strava.")
                .font(.subheadline)
                .foregroundStyle(LatchColor.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .latchCard()
    }
}

struct PhoneSettingsView: View {
    @ObservedObject var model: PhoneRouteLibraryModel
    @Binding var tab: PhoneTab
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue

    private var appearanceSelection: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance.stored(appearanceRaw) },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    screenHeader("Settings", subtitle: "Connections stay out of the way")
                    appearanceCard
                    StravaSettingsView(strava: model.strava, pendingRuns: model.completedRuns)
                    watchWorkflowCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .scrollContentBackground(.hidden)
            .background(LatchColor.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .phoneChrome(tab: $tab, warning: model.storageWarning)
        }
        .latchScreen()
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance")
                .font(.headline)
                .foregroundStyle(LatchColor.ink)
            Text("Light and dark are used here and on Apple Watch. System keeps both matched to this iPhone.")
                .font(.subheadline)
                .foregroundStyle(LatchColor.muted)
            Picker("Appearance", selection: appearanceSelection) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .latchCard()
    }

    private var watchWorkflowCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How a course gets to your wrist")
                .font(.headline)
                .foregroundStyle(LatchColor.ink)
            workflowStep("1", "Import a GPX course on this iPhone.")
            workflowStep("2", "Send it to Apple Watch. That is the step that matters.")
            workflowStep("3", "Start the run on your Watch. The phone can stay behind.")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .latchCard()
    }

    private func workflowStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(LatchColor.onAccent)
                .frame(width: 22, height: 22)
                .background(LatchColor.accent, in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(LatchColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

func screenHeader(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title)
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .foregroundStyle(LatchColor.ink)
            .accessibilityAddTraits(.isHeader)
        Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(LatchColor.muted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 8)
}
