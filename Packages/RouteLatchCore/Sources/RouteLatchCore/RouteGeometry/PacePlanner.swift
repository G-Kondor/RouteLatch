import Foundation

public struct PaceProgress: Equatable, Sendable {
    public let targetPaceSecondsPerKilometer: Double
    public let averagePaceSecondsPerKilometer: Double
    public let plannedElapsed: TimeInterval
    /// Positive values mean behind plan; negative values mean ahead.
    public let scheduleDelta: TimeInterval
    public let projectedDuration: TimeInterval
}

public enum PaceCalculator {
    public static func progress(
        targetPaceSecondsPerKilometer target: Double,
        elapsed: TimeInterval,
        distanceCompleted: Double,
        plannedDistance: Double
    ) -> PaceProgress? {
        guard PaceGoalConfiguration.isValid(target),
              elapsed.isFinite, elapsed >= 0,
              distanceCompleted.isFinite, distanceCompleted > 0,
              plannedDistance.isFinite, plannedDistance > 0 else { return nil }

        let completedKilometers = distanceCompleted / 1_000
        let average = elapsed / completedKilometers
        let plannedElapsed = target * completedKilometers
        return PaceProgress(
            targetPaceSecondsPerKilometer: target,
            averagePaceSecondsPerKilometer: average,
            plannedElapsed: plannedElapsed,
            scheduleDelta: elapsed - plannedElapsed,
            projectedDuration: average * (plannedDistance / 1_000)
        )
    }
}

public struct PaceAlertState: Sendable {
    public enum Event: Equatable, Sendable { case fellBehind, caughtUp, repeatWarning, none }

    public static let enterFraction = 0.10
    public static let exitFraction = 0.05
    public static let minimumDistance = 500.0
    public static let minimumElapsed: TimeInterval = 180
    public static let repeatInterval: TimeInterval = 120

    public private(set) var isBehind = false
    private var lastWarningElapsed: TimeInterval?

    public init() {}

    public mutating func update(
        averagePace: Double,
        targetPace: Double,
        distanceCompleted: Double,
        elapsed: TimeInterval
    ) -> Event {
        guard averagePace.isFinite,
              PaceGoalConfiguration.isValid(targetPace),
              distanceCompleted >= Self.minimumDistance,
              elapsed >= Self.minimumElapsed else { return .none }

        if !isBehind, averagePace > targetPace * (1 + Self.enterFraction) {
            isBehind = true
            lastWarningElapsed = elapsed
            return .fellBehind
        }
        if isBehind, averagePace <= targetPace * (1 + Self.exitFraction) {
            isBehind = false
            lastWarningElapsed = nil
            return .caughtUp
        }
        if isBehind, elapsed - (lastWarningElapsed ?? 0) >= Self.repeatInterval {
            lastWarningElapsed = elapsed
            return .repeatWarning
        }
        return .none
    }
}
