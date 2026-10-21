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
    @Environment(\.colorScheme) private var colorScheme
    let entry: WorkoutEntry

    var body: some View {
        let palette = WidgetPalette.current(colorScheme: colorScheme)
        return content(palette)
            .containerBackground(palette.canvas, for: .widget)
    }

    @ViewBuilder
    private func content(_ palette: WidgetPalette) -> some View {
        if entry.snapshot.phase == .inactive {
            HStack {
                Image(systemName: "figure.run.circle.fill").foregroundStyle(palette.accent)
                VStack(alignment: .leading) {
                    Text("RouteLatch").font(.headline).foregroundStyle(palette.ink)
                    Text("No active run").font(.caption2).foregroundStyle(palette.muted)
                }
            }
            .widgetURL(URL(string: "routelatch://run"))
        } else {
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: entry.snapshot.phase == .paused ? "pause.circle.fill" : "figure.run")
                            .foregroundStyle(palette.accent)
                        Text(distanceText)
                            .font(.headline.weight(.bold).monospacedDigit())
                            .foregroundStyle(palette.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    HStack(spacing: 4) {
                        elapsedText
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Label(paceText, systemImage: "speedometer")
                            .lineLimit(1)
                    }
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(palette.ink)
                    .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                controlButtons(palette)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func controlButtons(_ palette: WidgetPalette) -> some View {
        HStack(spacing: 4) {
            if entry.snapshot.phase == .active {
                Button(intent: WorkoutCommandIntent(command: .pause)) {
                    Image(systemName: "pause.fill")
                        .font(.title2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .tint(palette.accent)
                .accessibilityLabel("Pause run")
            } else if entry.snapshot.phase == .paused {
                Button(intent: WorkoutCommandIntent(command: .resume)) {
                    Image(systemName: "play.fill")
                        .font(.title2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .tint(palette.accent)
                .accessibilityLabel("Resume run")
            }
            Button(intent: WorkoutCommandIntent(command: .finish)) {
                Image(systemName: "stop.fill")
                    .font(.title2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .tint(.red)
            .accessibilityLabel("Finish run")
        }
        .labelStyle(.iconOnly)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

private struct WidgetPalette {
    let canvas: Color
    let ink: Color
    let muted: Color
    let accent: Color

    static let light = WidgetPalette(
        canvas: Color(red: 0.973, green: 0.929, blue: 0.894),
        ink: Color(red: 0.110, green: 0.090, blue: 0.078),
        muted: Color(red: 0.345, green: 0.305, blue: 0.275),
        accent: Color(red: 0.640, green: 0.320, blue: 0.069)
    )

    static let dark = WidgetPalette(
        canvas: Color(red: 0.102, green: 0.078, blue: 0.071),
        ink: Color(red: 0.969, green: 0.941, blue: 0.910),
        muted: Color(red: 0.780, green: 0.722, blue: 0.675),
        accent: Color(red: 1.000, green: 0.545, blue: 0.247)
    )

    static func current(colorScheme: ColorScheme) -> WidgetPalette {
        switch WorkoutWidgetStore.readResolvedAppearance() {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            switch colorScheme {
            case .dark:
                return .dark
            case .light:
                return .light
            @unknown default:
                return .dark
            }
        }
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
