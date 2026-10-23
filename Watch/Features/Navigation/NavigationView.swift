import MapKit
import RouteLatchCore
import SwiftUI

struct NavigationView: View {
    @StateObject private var model: RouteNavigationModel
    @EnvironmentObject private var anchor: WorkoutSessionAnchor
    private let onClose: () -> Void

    init(
        route: Route? = nil,
        freeRunTargetPaceSecondsPerKilometer: Double? = nil,
        onClose: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: RouteNavigationModel(
            route: route,
            freeRunTargetPaceSecondsPerKilometer: freeRunTargetPaceSecondsPerKilometer
        ))
        self.onClose = onClose
    }

    var body: some View {
        RunScreen(model: model)
            .interactiveDismissDisabled(model.keepsDisplay)
            .onAppear { anchor.present(model, onClose: onClose) }
            .onDisappear { anchor.releaseIfNotRunning(model) }
    }
}

struct RunScreen: View {
    @ObservedObject var model: RouteNavigationModel
    @EnvironmentObject private var anchor: WorkoutSessionAnchor
    @Environment(\.latchColor) private var latch
    @State private var mapPosition: MapCameraPosition
    @State private var hasCenteredOnRunner = false
    @State private var setupPage = 0
    /// In-run pager index. 1 is the glance page; 0 is the controls page to its left.
    @State private var runPage = 1
    @State private var confirmingFinish = false

