import Foundation
import XCTest
@testable import RouteLatchCore

final class RunAnalyticsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testZoneBoundariesMatchStravaAndRunnaPercents() {
        let maxHeartRate = 200.0
        XCTAssertEqual(HeartRateZone.classify(beatsPerMinute: 130, maxHeartRate: maxHeartRate), .recovery)
        XCTAssertEqual(HeartRateZone.classify(beatsPerMinute: 130.2, maxHeartRate: maxHeartRate), .endurance)
        XCTAssertEqual(HeartRateZone.classify(beatsPerMinute: 162, maxHeartRate: maxHeartRate), .endurance)
        XCTAssertEqual(HeartRateZone.classify(beatsPerMinute: 162.2, maxHeartRate: maxHeartRate), .tempo)
        XCTAssertEqual(HeartRateZone.classify(beatsPerMinute: 178, maxHeartRate: maxHeartRate), .tempo)
        XCTAssertEqual(HeartRateZone.classify(beatsPerMinute: 178.2, maxHeartRate: maxHeartRate), .threshold)
        XCTAssertEqual(HeartRateZone.classify(beatsPerMinute: 194, maxHeartRate: maxHeartRate), .threshold)
        XCTAssertEqual(HeartRateZone.classify(beatsPerMinute: 194.2, maxHeartRate: maxHeartRate), .anaerobic)
        XCTAssertEqual(HeartRateZone.classify(beatsPerMinute: 250, maxHeartRate: maxHeartRate), .anaerobic)
        XCTAssertNil(HeartRateZone.classify(beatsPerMinute: 0, maxHeartRate: maxHeartRate))
        XCTAssertNil(HeartRateZone.classify(beatsPerMinute: .nan, maxHeartRate: maxHeartRate))
    }

    func testAgeSetsMaxHeartRateAndUnknownAgeUses190() {
        XCTAssertEqual(HeartRateZoneSettings(age: 40).maxHeartRate, 180)
        XCTAssertFalse(HeartRateZoneSettings(age: 40).usesEstimatedMax)
        XCTAssertNil(HeartRateZoneSettings(age: 5).age)
        XCTAssertEqual(HeartRateZoneSettings(age: nil).maxHeartRate, 190)
        XCTAssertTrue(HeartRateZoneSettings(age: nil).usesEstimatedMax)
    }

    func testHeartRateGapIsCappedAndAShortSeriesDoesNotInventZones() {
        let samples = [
            AnalyticsHeartRateSample(timestamp: start, beatsPerMinute: 120),
            AnalyticsHeartRateSample(timestamp: start.addingTimeInterval(200), beatsPerMinute: 120)
        ]
        let snapshot = snapshot(activities: [activity(samples: samples, heartSource: .health)], settings: HeartRateZoneSettings(age: 20))
        XCTAssertTrue(snapshot.zones.isEmpty)
        XCTAssertNil(snapshot.effort)
        XCTAssertEqual(snapshot.measuredHeartRate, 15, accuracy: 0.01)
    }

    func testEffortWeightsMinutesByZone() {
        var samples: [AnalyticsHeartRateSample] = []
        for second in stride(from: 0, through: 110, by: 10) {
            samples.append(.init(timestamp: start.addingTimeInterval(TimeInterval(second)), beatsPerMinute: 100))
        }
        for second in stride(from: 120, through: 240, by: 10) {
            samples.append(.init(timestamp: start.addingTimeInterval(TimeInterval(second)), beatsPerMinute: 199))
        }
        let snapshot = snapshot(activities: [activity(samples: samples, heartSource: .recordedRun)], settings: HeartRateZoneSettings(age: 20))
        let recovery = snapshot.zones.first { $0.zone == .recovery }
        let anaerobic = snapshot.zones.first { $0.zone == .anaerobic }
        XCTAssertEqual(recovery?.duration ?? 0, 120, accuracy: 0.01)
        XCTAssertEqual(anaerobic?.duration ?? 0, 120, accuracy: 0.01)
        XCTAssertEqual(snapshot.effort, 12)
        XCTAssertEqual(snapshot.heartRateOrigin, .recordedRun)
    }

    func testKilometerSplitsScaleAShortTrackToTheSavedDistance() {
        let track = [
            AnalyticsTrackSample(latitude: 47.5, longitude: 19, elevationMeters: 100, timestamp: start),
            AnalyticsTrackSample(latitude: 47.505, longitude: 19, elevationMeters: 110, timestamp: start.addingTimeInterval(600))
        ]
        let splits = RunAnalytics.kilometerSplits(track: track, distanceMeters: 2_000)
        XCTAssertEqual(splits.count, 2)
        XCTAssertEqual(splits[0].distanceMeters, 1_000, accuracy: 0.01)
        XCTAssertEqual(splits[0].duration, 300, accuracy: 0.01)
        XCTAssertEqual(splits[1].duration, 300, accuracy: 0.01)
        XCTAssertFalse(splits[0].isPartial)
    }

    func testPartialSplitIsKeptAndAGPSSpikeIsDropped() {
        let steady = [
            AnalyticsTrackSample(latitude: 47.5, longitude: 19, elevationMeters: nil, timestamp: start),
            AnalyticsTrackSample(latitude: 47.505, longitude: 19, elevationMeters: nil, timestamp: start.addingTimeInterval(750))
        ]
        let partial = RunAnalytics.kilometerSplits(track: steady, distanceMeters: 2_500)
        XCTAssertEqual(partial.count, 3)
        XCTAssertTrue(partial[2].isPartial)
        XCTAssertEqual(partial[2].distanceMeters, 500, accuracy: 0.01)
        XCTAssertEqual(partial[2].duration, 150, accuracy: 0.01)

        let spike = [
            AnalyticsTrackSample(latitude: 47.5, longitude: 19, elevationMeters: nil, timestamp: start),
            AnalyticsTrackSample(latitude: 48.5, longitude: 19, elevationMeters: nil, timestamp: start.addingTimeInterval(1))
        ]
        XCTAssertTrue(RunAnalytics.kilometerSplits(track: spike, distanceMeters: 5_000).isEmpty)
        XCTAssertTrue(RunAnalytics.kilometerSplits(track: [], distanceMeters: 5_000).isEmpty)
    }

    func testElevationIgnoresRisesUnderThreeMeters() {
        let noisy = track(elevations: [100, 101, 102, 101, 100])
        XCTAssertEqual(RunAnalytics.elevationGainMeters(of: noisy), 0)
        let climb = track(elevations: [100, 104, 101, 110])
        XCTAssertEqual(RunAnalytics.elevationGainMeters(of: climb), 13)
        XCTAssertNil(RunAnalytics.elevationGainMeters(of: track(elevations: [nil, nil])))
    }

    func testMergePrefersHealthMetricsAndKeepsThePhoneRoute() throws {
        let recorded = RecordedRun(
            name: "River",
            startedAt: start,
            endedAt: start.addingTimeInterval(1_800),
            activeDuration: 1_700,
            distanceMeters: 5_000,
            points: [
                .init(latitude: 47.5, longitude: 19, elevation: 100, timestamp: start, heartRate: 130),
                .init(latitude: 47.505, longitude: 19, elevation: 140, timestamp: start.addingTimeInterval(1_800), heartRate: 150)
            ]
        )
        let health = healthRun(
            id: "abc",
            startedAt: start.addingTimeInterval(30),
            duration: 1_800,
            distance: 5_100,
            elevation: 42,
            samples: [
                .init(timestamp: start, beatsPerMinute: 140),
                .init(timestamp: start.addingTimeInterval(60), beatsPerMinute: 150)
            ],
            steps: 5_100,
            energy: 320
        )
        let activities = RunAnalytics.activities(health: [health], recorded: [recorded])
        XCTAssertEqual(activities.count, 1)
        let activity = try XCTUnwrap(activities.first)
        XCTAssertEqual(activity.name, "River")
        XCTAssertEqual(activity.distanceMeters, 5_100)
        XCTAssertEqual(activity.distanceSource, .health)
        XCTAssertEqual(activity.duration, 1_700)
        XCTAssertEqual(activity.durationSource, .recordedRun)
        XCTAssertEqual(activity.elevationGainMeters, 42)
        XCTAssertEqual(activity.elevationSource, .health)
        XCTAssertEqual(activity.heartRateSource, .health)
        XCTAssertEqual(activity.averageHeartRate, 148)
        XCTAssertEqual(activity.averageCadenceStepsPerMinute ?? 0, 170, accuracy: 0.01)
        XCTAssertEqual(activity.cadenceSource, .health)
        XCTAssertEqual(activity.activeEnergyKilocalories, 320)
        XCTAssertEqual(activity.energySource, .health)
        XCTAssertEqual(activity.trackSource, .recordedRun)
        XCTAssertFalse(activity.track.isEmpty)
    }

    func testDistinctRunsStaySeparate() {
        let recorded = RecordedRun(
            name: "Free Run",
            startedAt: start,
            endedAt: start.addingTimeInterval(1_200),
            activeDuration: 1_200,
            distanceMeters: 5_000,
            points: []
        )
        let later = healthRun(id: "later", startedAt: start.addingTimeInterval(2 * 3_600), duration: 1_000, distance: 4_000)
        let differentDistance = healthRun(id: "other", startedAt: start.addingTimeInterval(60), duration: 3_000, distance: 20_000)
        XCTAssertEqual(RunAnalytics.activities(health: [later], recorded: [recorded]).count, 2)
        XCTAssertEqual(RunAnalytics.activities(health: [differentDistance], recorded: [recorded]).count, 2)
    }

    func testMissingHealthExtrasStayEmpty() throws {
        let recorded = RecordedRun(
            name: "Free Run",
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            activeDuration: 600,
            distanceMeters: 2_000,
            points: [
                .init(latitude: 47.5, longitude: 19, elevation: nil, timestamp: start, heartRate: nil)
            ]
        )
        let activity = try XCTUnwrap(RunAnalytics.activities(health: [], recorded: [recorded]).first)
        XCTAssertNil(activity.averageCadenceStepsPerMinute)
        XCTAssertNil(activity.activeEnergyKilocalories)
        XCTAssertNil(activity.elevationGainMeters)
        XCTAssertNil(activity.heartRateSource)
        XCTAssertEqual(activity.distanceSource, .recordedRun)
    }

    func testWeekWindowExcludesOlderRunsAndMixesSources() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = start
        let recent = activity(startedAt: now.addingTimeInterval(-3_600), distance: 5_000, duration: 1_800, source: .health, elevation: 20, elevationSource: .health)
        let older = activity(startedAt: now.addingTimeInterval(-10 * 86_400), distance: 3_000, duration: 1_200, source: .recordedRun)
        let phone = activity(startedAt: now.addingTimeInterval(-7_200), distance: 2_000, duration: 800, source: .recordedRun, elevation: 10, elevationSource: .recordedRun)
        let snapshot = RunAnalytics.snapshot(
            activities: [recent, older, phone],
            range: .week,
            now: now,
            calendar: calendar,
            zones: HeartRateZoneSettings(age: nil)
        )
        XCTAssertEqual(snapshot.activities.count, 2)
        XCTAssertEqual(snapshot.distanceMeters, 7_000, accuracy: 0.1)
        XCTAssertEqual(snapshot.buckets.count, 7)
        XCTAssertEqual(snapshot.buckets.last?.distanceMeters ?? 0, 7_000, accuracy: 0.1)
        XCTAssertEqual(snapshot.distanceOrigin, .combined)
        XCTAssertEqual(snapshot.elevationGainMeters, 30)
        XCTAssertEqual(snapshot.elevationOrigin, .combined)
        XCTAssertEqual(RunAnalytics.snapshot(activities: [], range: .month, now: now, calendar: calendar, zones: .init(age: nil)).buckets.count, 4)
        XCTAssertEqual(RunAnalytics.snapshot(activities: [], range: .year, now: now, calendar: calendar, zones: .init(age: nil)).buckets.count, 12)
    }

    private func snapshot(activities: [AnalyticsActivity], settings: HeartRateZoneSettings) -> TrainingSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return RunAnalytics.snapshot(activities: activities, range: .week, now: start.addingTimeInterval(3_600), calendar: calendar, zones: settings)
    }

    private func activity(
        startedAt: Date? = nil,
        distance: Double = 1_000,
        duration: TimeInterval = 300,
        source: AnalyticsFieldSource = .recordedRun,
        elevation: Double? = nil,
        elevationSource: AnalyticsFieldSource? = nil,
        samples: [AnalyticsHeartRateSample] = [],
        heartSource: AnalyticsFieldSource? = nil
    ) -> AnalyticsActivity {
        let started = startedAt ?? start
        return AnalyticsActivity(
            id: UUID().uuidString,
            name: "Run",
            startedAt: started,
            endedAt: started.addingTimeInterval(duration),
            duration: duration,
            distanceMeters: distance,
            elevationGainMeters: elevation,
            averageHeartRate: nil,
            heartRateSamples: samples,
            averageCadenceStepsPerMinute: nil,
            activeEnergyKilocalories: nil,
            track: [],
            distanceSource: source,
            durationSource: source,
            elevationSource: elevationSource,
            heartRateSource: heartSource,
            cadenceSource: nil,
            energySource: nil,
            trackSource: nil
        )
    }

    private func healthRun(
        id: String,
        startedAt: Date,
        duration: TimeInterval,
        distance: Double?,
        elevation: Double? = nil,
        samples: [AnalyticsHeartRateSample] = [],
        average: Double? = 148,
        steps: Double? = nil,
        energy: Double? = nil
    ) -> ImportedHealthRun {
        ImportedHealthRun(
            id: id,
            name: "Run",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(duration),
            duration: duration,
            distanceMeters: distance,
            elevationGainMeters: elevation,
            averageHeartRate: average,
            heartRateSamples: samples,
            stepCount: steps,
            activeEnergyKilocalories: energy,
            track: []
        )
    }

    private func track(elevations: [Double?]) -> [AnalyticsTrackSample] {
        elevations.enumerated().map { index, elevation in
            AnalyticsTrackSample(
                latitude: nil,
                longitude: nil,
                elevationMeters: elevation,
                timestamp: start.addingTimeInterval(TimeInterval(index))
            )
        }
    }
}
