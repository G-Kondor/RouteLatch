import Foundation

/// One completed kilometer of recorded run distance.
public struct KilometerClosure: Equatable, Sendable {
    /// 1-based index of the kilometer that just closed.
    public let index: Int
    /// Active time for that kilometer. A sample that jumps several kilometers uses the average.
    public let splitDuration: TimeInterval

    public init(index: Int, splitDuration: TimeInterval) {
        self.index = index
        self.splitDuration = splitDuration
    }
}

/// Reports each whole kilometer of run distance once, when the runner closes it.
public struct KilometerClosureState: Sendable {
    public enum Event: Equatable, Sendable {
        case closed(KilometerClosure)
        case none
    }

    public static let lengthMeters = 1_000.0

    public private(set) var closedCount = 0
    private var elapsedAtLastClosure: TimeInterval = 0

    public init() {}

    public mutating func update(distanceMeters: Double, elapsed: TimeInterval) -> Event {
        guard distanceMeters.isFinite, distanceMeters >= 0,
              elapsed.isFinite, elapsed >= 0,
              let completed = Int(exactly: (distanceMeters / Self.lengthMeters).rounded(.down)),
              completed > closedCount else { return .none }

        let opened = completed - closedCount
        let interval = max(0, elapsed - elapsedAtLastClosure)
        closedCount = completed
        elapsedAtLastClosure = elapsed
        let split = opened == 1 ? interval : interval / Double(opened)
        return .closed(KilometerClosure(index: completed, splitDuration: split))
    }
}
