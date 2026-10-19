import MapKit
import RouteLatchCore
import SwiftUI

struct NavigationView: View {
    @StateObject private var model: RouteNavigationModel
    @State private var mapPosition: MapCameraPosition
    @State private var hasCenteredOnRunner = false
    @State private var setupPage = 0
    /// In-run pager index. 1 is the glance page; 0 is the controls page to its left.
    @State private var runPage = 1
    @State private var confirmingFinish = false

    init(route: Route? = nil, freeRunTargetPaceSecondsPerKilometer: Double? = nil) {
        _model = StateObject(wrappedValue: RouteNavigationModel(
            route: route,
            freeRunTargetPaceSecondsPerKilometer: freeRunTargetPaceSecondsPerKilometer
        ))
        if let route {
            let bounds = route.bounds
            _mapPosition = State(initialValue: .region(MKCoordinateRegion(
                center: .init(
                    latitude: (bounds.minLatitude + bounds.maxLatitude) / 2,
                    longitude: (bounds.minLongitude + bounds.maxLongitude) / 2
                ),
                span: .init(
                    latitudeDelta: max(0.005, (bounds.maxLatitude - bounds.minLatitude) * 1.3),
                    longitudeDelta: max(0.005, (bounds.maxLongitude - bounds.minLongitude) * 1.3)
                )
            )))
        } else {
            _mapPosition = State(initialValue: .userLocation(followsHeading: true, fallback: .automatic))
        }
    }

    private var isRunning: Bool {
        model.phase == .active || model.phase == .paused
    }