    init(model: RouteNavigationModel) {
        self.model = model
        if let route = model.route {
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
        .containerBackground(latch.canvas, for: .navigation)
        .background(latch.canvas)
        .tint(latch.accent)
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
        .onChange(of: model.kilometerSign) { _, sign in
            guard let sign else { return }
            AccessibilityNotification.Announcement("Kilometer \(sign.index) closed, split \(watchDuration(sign.splitDuration))").post()
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
        .latchTabPage()
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
        .latchTabPage()
    }

    private var mapView: some View {
        Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
            if let route = model.route {
                ForEach(Array(route.segments.enumerated()), id: \.offset) { _, segment in
                    MapPolyline(coordinates: segment.points.map { .init(latitude: $0.latitude, longitude: $0.longitude) })
                        .stroke(latch.accent, lineWidth: 4)
                }
                Marker("Start", systemImage: "flag.fill", coordinate: .init(latitude: route.start.latitude, longitude: route.start.longitude)).tint(latch.accent)
                Marker("Finish", systemImage: "flag.checkered", coordinate: .init(latitude: route.finish.latitude, longitude: route.finish.longitude)).tint(.red)
            }
            if let location = model.location { Annotation("You", coordinate: location.coordinate) { Image(systemName: "location.fill").foregroundStyle(latch.accent).padding(4).background(latch.card, in: Circle()) } }
        }
        .accessibilityLabel(model.isGuidedRun ? "Route map and current position" : "Current running position")
        .safeAreaInset(edge: .bottom, spacing: 4) {
            if model.location != nil {
                Button {
                    mapPosition = .userLocation(followsHeading: true, fallback: mapPosition)
                } label: {
                    Label("Recenter", systemImage: "location.fill")
                }
                .buttonStyle(WatchRunButtonStyle(fill: latch.accent, foreground: latch.onAccent))
                .frame(maxWidth: .infinity)
                .frame(height: 84)
                .accessibilityLabel("Recenter map on runner")
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 4) {
                kilometerSignBanner
                courseAlertBanner
            }
            .padding(.top, 4)
        }
        .latchTabPage()
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
                metric("Distance", watchDistance(model.actualDistance), valueFont: .title2.bold().monospacedDigit())
                metric("Elapsed", Duration.seconds(model.elapsed).formatted(.time(pattern: .minuteSecond)), valueFont: .body.bold().monospacedDigit())
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
            }
            .padding(8)
            .latchCard()
            .padding(.horizontal, 2)
        }
        .overlay(alignment: .top) {
            VStack(spacing: 4) {
                kilometerSignBanner
                courseAlertBanner
            }
        }
        .latchTabPage()
    }

    private var status: some View {
        Group {
            if model.isAcquiringGPS, model.phase == .active {
                Label("ACQUIRING GPS", systemImage: "location.slash")
                    .foregroundStyle(latch.muted)
            } else if model.match == nil {
                Label(model.phase == .active ? "TRACKING RUN" : "WAITING FOR GPS", systemImage: model.phase == .active ? "location.fill" : "location.slash")
                    .foregroundStyle(latch.accent)
            } else if model.isOffCourse {
                Label("OFF COURSE", systemImage: "exclamationmark.triangle.fill").foregroundStyle(latch.danger)
            } else if model.isBehindPace {
                Label("BEHIND GOAL", systemImage: "clock.badge.exclamationmark.fill").foregroundStyle(latch.accent)
            } else {
                Label("ON ROUTE", systemImage: "checkmark.circle.fill").foregroundStyle(latch.accent)
            }
        }
        .font(.title3.bold())
    }

    @ViewBuilder
    private var courseAlertBanner: some View {
        if model.isOffCourse {
            alertCapsule("OFF COURSE", fill: latch.danger, foreground: latch.onDanger)
        } else if model.isAcquiringGPS, model.phase == .active {
            alertCapsule("ACQUIRING GPS", fill: latch.chip, foreground: latch.ink)
        } else if model.isBehindPace {
            alertCapsule("BEHIND PACE", fill: latch.accent, foreground: latch.onAccent)
        }
    }

    private func alertCapsule(_ title: String, fill: Color, foreground: Color) -> some View {
        Text(title)
            .font(.caption.bold())
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
                    .tint(latch.accent)
                    .foregroundStyle(latch.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .finished:
                finishedWorkout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .latchTabPage()
    }

    private var readyWorkout: some View {
        VStack(spacing: 6) {
            Text(model.runName)
                .font(.caption2)
                .foregroundStyle(latch.muted)
                .lineLimit(1)
            LatchIconBadge(systemName: model.isGuidedRun ? "location.fill" : "figure.run", size: 36)
            Button { model.start() } label: {
                VStack(spacing: 4) {
                    Image(systemName: "figure.run")
                        .font(.title2)
                    Text("Start Run")
                }
            }
            .buttonStyle(WatchRunButtonStyle(fill: latch.accent, foreground: latch.onAccent))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var startingWorkout: some View {
        VStack(spacing: 6) {
            ProgressView(model.startStage?.message ?? "Starting…")
                .font(.caption)
                .tint(latch.accent)
                .foregroundStyle(latch.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if model.startStage != .workout {
                Button("Cancel", role: .cancel) { model.cancelStart() }
                    .buttonStyle(WatchRunButtonStyle(fill: latch.chip, foreground: latch.ink))
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
                .foregroundStyle(latch.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            runControlButton(
                title: model.phase == .active ? "Pause" : "Resume",
                systemImage: model.phase == .active ? "pause.fill" : "play.fill",
                fill: latch.accent,
                foreground: latch.onAccent,
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
                fill: latch.danger,
                foreground: latch.onDanger,
                accessibilityLabel: "Finish run"
            ) {
                confirmingFinish = true
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            kilometerSignBanner
                .padding(.top, 2)
        }
        .latchTabPage()
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
            glanceStack(timeSize: 26, distanceSize: 42, statSize: 22, labelSize: 12)
            glanceStack(timeSize: 20, distanceSize: 34, statSize: 20, labelSize: 11)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(glanceAccessibilityLabel)
        .accessibilityHint("Swipe right for pause and finish")
        .latchTabPage()
    }

    private func glanceStack(timeSize: CGFloat, distanceSize: CGFloat, statSize: CGFloat, labelSize: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(glanceStatus.title)
                .font(.system(size: labelSize, weight: .bold))
                .foregroundStyle(glanceStatus.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let sign = model.kilometerSign {
                kilometerSignBadge(sign, numberSize: labelSize + 4)
            }
            Text(watchDuration(model.elapsed))
                .font(.system(size: timeSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(latch.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            distanceReadout(numberSize: distanceSize)
            VStack(spacing: 1) {
                if model.targetPaceSecondsPerKilometer != nil {
                    paceComparison(statSize: statSize, labelSize: labelSize)
                }
                secondaryMetrics(statSize: statSize, labelSize: labelSize)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .background(latch.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .animation(.easeOut(duration: 0.2), value: model.kilometerSign)
    }

    @ViewBuilder
    private var kilometerSignBanner: some View {
        if let sign = model.kilometerSign {
            kilometerSignBadge(sign, numberSize: 15)
        }
    }

    private func kilometerSignBadge(_ sign: KilometerClosure, numberSize: CGFloat) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "flag.fill")
                .font(.system(size: max(11, numberSize - 3), weight: .bold))
            Text("KM \(sign.index)")
                .font(.system(size: numberSize, weight: .bold, design: .rounded))
            Text(watchDuration(sign.splitDuration))
                .font(.system(size: max(11, numberSize - 2), weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(latch.onAccent)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(latch.accent, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kilometer \(sign.index) closed")
        .accessibilityValue("Split \(watchDuration(sign.splitDuration))")
    }

    private func paceComparison(statSize: CGFloat, labelSize: CGFloat) -> some View {
        HStack(spacing: 6) {
            if let pace = model.paceProgress {
                glanceStat(
                    title: paceCaption(pace.scheduleDelta),
                    value: signedSchedule(pace.scheduleDelta),
                    color: paceTone(pace.scheduleDelta),
                    statSize: statSize,
                    labelSize: labelSize
                )
                glanceStat(
                    title: planCaption,
                    value: watchPercent(pace.adherencePercent),
                    color: paceTone(pace.scheduleDelta),
                    statSize: statSize,
                    labelSize: labelSize
                )
            } else {
                glanceStat(title: "BEHIND", value: "—", color: latch.ink, statSize: statSize, labelSize: labelSize)
                glanceStat(title: planCaption, value: "—", color: latch.ink, statSize: statSize, labelSize: labelSize)
            }
        }
    }

    private func secondaryMetrics(statSize: CGFloat, labelSize: CGFloat) -> some View {
        HStack(spacing: 6) {
            glanceStat(
                title: "AVG /KM",
                value: model.averagePace.map { watchPaceMinutes($0) } ?? "—",
                color: latch.ink,
                statSize: statSize,
                labelSize: labelSize
            )
            if let heartRate = model.heartRate {
                glanceStat(
                    title: "BPM",
                    value: String(format: "%.0f", heartRate),
                    color: latch.danger,
                    statSize: statSize,
                    labelSize: labelSize
                )
            }
        }
    }

    private func glanceStat(title: String, value: String, color: Color, statSize: CGFloat, labelSize: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: statSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: labelSize, weight: .semibold))
                .foregroundStyle(latch.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var glanceStatus: (title: String, color: Color) {
        if model.phase == .paused, model.isOffCourse {
            return ("PAUSED · OFF COURSE", latch.danger)
        }
        if model.phase == .paused {
            return ("PAUSED", latch.accent)
        }
        if model.isAcquiringGPS {
            return ("ACQUIRING GPS", latch.muted)
        }
        if model.isOffCourse {
            return ("OFF COURSE", latch.danger)
        }
        guard let pace = model.paceProgress else {
            return ("RUNNING", latch.accent)
        }
        if pace.scheduleDelta >= 1 { return ("BEHIND", latch.accent) }
        if pace.scheduleDelta <= -1 { return ("AHEAD", latch.ink) }
        return ("ON PACE", latch.accent)
    }

    private var glanceAccessibilityLabel: String {
        var parts = [
            glanceStatus.title,
            "Distance \(watchDistance(model.actualDistance))",
            "Elapsed \(watchDuration(model.elapsed))"
        ]
        if let sign = model.kilometerSign {
            parts.append("Kilometer \(sign.index) closed, split \(watchDuration(sign.splitDuration))")
        }
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
                        .foregroundStyle(summary.workoutSaved ? latch.accent : latch.danger)
                    metric("Elapsed", Duration.seconds(summary.elapsed).formatted(.time(pattern: .minuteSecond)), valueFont: .body.bold().monospacedDigit())
                    metric("Distance", watchDistance(summary.actualDistance), valueFont: .title2.bold().monospacedDigit())
                    metric("Average pace", summary.averagePace.map(watchPace) ?? "—")
                    if let pace = summary.paceProgress {
                        metric("Schedule", scheduleText(pace.scheduleDelta))
                        metric("Vs plan", watchPercent(pace.adherencePercent))
                        if model.isGuidedRun { metric("Projected", watchDuration(pace.projectedDuration)) }
                    }
                    if let heartRate = summary.heartRate { metric("Heart rate", String(format: "%.0f bpm", heartRate)) }
                    if summary.workoutSaved, !summary.routeSaved {
                        Text("Workout saved without a location route.").font(.caption2).foregroundStyle(latch.muted)
                    }
                }
                Button("Done") { anchor.dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(latch.accent)
                    .accessibilityLabel("Done")
            }
            .padding(8)
            .latchCard()
            .padding(.horizontal, 2)
        }
        .latchTabPage()
    }

    private func distanceReadout(numberSize: CGFloat) -> some View {
        let readout = distanceParts(model.actualDistance)
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(readout.value)
                .font(.system(size: numberSize, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(readout.unit)
                .font(.system(size: max(16, numberSize * 0.46), weight: .bold, design: .rounded))
        }
        .foregroundStyle(latch.accent)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityLabel("Distance \(watchDistance(model.actualDistance))")
    }

    private func distanceParts(_ meters: Double) -> (value: String, unit: String) {
        guard meters.isFinite, meters >= 1_000 else {
            let whole = meters.isFinite ? max(0, meters) : 0
            return (String(format: "%.0f", whole), "m")
        }
        return (String(format: "%.1f", meters / 1_000), "km")
    }

    private func metric(_ title: String, _ value: String, valueFont: Font = .title3.bold().monospacedDigit()) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(latch.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            Text(value)
                .font(valueFont)
                .foregroundStyle(latch.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
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
        if delta >= 1 { return latch.accent }
        if delta <= -1 { return latch.ink }
        return latch.ink
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
