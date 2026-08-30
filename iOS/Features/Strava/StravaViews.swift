import RouteLatchCore
import SwiftUI

struct CompletedRunRow: View {
    let run: RecordedRun
    @ObservedObject var strava: StravaManager
    let runStore: RecordedRunFileStore

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(run.name).font(.headline)
                Text(run.startedAt, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(run.distanceMeters.formattedDistance)
                    Text("•")
                    Text(runDuration(run.activeDuration))
                    Text("•")
                    Text(averagePace)
                }
                .font(.caption)
                Text(status.label)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
            }
            Spacer()
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
                Image(systemName: statusIcon).font(.title3)
            }
            .accessibilityLabel("Run actions")
        }
        .padding(.vertical, 3)
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
        case .uploading, .processing: .orange
        case .waitingForWatch, .ready, .notEligible: .secondary
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
            Form {
                Section("Connection") {
                    if !strava.isConfigured {
                        Label("This build still needs its Strava client ID and token broker URL.", systemImage: "wrench.and.screwdriver")
                            .foregroundStyle(.orange)
                    } else if strava.isConnected {
                        Label(strava.athleteName ?? "Connected to Strava", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Disconnect", role: .destructive) { strava.disconnect() }
                    } else {
                        Button("Connect with Strava", systemImage: "bolt.horizontal.fill") { strava.connect() }
                            .disabled(strava.isAuthenticating)
                        if strava.isAuthenticating { ProgressView("Waiting for Strava…") }
                    }
                }
                Section("Uploads") {
                    Text("\(pendingRuns.count) completed run(s) stored on this iPhone.")
                        .foregroundStyle(.secondary)
                    Text("Runs are never uploaded automatically. Use the menu beside a completed run to upload it, then check its Strava status manually.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Text("RouteLatch keeps saving the workout to Apple Health. The timestamped TCX copy is sent directly to Strava, because Strava does not import third-party Health workouts.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Strava")
            .toolbar { Button("Done") { dismiss() } }
            .alert("Strava Error", isPresented: Binding(get: { strava.errorMessage != nil }, set: { if !$0 { strava.errorMessage = nil } })) {
                Button("OK") {}
            } message: {
                Text(strava.errorMessage ?? "Unknown error")
            }
        }
    }
}