    var body: some View {
        Group {
            if isRunning {
                runPager
            } else {
                setupPager
            }
        }
        .containerBackground(.black, for: .navigation)
        .navigationBarBackButtonHidden(hidesRunChrome)
        .toolbar(hidesRunChrome ? Visibility.hidden : Visibility.automatic, for: .navigationBar)
        .alert("Run Error", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK") {} } message: { Text(model.errorMessage ?? "Unknown error") }
        .alert("Finish Run?", isPresented: $confirmingFinish) {
            Button("Finish", role: .destructive) { model.finish() }
            Button("Keep Running", role: .cancel) {}
        } message: {
            Text("The workout and the route you actually ran will be saved to Health.")
        }
        .onChange(of: model.phase) { _, phase in
            switch phase {
            case .starting:
                runPage = 1
            case .ready, .finishing, .finished:
                setupPage = 0
                runPage = 1
            case .active, .paused:
                break
            }
        }
    }

    private var hidesRunChrome: Bool {
        switch model.phase {
        case .starting, .active, .paused, .finishing: true
        case .ready, .finished: false
        }
    }

    private var setupPager: some View {
        TabView(selection: $setupPage) {
            workoutView.tag(0)
            if model.isGuidedRun {
                mapView.tag(1)
            }
            metricsView.tag(model.isGuidedRun ? 2 : 1)
        }
        .tabViewStyle(.verticalPage)
    }

    /// Controls sit on the left page so a right swipe from the glance page reveals them.
    private var runPager: some View {
        TabView(selection: $runPage) {
            runControls.tag(0)
            glanceView.tag(1)
            if model.isGuidedRun {
                mapView.tag(2)
            }
            metricsView.tag(model.isGuidedRun ? 3 : 2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
    }

    private var mapView: some View {
        Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
            if let route = model.route {
                ForEach(Array(route.segments.enumerated()), id: \.offset) { _, segment in
                    MapPolyline(coordinates: segment.points.map { .init(latitude: $0.latitude, longitude: $0.longitude) })
                        .stroke(.orange, lineWidth: 4)
                }
                Marker("Start", systemImage: "flag.fill", coordinate: .init(latitude: route.start.latitude, longitude: route.start.longitude)).tint(.green)
                Marker("Finish", systemImage: "flag.checkered", coordinate: .init(latitude: route.finish.latitude, longitude: route.finish.longitude)).tint(.red)
            }
            if let location = model.location { Annotation("You", coordinate: location.coordinate) { Image(systemName: "location.fill").foregroundStyle(.blue).padding(4).background(.white, in: Circle()) } }
        }
        .accessibilityLabel(model.isGuidedRun ? "Route map and current position" : "Current running position")
        .safeAreaInset(edge: .bottom, spacing: 4) {
            if model.location != nil {
                Button {
                    mapPosition = .userLocation(followsHeading: true, fallback: mapPosition)
                } label: {
                    Label("Recenter", systemImage: "location.fill")
                }
                .buttonStyle(WatchRunButtonStyle(fill: .orange, foreground: .black))
                .frame(maxWidth: .infinity)
                .frame(height: 84)
                .accessibilityLabel("Recenter map on runner")
            }
        }
        .overlay(alignment: .top) {
            courseAlertBanner
                .padding(.top, 4)
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
                metric("Distance", watchDistance(model.actualDistance))
                metric("Elapsed", Duration.seconds(model.elapsed).formatted(.time(pattern: .minuteSecond)))
                metric("Average pace", model.averagePace.map(watchPace) ?? "—")
                if let route = model.route {
                    metric("Route progress", String(format: "%.0f%%", (model.match?.progress ?? 0) * 100))
                    metric("Remaining", watchDistance(max(0, route.totalDistance - (model.match?.distanceAlongRoute ?? 0))))
                    metric("Off course", watchDistance(model.match?.distanceFromRoute ?? 0))
                }
                if let target = model.targetPaceSecondsPerKilometer {
                    metric("Target pace", watchPace(target))
                }
                if let pace = model.paceProgress {
                    metric("Schedule", scheduleText(pace.scheduleDelta))
                    metric("Vs plan", watchPercent(pace.adherencePercent))
                    if model.isGuidedRun { metric("Projected", watchDuration(pace.projectedDuration)) }
                }
                if let heartRate = model.heartRate { metric("Heart rate", String(format: "%.0f bpm", heartRate)) }
            }.padding(.horizontal, 4)
        }
        .overlay(alignment: .top) {
            courseAlertBanner
        }
    }

    private var status: some View {
        Group {
            if model.match == nil {
                Label(model.phase == .active ? "TRACKING RUN" : "WAITING FOR GPS", systemImage: model.phase == .active ? "location.fill" : "location.slash")
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

    @ViewBuilder
    private var courseAlertBanner: some View {
        if model.isOffCourse {
            alertCapsule("OFF COURSE", fill: .red, foreground: .white)
        } else if model.isBehindPace {
            alertCapsule("BEHIND PACE", fill: .yellow, foreground: .black)
        }
    }

    private func alertCapsule(_ title: String, fill: Color, foreground: Color) -> some View {
        Text(title)
            .font(.caption2.bold())
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(fill, in: Capsule())
            .accessibilityLabel(title)
    }

    private var workoutView: some View {
        Group {
            switch model.phase {
            case .ready:
                readyWorkout
            case .starting:
                startingWorkout
            case .active, .paused:
                glanceView
            case .finishing:
                ProgressView("Saving…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .finished:
                finishedWorkout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var readyWorkout: some View {
        VStack(spacing: 6) {
            Text(model.runName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: model.isGuidedRun ? "location.fill" : "figure.run")
                .font(.title3)
                .foregroundStyle(.orange)
            Button { model.start() } label: {
                VStack(spacing: 4) {
                    Image(systemName: "figure.run")
                        .font(.title2)
                    Text("Start Run")
                }
            }
            .buttonStyle(WatchRunButtonStyle(fill: .orange, foreground: .black))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var startingWorkout: some View {
        VStack(spacing: 6) {
            ProgressView(model.startStage?.message ?? "Starting…")
                .font(.caption)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if model.startStage != .workout {
                Button("Cancel", role: .cancel) { model.cancelStart() }
                    .buttonStyle(WatchRunButtonStyle(fill: Color(white: 0.28), foreground: .white))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Cancel start")
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var runControls: some View {
        VStack(spacing: 8) {
            Text(model.runName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            runControlButton(
                title: model.phase == .active ? "Pause" : "Resume",
                systemImage: model.phase == .active ? "pause.fill" : "play.fill",
                fill: model.phase == .active ? .yellow : .green,
                foreground: .black,
                accessibilityLabel: model.phase == .active ? "Pause run" : "Resume run"
            ) {
                if model.phase == .active {
                    model.pause()
                } else {
                    model.resume()
                }
            }
            runControlButton(
                title: "Finish",
                systemImage: "stop.fill",
                fill: .red,
                foreground: .white,
                accessibilityLabel: "Finish run"
            ) {
                confirmingFinish = true
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func runControlButton(
        title: String,
        systemImage: String,
        fill: Color,
        foreground: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title)
                Text(title)
                    .font(.headline)
            }
        }
        .buttonStyle(WatchRunButtonStyle(fill: fill, foreground: foreground))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(accessibilityLabel)
    }

    private var glanceView: some View {
        ViewThatFits(in: .vertical) {
            glanceStack(timeSize: 44)
            glanceStack(timeSize: 34)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(glanceAccessibilityLabel)
        .accessibilityHint("Swipe right for pause and finish")
    }

    private func glanceStack(timeSize: CGFloat) -> some View {
        VStack(spacing: 1) {
            Text(glanceStatus.title)
                .font(.caption2.bold())
                .foregroundStyle(glanceStatus.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(watchDuration(model.elapsed))
                .font(.system(size: timeSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(watchDistance(model.actualDistance))
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(.green)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if model.targetPaceSecondsPerKilometer != nil {
                paceComparison
            }
            secondaryMetrics
        }
    }

    private var paceComparison: some View {
        HStack(spacing: 6) {
            if let pace = model.paceProgress {
                glanceStat(
                    title: paceCaption(pace.scheduleDelta),
                    value: signedSchedule(pace.scheduleDelta),
                    color: paceTone(pace.scheduleDelta)
                )
                glanceStat(
                    title: planCaption,
                    value: watchPercent(pace.adherencePercent),
                    color: paceTone(pace.scheduleDelta)
                )
            } else {
                glanceStat(title: "BEHIND", value: "—", color: .white)
                glanceStat(title: planCaption, value: "—", color: .white)
            }
        }
    }

    private var secondaryMetrics: some View {
        HStack(spacing: 6) {
            glanceStat(
                title: "AVG /KM",
                value: model.averagePace.map { watchPaceMinutes($0) } ?? "—",
                color: .orange
            )
            if let heartRate = model.heartRate {
                glanceStat(
                    title: "BPM",
                    value: String(format: "%.0f", heartRate),
                    color: .red
                )
            }
        }
    }

    private func glanceStat(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var glanceStatus: (title: String, color: Color) {
        if model.phase == .paused, model.isOffCourse {
            return ("PAUSED · OFF COURSE", .red)
        }
        if model.phase == .paused {
            return ("PAUSED", .yellow)
        }
        if model.isOffCourse {
            return ("OFF COURSE", .red)
        }
        guard let pace = model.paceProgress else {
            return ("RUNNING", .white)
        }
        if pace.scheduleDelta >= 1 { return ("BEHIND", .yellow) }
        if pace.scheduleDelta <= -1 { return ("AHEAD", .green) }
        return ("ON PACE", .green)
    }

    private var glanceAccessibilityLabel: String {
        var parts = [
            glanceStatus.title,
            "Elapsed \(watchDuration(model.elapsed))",
            "Distance \(watchDistance(model.actualDistance))"
        ]
        if let pace = model.paceProgress {
            parts.append(scheduleText(pace.scheduleDelta))
            parts.append("\(watchPercent(pace.adherencePercent)) of planned pace")
        } else if model.targetPaceSecondsPerKilometer != nil {
            parts.append("Pace comparison waiting for distance")
        }
        if let average = model.averagePace {
            parts.append("Average pace \(watchPace(average))")
        }
        if let heartRate = model.heartRate {
            parts.append(String(format: "Heart rate %.0f beats per minute", heartRate))
        }
        return parts.joined(separator: ", ")
    }

    private var planCaption: String {
        guard let target = model.targetPaceSecondsPerKilometer else { return "OF PLAN" }
        return "OF \(watchPaceMinutes(target))"
    }

    private var finishedWorkout: some View {
        ScrollView {
            VStack(spacing: 7) {
                if let summary = model.summary {
                    Label(summary.workoutSaved ? "Run Saved" : "Run Ended", systemImage: summary.workoutSaved ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(summary.workoutSaved ? .green : .yellow)
                    metric("Elapsed", Duration.seconds(summary.elapsed).formatted(.time(pattern: .minuteSecond)))
                    metric("Distance", watchDistance(summary.actualDistance))
                    metric("Average pace", summary.averagePace.map(watchPace) ?? "—")
                    if let pace = summary.paceProgress {
                        metric("Schedule", scheduleText(pace.scheduleDelta))
                        metric("Vs plan", watchPercent(pace.adherencePercent))
                        if model.isGuidedRun { metric("Projected", watchDuration(pace.projectedDuration)) }
                    }
                    if let heartRate = summary.heartRate { metric("Heart rate", String(format: "%.0f bpm", heartRate)) }
                    if summary.workoutSaved, !summary.routeSaved {
                        Text("Workout saved without a location route.").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 4)
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

    private func signedSchedule(_ delta: TimeInterval) -> String {
        if abs(delta) < 1 { return "0:00" }
        return (delta > 0 ? "+" : "-") + watchDuration(abs(delta))
    }

    private func paceCaption(_ delta: TimeInterval) -> String {
        if abs(delta) < 1 { return "ON PLAN" }
        return delta > 0 ? "BEHIND" : "AHEAD"
    }

    private func paceTone(_ delta: TimeInterval) -> Color {
        if delta >= 1 { return .yellow }
        if delta <= -1 { return .green }
        return .white
    }

    private func watchPercent(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return "\(min(999, max(0, Int(value.rounded()))))%"
    }

    private func watchPaceMinutes(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        let rounded = Int(seconds.rounded())
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }
}
