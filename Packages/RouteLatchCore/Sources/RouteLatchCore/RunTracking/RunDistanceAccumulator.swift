import Foundation

/// A conservative GPS fallback for live run distance. HealthKit remains the
/// authoritative source when it publishes walking/running distance.
public struct RunDistanceAccumulator: Sendable {
    public struct Sample: Equatable, Sendable {
        public let latitude: Double
        public let longitude: Double
        public let horizontalAccuracy: Double
        public let timestamp: Date

        public init(latitude: Double, longitude: Double, horizontalAccuracy: Double, timestamp: Date) {
            self.latitude = latitude
            self.longitude = longitude
            self.horizontalAccuracy = horizontalAccuracy
            self.timestamp = timestamp
        }
    }

    public private(set) var distance: Double = 0
    private var previous: Sample?

    public init() {}

    @discardableResult
    public mutating func add(_ sample: Sample) -> Double {
        guard sample.latitude.isFinite, (-90...90).contains(sample.latitude),
              sample.longitude.isFinite, (-180...180).contains(sample.longitude),
              sample.horizontalAccuracy.isFinite,
              (0...75).contains(sample.horizontalAccuracy) else { return distance }

        guard let previous else {
            self.previous = sample
            return distance
        }

        let interval = sample.timestamp.timeIntervalSince(previous.timestamp)
        guard interval > 0 else { return distance }

        let segment = Self.distance(from: previous, to: sample)
        // A runner cannot realistically cover more than 12 m/s. Accuracy-based
        // slack prevents a single GPS jump from inflating the finished result.
        let accuracySlack = min(75, previous.horizontalAccuracy + sample.horizontalAccuracy)
        guard segment <= interval * 12 + accuracySlack else { return distance }

        self.previous = sample
        // Ignore movement that is smaller than typical GPS jitter while standing.
        let noiseFloor = min(4, min(previous.horizontalAccuracy, sample.horizontalAccuracy) * 0.25)
        if segment >= noiseFloor { distance += segment }
        return distance
    }

    public mutating func reset() {
        distance = 0
        previous = nil
    }

    private static func distance(from first: Sample, to second: Sample) -> Double {
        let radius = 6_371_008.8
        let latitude1 = first.latitude * .pi / 180
        let latitude2 = second.latitude * .pi / 180
        let latitudeDelta = latitude2 - latitude1
        let longitudeDelta = (second.longitude - first.longitude) * .pi / 180
        let haversine = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(latitude1) * cos(latitude2)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return radius * 2 * atan2(sqrt(haversine), sqrt(max(0, 1 - haversine)))
    }
}
