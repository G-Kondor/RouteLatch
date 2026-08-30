import Foundation

enum WorkoutWidgetStore {
    static let suiteName = "group.com.gergokondor.RouteLatchApp.watchkitapp"
    static let widgetKind = "RouteLatchWorkoutWidget"

    enum Phase: String, Codable, Sendable {
        case inactive
        case active
        case paused
        case finishing
    }

    enum Command: String, Codable, Sendable {
        case pause
        case resume
        case finish
    }

    struct Snapshot: Codable, Sendable {
        var phase: Phase
        var runName: String
        var elapsed: TimeInterval
        var distance: Double
        var averagePace: Double?
        var updatedAt: Date

        static let inactive = Snapshot(
            phase: .inactive,
            runName: "RouteLatch",
            elapsed: 0,
            distance: 0,
            averagePace: nil,
            updatedAt: .now
        )

        var timerStart: Date {
            updatedAt.addingTimeInterval(-elapsed)
        }
    }

    private struct PendingCommand: Codable {
        let id: UUID
        let command: Command
    }

    private static let snapshotKey = "workout-widget.snapshot"
    private static let commandKey = "workout-widget.command"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static func readSnapshot() -> Snapshot {
        guard let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return .inactive
        }
        if snapshot.phase != .inactive, Date().timeIntervalSince(snapshot.updatedAt) > 120 {
            return .inactive
        }
        return snapshot
    }

    static func writeSnapshot(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func queue(_ command: Command) {
        guard let data = try? JSONEncoder().encode(PendingCommand(id: UUID(), command: command)) else { return }
        defaults.set(data, forKey: commandKey)
    }

    static func consumeCommand() -> Command? {
        guard let data = defaults.data(forKey: commandKey),
              let pending = try? JSONDecoder().decode(PendingCommand.self, from: data) else {
            return nil
        }
        defaults.removeObject(forKey: commandKey)
        return pending.command
    }

    static func discardPendingCommand() {
        defaults.removeObject(forKey: commandKey)
    }
}
