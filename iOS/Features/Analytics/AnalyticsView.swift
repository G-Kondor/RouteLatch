import RouteLatchCore
import SwiftUI

struct AnalyticsView: View {
    @ObservedObject var model: PhoneRouteLibraryModel
    @ObservedObject var health: RunningHealthStore
    @Binding var tab: PhoneTab
    @Binding var range: AnalyticsRange
    @AppStorage("RouteLatch.analytics.age") private var storedAge = 0
    @State private var editingAge = false
    @State private var selectedZone: HeartRateZone?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    screenHeader("Analytics", subtitle: "Pace, effort, and heart-rate zones")
                    if model.areRunsReady, health.isLoading, !activities.isEmpty {
                        ProgressView("Reading Apple Health")
                            .tint(LatchColor.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let statusMessage = health.statusMessage {
                        statusBanner(statusMessage)
                    }
                    if !model.areRunsReady {
                        LibraryLoadingCard(title: "Loading your runs")
                    } else if activities.isEmpty {
                        if health.access == .requested && !health.hasFetched {
                            loadingCard
                        } else {
                            emptyState
                        }
                    } else {
                        if health.access == .notRequested {
                            healthBanner
                        } else if health.access == .unavailable {
                            unavailableNote
                        }
                        yearCard
                        rangePicker
                        if snapshot.runCount == 0 {
                            periodEmpty
                        } else {
                            trainingContent
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .scrollContentBackground(.hidden)
            .background(LatchColor.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .phoneChrome(tab: $tab, warning: model.storageWarning)
            .refreshable { await health.refresh(force: true) }
        }
        .latchScreen()
        .task { await health.refresh() }
        .onChange(of: range) { _, _ in
            selectedZone = nil
        }
        .sheet(isPresented: $editingAge) {
            HeartRateAgeSheet(storedAge: $storedAge)
        }
    }

    private var screen: AnalyticsScreen {
        let now = Date()
        let calendar = Calendar.current
        let minute = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)) ?? now
        let key = AnalyticsScreenKey(
            healthRevision: health.revision,
            libraryRevision: model.contentRevision,
            range: range,
            age: storedAge,
            minute: minute
        )
        let store = model.analyticsScreenStore
        if store.key == key, let cached = store.screen {
            return cached
        }
        let built = AnalyticsScreen.make(
            healthRuns: health.runs,
            recorded: model.completedRuns,
            range: range,
            storedAge: storedAge,
            now: now
        )
        store.key = key
        store.screen = built
        return built
    }

    private var activities: [AnalyticsActivity] { screen.activities }

    private var zoneSettings: HeartRateZoneSettings { screen.zoneSettings }

    private var snapshot: TrainingSnapshot { screen.snapshot }

    private var trainingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            summaryCard
            distanceCard
            if snapshot.buckets.contains(where: { $0.paceSecondsPerKilometer != nil }) {
                paceCard
            }
            heartCard
            metricGrid
            splitsCard
            runsCard
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 6) {
            ForEach(AnalyticsRange.allCases, id: \.rawValue) { item in
                let selected = range == item
                Button {
                    range = item
                } label: {
                    Text(rangeTitle(item))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(selected ? LatchColor.onAccent : LatchColor.ink)
                        .background(selected ? LatchColor.accent : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
            }
        }
        .padding(4)
        .latchGlass(radius: 24)
    }

    private var yearCard: some View {
        let grid = screen.year
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Year of activity")
                    .font(.headline)
                    .foregroundStyle(LatchColor.ink)
                Spacer(minLength: 8)
                Text(yearSummary(grid))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LatchColor.muted)
                    .multilineTextAlignment(.trailing)
            }
            ActivityYearChart(grid: grid)
            Text("Each square is a day over the last year.")
                .font(.caption)
                .foregroundStyle(LatchColor.muted)
        }
        .padding(18)
        .latchCard()
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(snapshot.distanceMeters.formattedDistance)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(LatchColor.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(summaryCaption)
                .font(.subheadline)
                .foregroundStyle(LatchColor.muted)
            HStack(spacing: 8) {
                summaryStat("Time", clock(snapshot.duration))
                summaryStat("Pace", pace(snapshot.averagePaceSecondsPerKilometer))
                summaryStat("Runs", "\(snapshot.runCount)")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .latchCard()
    }

    private var summaryCaption: String {
        let distance = originName(snapshot.distanceOrigin)
        let time = originName(snapshot.durationOrigin)
        if distance == time {
            return "Distance and time from \(distance)"
        }
        return "Distance from \(distance) · Time from \(time)"
    }

    private var distanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Distance")
                    .font(.headline)
                    .foregroundStyle(LatchColor.ink)
                Spacer(minLength: 8)
                Text(rangeTitle(range))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LatchColor.muted)
            }
            GradientTrendChart(samples: distanceSamples, showsBars: true)
        }
        .padding(18)
        .latchCard()
    }

    private var paceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Pace")
                    .font(.headline)
                    .foregroundStyle(LatchColor.ink)
                Spacer(minLength: 8)
                Text("Faster is higher")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LatchColor.muted)
            }
            GradientTrendChart(samples: paceSamples, showsBars: false)
        }
        .padding(18)
        .latchCard()
    }

    private var distanceSamples: [TrendChartSample] { screen.distanceSamples }

    private var paceSamples: [TrendChartSample] { screen.paceSamples }

    private var heartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Heart-rate zones")
                .font(.headline)
                .foregroundStyle(LatchColor.ink)
            if !snapshot.zones.isEmpty {
                zoneStack
            }
            if snapshot.zones.isEmpty {
                heartEmpty
            } else {
                ForEach(snapshot.zones) { share in
                    Button {
                        selectedZone = selectedZone == share.zone ? nil : share.zone
                    } label: {
                        zoneRow(share)
                            .padding(8)
                            .background(
                                selectedZone == share.zone ? LatchColor.accentSoft : Color.clear,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
                if let selectedZone, let share = snapshot.zones.first(where: { $0.zone == selectedZone }) {
                    ChartPointOverview(title: "\(share.zone.title) zone", rows: zoneDetails(share))
                }
                Text("Based on \(clock(snapshot.measuredHeartRate)) of heart-rate samples from \(originName(snapshot.heartRateOrigin)).")
                    .font(.caption)
                    .foregroundStyle(LatchColor.muted)
            }
            ageRow
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .latchCard()
    }

    private var heartEmpty: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let average = snapshot.activities.compactMap(\.averageHeartRate).first {
                Text("Average \(Int(average.rounded())) bpm")
                    .font(.title3.bold())
                    .foregroundStyle(LatchColor.ink)
                Text("Apple Health has an average, and the series is still too short to split into zones.")
                    .font(.subheadline)
                    .foregroundStyle(LatchColor.muted)
            } else {
                Text("No heart rate in this period")
                    .font(.title3.bold())
                    .foregroundStyle(LatchColor.ink)
                Text("Zones appear when a run includes a heart-rate series from Apple Health or from the Watch copy on this iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(LatchColor.muted)
            }
        }
    }

    private var ageRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(ageCopy)
                .font(.caption)
                .foregroundStyle(LatchColor.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Set age") { editingAge = true }
                .font(.caption.weight(.semibold))
                .foregroundStyle(LatchColor.accent)
        }
    }

    private var ageCopy: String {
        if let age = zoneSettings.age {
            return "Max heart rate is \(Int(zoneSettings.maxHeartRate.rounded())) bpm, from 220 − \(age)."
        }
        return "Max heart rate is 190 bpm until you set your age."
    }

    private var metricGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                metricTile(
                    "Effort",
                    snapshot.effort.map(String.init) ?? "—",
                    snapshot.effort == nil ? "Needs heart rate" : "Zone minutes, weighted 1–5",
                    "bolt.heart.fill"
                )
                metricTile(
                    "Cadence",
                    snapshot.averageCadenceStepsPerMinute.map { "\(Int($0.rounded()))" } ?? "—",
                    snapshot.averageCadenceStepsPerMinute == nil ? "No steps in Apple Health" : "Steps / min in Apple Health",
                    "shoeprints.fill"
                )
            }
            HStack(spacing: 12) {
                metricTile(
                    "Elevation",
                    snapshot.elevationGainMeters.map { "\(Int($0.rounded())) m" } ?? "—",
                    elevationDetail,
                    "mountain.2.fill"
                )
                metricTile(
                    "Calories",
                    snapshot.activeEnergyKilocalories.map { "\(Int($0.rounded()))" } ?? "—",
                    snapshot.activeEnergyKilocalories == nil ? "Not in Apple Health" : "Active energy in Apple Health",
                    "flame.fill"
                )
            }
            Text("Cadence and calories are read from Apple Health. Elevation uses Health when the workout includes it, and otherwise the climb on the route saved on this iPhone.")
                .font(.caption)
                .foregroundStyle(LatchColor.muted)
        }
    }

    private var elevationDetail: String {
        guard snapshot.elevationGainMeters != nil else { return "Not recorded" }
        if snapshot.elevationCount < snapshot.runCount {
            return "\(snapshot.elevationCount) of \(snapshot.runCount) runs · \(originName(snapshot.elevationOrigin))"
        }
        return originName(snapshot.elevationOrigin)
    }

    private var splitsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Splits")
                .font(.headline)
                .foregroundStyle(LatchColor.ink)
            if let name = snapshot.splitRunName {
                Text(splitSubtitle(name))
                    .font(.subheadline)
                    .foregroundStyle(LatchColor.muted)
            }
            if snapshot.splits.isEmpty {
                Text("This run has no route, so kilometer splits aren’t available.")
                    .font(.subheadline)
                    .foregroundStyle(LatchColor.muted)
            } else {
                SplitPaceChart(splits: snapshot.splits) { pace($0) }
                if snapshot.splits.count > 12 {
                    Text("\(snapshot.splits.count - 12) more splits")
                        .font(.caption)
                        .foregroundStyle(LatchColor.muted)
                }
                Text(splitSource)
                    .font(.caption)
                    .foregroundStyle(LatchColor.muted)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .latchCard()
    }

    private var runsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Runs")
                .font(.headline)
                .foregroundStyle(LatchColor.ink)
            ForEach(Array(snapshot.activities.prefix(10))) { activity in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(activity.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(LatchColor.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(activity.distanceMeters.formattedDistance)
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(LatchColor.ink)
                    }
                    HStack {
                        Text(activity.startedAt.formatted(date: .abbreviated, time: .shortened))
                        Spacer(minLength: 8)
                        Text(pace(activity.paceSecondsPerKilometer))
                    }
                    .font(.caption)
                    .foregroundStyle(LatchColor.muted)
                    Text(runOrigin(activity.primaryOrigin))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LatchColor.accent)
                }
                .padding(.vertical, 4)
            }
            if snapshot.activities.count > 10 {
                Text("Showing 10 of \(snapshot.activities.count) runs")
                    .font(.caption)
                    .foregroundStyle(LatchColor.muted)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .latchCard()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            LatchIconBadge(systemName: "chart.bar.fill", size: 64)
            Text("No runs yet")
                .font(.title3.bold())
                .foregroundStyle(LatchColor.ink)
            Text(emptyCopy)
                .font(.subheadline)
                .foregroundStyle(LatchColor.muted)
                .multilineTextAlignment(.center)
            if health.access == .notRequested {
                allowButton
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .latchCard()
    }

    private var emptyCopy: String {
        switch health.access {
        case .unavailable:
            "Apple Health isn’t available on this device. A run your Watch sends to this iPhone will show up here."
        case .notRequested:
            "Finish a run on Apple Watch. RouteLatch can read it from Apple Health, and it also keeps the copy your Watch sends to this iPhone."
        case .requested:
            "Apple Health has no running workouts, and none are saved on this iPhone. Finish a run on your Watch and it will show up here."
        }
    }

    private var periodEmpty: some View {
        VStack(spacing: 12) {
            LatchIconBadge(systemName: "calendar", size: 64)
            Text("No runs in this \(rangeTitle(range).lowercased())")
                .font(.title3.bold())
                .foregroundStyle(LatchColor.ink)
            Text("Try a longer range. Nothing here is filled in until a run falls inside it.")
                .font(.subheadline)
                .foregroundStyle(LatchColor.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .latchCard()
    }

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(LatchColor.accent)
            Text("Reading Apple Health")
                .font(.headline)
                .foregroundStyle(LatchColor.ink)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .latchCard()
    }

    private var healthBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple Health")
                .font(.headline)
                .foregroundStyle(LatchColor.ink)
            Text("Heart rate, cadence, elevation, and calories can be read from running workouts already in Apple Health.")
                .font(.subheadline)
                .foregroundStyle(LatchColor.muted)
            allowButton
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .latchCard()
    }

    private var unavailableNote: some View {
        Text("Apple Health isn’t available on this device. These numbers use runs saved on this iPhone.")
            .font(.caption)
            .foregroundStyle(LatchColor.muted)
    }

    private var allowButton: some View {
        Button {
            Task { await health.allowAccess() }
        } label: {
            Label("Allow Apple Health", systemImage: "heart.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .foregroundStyle(LatchColor.onAccent)
        .background(LatchColor.accent, in: Capsule())
        .disabled(health.isLoading)
        .opacity(health.isLoading ? 0.7 : 1)
    }

    private func statusBanner(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(LatchColor.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .latchGlass(radius: 16)
    }

    private func summaryStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(LatchColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(LatchColor.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(LatchColor.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metricTile(_ title: String, _ value: String, _ detail: String, _ systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(LatchColor.muted)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(LatchColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(LatchColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .latchCard()
        .accessibilityElement(children: .combine)
    }

    private func zoneRow(_ share: HeartRateZoneShare) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Z\(share.zone.rawValue)")
                    .font(.caption.bold())
                    .foregroundStyle(LatchColor.accent)
                    .frame(width: 36, height: 26)
                    .background(LatchColor.accentSoft, in: Capsule())
                VStack(alignment: .leading, spacing: 1) {
                    Text(share.zone.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LatchColor.ink)
                    Text(bpmRange(share))
                        .font(.caption2)
                        .foregroundStyle(LatchColor.muted)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(clock(share.duration))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(LatchColor.ink)
                    Text("\(Int((share.fraction * 100).rounded()))%")
                        .font(.caption2)
                        .foregroundStyle(LatchColor.muted)
                }
            }
            Capsule()
                .fill(LatchColor.chip)
                .frame(height: 8)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    LatchColor.accent.opacity(zoneOpacity(share.zone) * 0.45),
                                    LatchColor.accent.opacity(zoneOpacity(share.zone))
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .scaleEffect(x: share.fraction, y: 1, anchor: .leading)
                }
                .clipShape(Capsule())
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private func splitSubtitle(_ name: String) -> String {
        if let started = snapshot.splitRunStartedAt {
            return "\(name) · \(started.formatted(date: .abbreviated, time: .omitted))"
        }
        return name
    }

    private var splitSource: String {
        switch snapshot.splitOrigin {
        case .health:
            "From the Apple Health workout route."
        case .recordedRun:
            "From the route saved on this iPhone."
        case .combined:
            "From Apple Health and the route saved on this iPhone."
        case nil:
            ""
        }
    }

    private func bpmRange(_ share: HeartRateZoneShare) -> String {
        if let upper = share.upperBeatsPerMinute {
            return "\(share.lowerBeatsPerMinute)–\(upper) bpm"
        }
        return "\(share.lowerBeatsPerMinute)+ bpm"
    }

    private var zoneStack: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(snapshot.zones) { share in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    LatchColor.accent.opacity(max(0.28, zoneOpacity(share.zone) * 0.55)),
                                    LatchColor.accent.opacity(zoneOpacity(share.zone))
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: geo.size.width * share.fraction)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard geo.size.width > 0, let zone = zone(at: value.location.x, width: geo.size.width) else { return }
                        selectedZone = selectedZone == zone ? nil : zone
                    }
            )
        }
        .frame(height: 16)
        .background(LatchColor.chip)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private func zone(at x: CGFloat, width: CGFloat) -> HeartRateZone? {
        let fraction = min(1, max(0, x / width))
        var cursor = 0.0
        for share in snapshot.zones where share.fraction > 0 {
            cursor += share.fraction
            if fraction <= cursor {
                return share.zone
            }
        }
        return snapshot.zones.last { $0.fraction > 0 }?.zone
    }

    private func zoneDetails(_ share: HeartRateZoneShare) -> [ChartDetailRow] {
        [
            ChartDetailRow(label: "Time", value: clock(share.duration)),
            ChartDetailRow(label: "Share", value: "\(Int((share.fraction * 100).rounded()))%"),
            ChartDetailRow(label: "Range", value: bpmRange(share))
        ]
    }

    private func yearSummary(_ grid: ActivityYearGrid) -> String {
        let days = grid.activeDays == 1 ? "1 day" : "\(grid.activeDays) days"
        return "\(days) · \(grid.distanceMeters.formattedDistance)"
    }

    private func zoneOpacity(_ zone: HeartRateZone) -> Double {
        switch zone {
        case .recovery: 0.35
        case .endurance: 0.52
        case .tempo: 0.7
        case .threshold: 0.86
        case .anaerobic: 1
        }
    }

    private func rangeTitle(_ range: AnalyticsRange) -> String {
        switch range {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    private func originName(_ origin: AnalyticsOrigin?) -> String {
        switch origin {
        case .health: "Apple Health"
        case .recordedRun: "this iPhone"
        case .combined: "Apple Health and this iPhone"
        case nil: "these runs"
        }
    }

    private func runOrigin(_ origin: AnalyticsOrigin) -> String {
        switch origin {
        case .health: "Apple Health"
        case .recordedRun: "Saved on this iPhone"
        case .combined: "Apple Health and this iPhone"
        }
    }

    private func pace(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "— /km" }
        let rounded = Int(seconds.rounded())
        let minutes = rounded / 60
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d /km", minutes / 60, minutes % 60, rounded % 60)
        }
        return String(format: "%d:%02d /km", minutes, rounded % 60)
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3_600 {
            return String(format: "%d:%02d:%02d", total / 3_600, total % 3_600 / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct AnalyticsScreenKey: Equatable {
    let healthRevision: Int
    let libraryRevision: Int
    let range: AnalyticsRange
    let age: Int
    let minute: Date
}

@MainActor
final class AnalyticsScreenStore {
    fileprivate var key: AnalyticsScreenKey?
    fileprivate var screen: AnalyticsScreen?
}

private struct AnalyticsScreen {
    let activities: [AnalyticsActivity]
    let zoneSettings: HeartRateZoneSettings
    let snapshot: TrainingSnapshot
    let year: ActivityYearGrid
    let distanceSamples: [TrendChartSample]
    let paceSamples: [TrendChartSample]

    static func make(
        healthRuns: [ImportedHealthRun],
        recorded: [RecordedRun],
        range: AnalyticsRange,
        storedAge: Int,
        now: Date
    ) -> AnalyticsScreen {
        let zoneSettings = HeartRateZoneSettings(age: storedAge == 0 ? nil : storedAge)
        let activities = RunAnalytics.activities(health: healthRuns, recorded: recorded)
        let snapshot = RunAnalytics.snapshot(
            activities: activities,
            range: range,
            now: now,
            calendar: .current,
            zones: zoneSettings
        )
        return AnalyticsScreen(
            activities: activities,
            zoneSettings: zoneSettings,
            snapshot: snapshot,
            year: RunAnalytics.activityYear(activities: activities, now: now, calendar: .current),
            distanceSamples: distanceSamples(for: snapshot),
            paceSamples: paceSamples(for: snapshot)
        )
    }

    private static func distanceSamples(for snapshot: TrainingSnapshot) -> [TrendChartSample] {
        snapshot.buckets.enumerated().map { index, bucket in
            sample(
                snapshot: snapshot,
                index: index,
                bucket: bucket,
                value: bucket.distanceMeters,
                spoken: bucket.distanceMeters > 0 ? bucket.distanceMeters.formattedDistance : "No distance"
            )
        }
    }

    private static func paceSamples(for snapshot: TrainingSnapshot) -> [TrendChartSample] {
        let paces = snapshot.buckets.compactMap(\.paceSecondsPerKilometer)
        let slowest = paces.max() ?? 0
        return snapshot.buckets.enumerated().map { index, bucket in
            let bucketPace = bucket.paceSecondsPerKilometer
            let plotted = bucketPace.map { slowest - $0 + slowest * 0.2 }
            return sample(
                snapshot: snapshot,
                index: index,
                bucket: bucket,
                value: plotted,
                spoken: bucketPace.map { pace($0) } ?? "No pace"
            )
        }
    }

    private static func sample(
        snapshot: TrainingSnapshot,
        index: Int,
        bucket: DistanceBucket,
        value: Double?,
        spoken: String
    ) -> TrendChartSample {
        let end = bucketEnd(snapshot: snapshot, after: index)
        let detail = bucketDetails(snapshot: snapshot, bucket: bucket, ending: end)
        return TrendChartSample(
            id: index,
            label: bucket.label,
            title: detail.title,
            value: value,
            spoken: spoken,
            rows: detail.rows
        )
    }

    private static func bucketEnd(snapshot: TrainingSnapshot, after index: Int) -> Date {
        if index + 1 < snapshot.buckets.count {
            return snapshot.buckets[index + 1].start
        }
        return snapshot.windowEnd
    }

    private static func bucketDetails(
        snapshot: TrainingSnapshot,
        bucket: DistanceBucket,
        ending end: Date
    ) -> (title: String, rows: [ChartDetailRow]) {
        let matching = snapshot.activities.filter { $0.startedAt >= bucket.start && $0.startedAt < end }
        var rows = [
            ChartDetailRow(label: "Distance", value: bucket.distanceMeters > 0 ? bucket.distanceMeters.formattedDistance : "0 m"),
            ChartDetailRow(label: "Time", value: clock(bucket.duration)),
            ChartDetailRow(label: "Pace", value: pace(bucket.paceSecondsPerKilometer)),
            ChartDetailRow(label: "Runs", value: "\(matching.count)")
        ]
        if matching.count == 1 {
            rows.append(ChartDetailRow(label: "Run", value: matching[0].name))
        }
        let heartRates = matching.compactMap(\.averageHeartRate)
        if !heartRates.isEmpty {
            let average = heartRates.reduce(0, +) / Double(heartRates.count)
            rows.append(ChartDetailRow(label: "Heart rate", value: "\(Int(average.rounded())) bpm"))
        }
        let climbs = matching.compactMap(\.elevationGainMeters)
        if !climbs.isEmpty {
            rows.append(ChartDetailRow(label: "Elevation", value: "\(Int(climbs.reduce(0, +).rounded())) m"))
        }
        return (bucket.spokenLabel, rows)
    }

    private static func pace(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "— /km" }
        let rounded = Int(seconds.rounded())
        let minutes = rounded / 60
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d /km", minutes / 60, minutes % 60, rounded % 60)
        }
        return String(format: "%d:%02d /km", minutes, rounded % 60)
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3_600 {
            return String(format: "%d:%02d:%02d", total / 3_600, total % 3_600 / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct HeartRateAgeSheet: View {
    @Binding var storedAge: Int
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Int

    init(storedAge: Binding<Int>) {
        _storedAge = storedAge
        let current = storedAge.wrappedValue
        let initial = (HeartRateZoneSettings.minimumAge...HeartRateZoneSettings.maximumAge).contains(current) ? current : 30
        _draft = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Zones use 220 minus your age. They stay on a 190 bpm max until you save an age.")
                    .font(.subheadline)
                    .foregroundStyle(LatchColor.muted)
                Stepper(value: $draft, in: HeartRateZoneSettings.minimumAge...HeartRateZoneSettings.maximumAge) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Age \(draft)")
                            .font(.title3.bold())
                            .foregroundStyle(LatchColor.ink)
                        Text("Max heart rate \(220 - draft) bpm")
                            .font(.subheadline)
                            .foregroundStyle(LatchColor.muted)
                    }
                }
                Button {
                    storedAge = draft
                    dismiss()
                } label: {
                    Text("Save age")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(LatchColor.onAccent)
                .background(LatchColor.accent, in: Capsule())
                Button("Use 190 bpm") {
                    storedAge = 0
                    dismiss()
                }
                .font(.headline)
                .foregroundStyle(LatchColor.ink)
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(LatchColor.canvas.opacity(0.72))
            }
            .navigationTitle("Heart-rate max")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
