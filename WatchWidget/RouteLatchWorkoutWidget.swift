import AppIntents
import SwiftUI
import WidgetKit

@main
struct RouteLatchWorkoutWidgetBundle: WidgetBundle {
    var body: some Widget {
        RouteLatchWorkoutWidget()
    }
}

struct RouteLatchWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WorkoutWidgetStore.widgetKind, provider: WorkoutTimelineProvider()) { entry in
            WorkoutWidgetView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Live Run")
        .description("See your run and control the active workout.")
        .supportedFamilies([.accessoryRectangular])
    }
}

private struct WorkoutEntry: TimelineEntry {
    let date: Date
    let snapshot: WorkoutWidgetStore.Snapshot
}

private struct WorkoutTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkoutEntry {
        WorkoutEntry(date: .now, snapshot: .init(
            phase: .active,
            runName: "Morning Run",
            elapsed: 1_502,
            distance: 4_230,
            averagePace: 355,
            updatedAt: .now
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (WorkoutEntry) -> Void) {
        completion(WorkoutEntry(date: .now, snapshot: WorkoutWidgetStore.readSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutEntry>) -> Void) {
        let entry = WorkoutEntry(date: .now, snapshot: WorkoutWidgetStore.readSnapshot())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15))))
    }
}

private struct WorkoutWidgetView: View {
    let entry: WorkoutEntry

    var body: some View {
        if entry.snapshot.phase == .inactive {
            HStack {
                Image(systemName: "figure.run.circle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text("RouteLatch").font(.headline)
                    Text("No active run").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .widgetURL(URL(string: "routelatch://run"))
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: entry.snapshot.phase == .paused ? "pause.circle.fill" : "figure.run")
                        .foregroundStyle(entry.snapshot.phase == .paused ? .yellow : .green)
                    elapsedText
                        .font(.headline.monospacedDigit())
                    Spacer(minLength: 2)
                    controlButtons
                }
                HStack {
                    Label(distanceText, systemImage: "arrow.trianglehead.swap")
                    Spacer(minLength: 4)
                    Label(paceText, systemImage: "speedometer")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .widgetURL(URL(string: "routelatch://workout"))
        }
    }

    @ViewBuilder
    private var elapsedText: some View {
        if entry.snapshot.phase == .active {
            Text(entry.snapshot.timerStart, style: .timer)
        } else {
            Text(duration(entry.snapshot.elapsed))
        }
    }

    private var controlButtons: some View {
        HStack(spacing: 5) {
            if entry.snapshot.phase == .active {
                Button(intent: WorkoutCommandIntent(command: .pause)) {
                    Image(systemName: "pause.fill")
                }
                .tint(.yellow)
                .accessibilityLabel("Pause run")
            } else if entry.snapshot.phase == .paused {
                Button(intent: WorkoutCommandIntent(command: .resume)) {
                    Image(systemName: "play.fill")
                }
                .tint(.green)
                .accessibilityLabel("Resume run")
            }
            Button(intent: WorkoutCommandIntent(command: .finish)) {
                Image(systemName: "stop.fill")
            }
            .tint(.red)
            .accessibilityLabel("Finish run")
        }
        .labelStyle(.iconOnly)
    }

    private var distanceText: String {
        entry.snapshot.distance >= 1_000
            ? String(format: "%.1f km", entry.snapshot.distance / 1_000)
            : String(format: "%.0f m", entry.snapshot.distance)
    }

    private var paceText: String {
        guard let pace = entry.snapshot.averagePace, pace.isFinite, pace > 0 else { return "— /km" }
        let rounded = Int(pace.rounded())
        return String(format: "%d:%02d /km", rounded / 60, rounded % 60)
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let rounded = max(0, Int(seconds.rounded()))
        return rounded >= 3_600
            ? String(format: "%d:%02d:%02d", rounded / 3_600, rounded % 3_600 / 60, rounded % 60)
            : String(format: "%d:%02d", rounded / 60, rounded % 60)
    }
}

private enum WorkoutWidgetAction: String, AppEnum {
    case pause
    case resume
    case finish

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Workout action")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .pause: "Pause",
        .resume: "Resume",
        .finish: "Finish"
    ]
}

private struct WorkoutCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Control RouteLatch workout"

    @Parameter(title: "Action") var command: WorkoutWidgetAction

    init() {}

    init(command: WorkoutWidgetAction) {
        self.command = command
    }

    func perform() async throws -> some IntentResult {
        guard let command = WorkoutWidgetStore.Command(rawValue: command.rawValue) else { return .result() }
        WorkoutWidgetStore.queue(command)
        return .result()
    }
}
