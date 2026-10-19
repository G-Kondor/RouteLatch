import RouteLatchCore
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: PhoneRouteLibraryModel
    @Binding var tab: PhoneTab
    @Binding var importing: Bool
    @State private var selectedRoute: Route?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let featured {
                        hero(featured)
                        statRow
                        if !otherWaiting.isEmpty {
                            waitingSection
                        }
                    } else {
                        emptyHero
                        if model.completedRuns.first != nil {
                            statRow
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
            .navigationDestination(item: $selectedRoute) { route in
                RouteDetailView(route: route, model: model)
            }
            .phoneChrome(tab: $tab, warning: model.storageWarning)
        }
        .latchScreen()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                LatchIconBadge(systemName: "applewatch", size: 48)
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
            Text("Ready to run")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(LatchColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(LatchColor.muted)
        }
        .padding(.bottom, 2)
    }

    private var headerSubtitle: String {
        guard !model.routes.isEmpty else {
            return "Import a GPX course, then send it to your Watch."
        }
        if waitingCount == 0 {
            return "Every course is on your Watch. Leave the phone."
        }
        if waitingCount == 1 {
            return "1 course still needs your Watch."
        }
        return "\(waitingCount) courses still need your Watch."
    }

    private func hero(_ route: Route) -> some View {
        let current = live(route)
        let status = model.connectivity.status(for: current)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isOnWatch(status) ? "On your Watch" : "Send to Watch")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LatchColor.canvas)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(LatchColor.ink, in: Capsule())
                Spacer(minLength: 8)
                if isSending(status) {
                    ProgressView()
                        .tint(LatchColor.accent)
                }
            }
            Text(heroHeadline(status))
                .font(.title3.weight(.semibold))
                .foregroundStyle(LatchColor.ink)
            Text(current.name)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(LatchColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(heroFacts(current))
                .font(.subheadline)
                .foregroundStyle(LatchColor.muted)
            if let target = current.targetPaceSecondsPerKilometer {
                Label(paceLabel(target), systemImage: "speedometer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LatchColor.accent)
            }
            Text(status.label)
                .font(.caption)
                .foregroundStyle(LatchColor.muted)
            sendButton(current, status: status)
            HStack(spacing: 16) {
                Button("Course details") { selectedRoute = current }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LatchColor.accent)
                Button("Import GPX") { importing = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LatchColor.muted)
                    .disabled(importing || model.isImporting)
                    .accessibilityHint("Choose a GPX course file")
            }
        }
        .padding(18)
        .latchCard()
    }

    private var emptyHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            LatchIconBadge(systemName: "square.and.arrow.down", size: 56)
            Text("Put a course on your Watch")
                .font(.title3.bold())
                .foregroundStyle(LatchColor.ink)
            Text("Import a GPX file on this iPhone. RouteLatch sends it to Apple Watch so you can run the route without touching your phone.")
                .font(.subheadline)
                .foregroundStyle(LatchColor.muted)
            if importing || model.isImporting {
                ProgressView("Importing GPX")
                    .tint(LatchColor.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                primaryButton("Import GPX", systemImage: "square.and.arrow.down") { importing = true }
                    .accessibilityHint("Choose a GPX course file")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .latchCard()
    }

    private var statRow: some View {
        HStack(spacing: 12) {
            Button { tab = .runs } label: {
                statCard(
                    title: "Last run",
                    value: lastRunValue,
                    detail: lastRunDetail,
                    systemImage: "figure.run"
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens your runs")
            Button { tab = .routes } label: {
                statCard(
                    title: "Watch",
                    value: watchValue,
                    detail: watchDetail,
                    systemImage: "applewatch"
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens your routes")
        }
    }

    private func statCard(title: String, value: String, detail: String, systemImage: String) -> some View {
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
                .font(.caption)
                .foregroundStyle(LatchColor.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .latchCard()
    }

    private var waitingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Still on this iPhone")
                .font(.title3.bold())
                .foregroundStyle(LatchColor.ink)
                .accessibilityAddTraits(.isHeader)
            ForEach(otherWaiting) { route in
                waitingRow(route)
            }
        }
    }

    private func waitingRow(_ route: Route) -> some View {
        let current = live(route)
        let status = model.connectivity.status(for: current)
        return HStack(spacing: 12) {
            Button { selectedRoute = current } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(current.name)
                        .font(.headline)
                        .foregroundStyle(LatchColor.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text("\(current.totalDistance.formattedDistance) · \(status.label)")
                        .font(.caption)
                        .foregroundStyle(LatchColor.muted)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button {
                model.connectivity.send(current)
            } label: {
                Text(isSending(status) ? "Sending" : "Send")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LatchColor.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(LatchColor.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSending(status))
            .accessibilityLabel("Send \(current.name) to Apple Watch")
        }
        .padding(14)
        .latchCard()
    }

    private func sendButton(_ route: Route, status: RouteTransferStatus) -> some View {
        Button {
            model.connectivity.send(route)
        } label: {
            HStack(spacing: 8) {
                if isSending(status) {
                    ProgressView()
                        .tint(LatchColor.onAccent)
                } else {
                    Image(systemName: "applewatch.radiowaves.left.and.right")
                }
                Text(sendTitle(status))
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        .foregroundStyle(LatchColor.onAccent)
        .background(LatchColor.accent, in: Capsule())
        .disabled(isSending(status))
        .opacity(isSending(status) ? 0.75 : 1)
        .accessibilityLabel(sendTitle(status))
    }

    private func primaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        .foregroundStyle(LatchColor.onAccent)
        .background(LatchColor.accent, in: Capsule())
    }

    private var featured: Route? {
        model.routes.first { !isOnWatch(model.connectivity.status(for: $0)) } ?? model.routes.first
    }

    private var otherWaiting: [Route] {
        guard let featured else { return [] }
        return Array(model.routes.filter { $0.id != featured.id && !isOnWatch(model.connectivity.status(for: $0)) }.prefix(3))
    }

    private var waitingCount: Int {
        model.routes.filter { !isOnWatch(model.connectivity.status(for: $0)) }.count
    }

    private var onWatchCount: Int {
        model.routes.filter { isOnWatch(model.connectivity.status(for: $0)) }.count
    }

    private var lastRun: RecordedRun? { model.completedRuns.first }

    private var lastRunValue: String {
        guard let lastRun else { return "None yet" }
        return lastRun.distanceMeters.formattedDistance
    }

    private var lastRunDetail: String {
        guard let lastRun else { return "Runs from your Watch land here" }
        return "\(averagePace(lastRun)) · \(lastRun.startedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private var watchValue: String {
        guard !model.routes.isEmpty else { return "None" }
        return "\(onWatchCount) of \(model.routes.count)"
    }

    private var watchDetail: String {
        guard !model.routes.isEmpty else { return "Import a course to send" }
        if waitingCount == 0 { return "Ready to run without the phone" }
        return waitingCount == 1 ? "1 still to send" : "\(waitingCount) still to send"
    }

    private func live(_ route: Route) -> Route {
        model.routes.first(where: { $0.id == route.id }) ?? route
    }

    private func heroHeadline(_ status: RouteTransferStatus) -> String {
        switch status {
        case .delivered:
            "Leave your phone"
        case .connecting, .preparing, .queued, .transferring:
            "Sending your course"
        case .notSent:
            "Send this to your Watch"
        case .unavailable, .failed:
            "Your Watch doesn’t have it yet"
        }
    }

    private func heroFacts(_ route: Route) -> String {
        var parts = [route.totalDistance.formattedDistance]
        if let ascent = route.totalAscent {
            parts.append(String(format: "%.0f m ascent", ascent))
        }
        return parts.joined(separator: " · ")
    }

    private func sendTitle(_ status: RouteTransferStatus) -> String {
        switch status {
        case .delivered:
            "Send again"
        case .connecting, .preparing, .queued, .transferring:
            "Sending to Watch…"
        case .notSent:
            "Send to Apple Watch"
        case .unavailable, .failed:
            "Try sending again"
        }
    }

    private func isOnWatch(_ status: RouteTransferStatus) -> Bool {
        if case .delivered = status { return true }
        return false
    }

    private func isSending(_ status: RouteTransferStatus) -> Bool {
        switch status {
        case .connecting, .preparing, .queued, .transferring:
            true
        case .notSent, .unavailable, .delivered, .failed:
            false
        }
    }

    private func paceLabel(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded())
        return String(format: "Target %d:%02d /km", rounded / 60, rounded % 60)
    }

    private func averagePace(_ run: RecordedRun) -> String {
        guard run.distanceMeters > 0 else { return "— /km" }
        let seconds = Int((run.activeDuration / (run.distanceMeters / 1_000)).rounded())
        return String(format: "%d:%02d /km", seconds / 60, seconds % 60)
    }
}
