import RouteLatchCore
import SwiftUI

struct CompletedRunRow: View {
    let run: RecordedRun
    @ObservedObject var strava: StravaManager
    let runStore: RecordedRunFileStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                LatchIconBadge(systemName: "flag.checkered", size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(run.name)
                        .font(.headline)
                        .foregroundStyle(LatchColor.ink)
                    Text(run.startedAt, format: .dateTime.day().month().year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(LatchColor.muted)
                }
                Spacer(minLength: 8)
                Menu {
                    if case .uploaded = status {
                        Button("Open in Strava", systemImage: "arrow.up.forward.app") { strava.openUploadedActivity(for: run) }
                    } else if case .processing = status {
                        Button("Check Strava Status", systemImage: "arrow.clockwise") { Task { await strava.upload(run) } }
                    } else if case .uploading = status {
                        Button("Strava Request in Progress", systemImage: "hourglass") {}
                            .disabled(true)
                    } else if case .notEligible = status {
                        Button("Not Eligible for Strava", systemImage: "xmark.circle") {}
                            .disabled(true)
                    } else {
                        Button("Upload to Strava", systemImage: "arrow.up.circle") { Task { await strava.upload(run) } }
                    }
                    ShareLink(item: runStore.tcxURL(for: run.id)) {
                        Label("Share TCX File", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: statusIcon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .frame(width: 40, height: 40)
                        .background(LatchColor.chip, in: Circle())
                }
                .accessibilityLabel("Run actions")
            }
            HStack(spacing: 8) {
                runStat("Distance", run.distanceMeters.formattedDistance)
                runStat("Time", runDuration(run.activeDuration))
                runStat("Pace", averagePace)
            }
            Text(status.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
        }
    }

    private func runStat(_ title: String, _ value: String) -> some View {
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

    private var status: StravaRunStatus { strava.statuses[run.id] ?? .ready }
    private var statusIcon: String {
        switch status {
        case .uploaded: "checkmark.circle.fill"
        case .uploading, .processing: "arrow.triangle.2.circlepath"
        case .notEligible: "xmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        case .waitingForWatch, .ready: "ellipsis.circle"
        }
    }
    private var statusColor: Color {
        switch status {
        case .uploaded: .green
        case .failed: .red
        case .uploading, .processing: LatchColor.accent
        case .waitingForWatch, .ready, .notEligible: LatchColor.muted
        }
    }
    private var averagePace: String {
        guard run.distanceMeters > 0 else { return "— /km" }
        let seconds = Int((run.activeDuration / (run.distanceMeters / 1_000)).rounded())
        return String(format: "%d:%02d /km", seconds / 60, seconds % 60)
    }
    private func runDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return total >= 3_600
            ? String(format: "%d:%02d:%02d", total / 3_600, total % 3_600 / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct StravaSettingsView: View {
    @ObservedObject var strava: StravaManager
    let pendingRuns: [RecordedRun]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    connectionCard
                    uploadsCard
                    footnoteCard
                }
                .padding(16)
            }
            .latchScreen()
            .navigationTitle("Strava")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(LatchColor.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { Button("Done") { dismiss() } }
            .alert("Strava Error", isPresented: Binding(get: { strava.errorMessage != nil }, set: { if !$0 { strava.errorMessage = nil } })) {
                Button("OK") {}
            } message: {
                Text(strava.errorMessage ?? "Unknown error")
            }
        }
        .latchScreen()
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connection")
                .font(.headline)
                .foregroundStyle(LatchColor.ink)
            if !strava.isConfigured {
                Label("This build still needs its Strava client ID and token broker URL.", systemImage: "wrench.and.screwdriver")
                    .foregroundStyle(LatchColor.accent)
            } else if strava.isConnected {
                Label(strava.athleteName ?? "Connected to Strava", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Disconnect", role: .destructive) { strava.disconnect() }
                    .buttonStyle(.plain)
                    .font(.headline)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.14), in: Capsule())
            } else {
                Button { strava.connect() } label: {
                    Label("Connect with Strava", systemImage: "bolt.horizontal.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(LatchColor.onAccent)
                .background(LatchColor.accent, in: Capsule())
                .disabled(strava.isAuthenticating)
                .opacity(strava.isAuthenticating ? 0.55 : 1)
                if strava.isAuthenticating {
                    ProgressView("Waiting for Strava…")
                        .tint(LatchColor.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .latchCard()
    }

    private var uploadsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Uploads")
                .font(.headline)
                .foregroundStyle(LatchColor.ink)
            Text("\(pendingRuns.count) completed run(s) stored on this iPhone.")
                .foregroundStyle(LatchColor.muted)
            Text("Runs are never uploaded automatically. Use the menu beside a completed run to upload it, then check its Strava status manually.")
                .font(.footnote)
                .foregroundStyle(LatchColor.muted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .latchCard()
    }

    private var footnoteCard: some View {
        Text("RouteLatch keeps saving the workout to Apple Health. The timestamped TCX copy is sent directly to Strava, because Strava does not import third-party Health workouts.")
            .font(.footnote)
            .foregroundStyle(LatchColor.muted)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .latchCard()
    }
}
