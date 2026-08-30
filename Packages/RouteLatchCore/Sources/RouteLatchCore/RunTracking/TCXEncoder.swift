import Foundation

public enum TCXEncoder {
    public static func encode(_ run: RecordedRun) throws -> Data {
        let points = exportPoints(for: run)
        let distances = pointDistances(points, totalDistance: run.distanceMeters)
        let pointXML = zip(points, distances).map { point, distance in
            var values = ["<Time>\(iso8601(point.timestamp))</Time>"]
            if let latitude = point.latitude, let longitude = point.longitude {
                values.append("<Position><LatitudeDegrees>\(latitude)</LatitudeDegrees><LongitudeDegrees>\(longitude)</LongitudeDegrees></Position>")
            }
            if let elevation = point.elevation, elevation.isFinite {
                values.append("<AltitudeMeters>\(elevation)</AltitudeMeters>")
            }
            values.append("<DistanceMeters>\(distance)</DistanceMeters>")
            if let heartRate = point.heartRate, heartRate.isFinite, heartRate > 0 {
                values.append("<HeartRateBpm><Value>\(Int(heartRate.rounded()))</Value></HeartRateBpm>")
            }
            return "<Trackpoint>\(values.joined())</Trackpoint>"
        }.joined()

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2 http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd">
          <Activities>
            <Activity Sport="Running">
              <Id>\(iso8601(run.startedAt))</Id>
              <Lap StartTime="\(iso8601(run.startedAt))">
                <TotalTimeSeconds>\(run.activeDuration)</TotalTimeSeconds>
                <DistanceMeters>\(run.distanceMeters)</DistanceMeters>
                <Intensity>Active</Intensity>
                <TriggerMethod>Manual</TriggerMethod>
                <Track>\(pointXML)</Track>
              </Lap>
              <Notes>\(escape(run.name))</Notes>
              <Creator xsi:type="Device_t"><Name>RouteLatch</Name><UnitId>0</UnitId><ProductID>0</ProductID></Creator>
            </Activity>
          </Activities>
        </TrainingCenterDatabase>
        """
        guard let data = xml.data(using: .utf8) else { throw TCXEncodingError.invalidUTF8 }
        return data
    }

    private static func exportPoints(for run: RecordedRun) -> [RecordedRunPoint] {
        if !run.points.isEmpty { return run.points }
        return [
            .init(timestamp: run.startedAt),
            .init(timestamp: max(run.endedAt, run.startedAt.addingTimeInterval(run.activeDuration)))
        ]
    }

    private static func pointDistances(_ points: [RecordedRunPoint], totalDistance: Double) -> [Double] {
        guard !points.isEmpty else { return [] }
        var cumulative = [0.0]
        cumulative.reserveCapacity(points.count)
        for (first, second) in zip(points, points.dropFirst()) {
            cumulative.append(cumulative.last! + distance(from: first, to: second))
        }
        if let rawTotal = cumulative.last, rawTotal > 0 {
            let scale = totalDistance / rawTotal
            return cumulative.map { $0 * scale }
        }
        guard points.count > 1 else { return [totalDistance] }
        return points.indices.map { totalDistance * Double($0) / Double(points.count - 1) }
    }

    private static func distance(from first: RecordedRunPoint, to second: RecordedRunPoint) -> Double {
        guard let firstLatitude = first.latitude, let firstLongitude = first.longitude,
              let secondLatitude = second.latitude, let secondLongitude = second.longitude else { return 0 }
        let radius = 6_371_008.8
        let latitude1 = firstLatitude * .pi / 180
        let latitude2 = secondLatitude * .pi / 180
        let latitudeDelta = latitude2 - latitude1
        let longitudeDelta = (secondLongitude - firstLongitude) * .pi / 180
        let value = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(latitude1) * cos(latitude2) * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return radius * 2 * atan2(sqrt(value), sqrt(max(0, 1 - value)))
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

public enum TCXEncodingError: Error, LocalizedError, Sendable {
    case invalidUTF8

    public var errorDescription: String? { "The TCX workout file could not be encoded." }
}
