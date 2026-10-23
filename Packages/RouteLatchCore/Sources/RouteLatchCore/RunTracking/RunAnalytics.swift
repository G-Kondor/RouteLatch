import Foundation

public enum AnalyticsFieldSource: String, Equatable, Sendable {
    case health
    case recordedRun
}

public enum AnalyticsOrigin: Equatable, Sendable {
    case health
    case recordedRun
    case combined
}

public struct AnalyticsHeartRateSample: Equatable, Sendable {
    public let timestamp: Date
    public let beatsPerMinute: Double

    public init(timestamp: Date, beatsPerMinute: Double) {
        self.timestamp = timestamp
        self.beatsPerMinute = beatsPerMinute
    }
}

public struct AnalyticsTrackSample: Equatable, Sendable {
    public let latitude: Double?
    public let longitude: Double?
    public let elevationMeters: Double?
    public let timestamp: Date

    public init(latitude: Double?, longitude: Double?, elevationMeters: Double?, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevationMeters = elevationMeters
        self.timestamp = timestamp
    }
}

/// A running workout read from Apple Health. The phone app fills this in; the
/// analytics math below does not talk to HealthKit.
public struct ImportedHealthRun: Equatable, Sendable {
    public let id: String
    public let name: String
    public let startedAt: Date
    public let endedAt: Date
    public let duration: TimeInterval
    public let distanceMeters: Double?
    public let elevationGainMeters: Double?
    public let averageHeartRate: Double?
    public let heartRateSamples: [AnalyticsHeartRateSample]
    public let stepCount: Double?
    public let activeEnergyKilocalories: Double?
    public let track: [AnalyticsTrackSample]

    public init(
        id: String,
        name: String,
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval,
        distanceMeters: Double?,
        elevationGainMeters: Double?,
        averageHeartRate: Double?,
        heartRateSamples: [AnalyticsHeartRateSample],
        stepCount: Double?,
        activeEnergyKilocalories: Double?,
        track: [AnalyticsTrackSample]
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.distanceMeters = distanceMeters
        self.elevationGainMeters = elevationGainMeters
        self.averageHeartRate = averageHeartRate
        self.heartRateSamples = heartRateSamples
        self.stepCount = stepCount
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.track = track
    }
}

public struct AnalyticsActivity: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let startedAt: Date
    public let endedAt: Date
    public let duration: TimeInterval
    public let distanceMeters: Double
    public let elevationGainMeters: Double?
    public let averageHeartRate: Double?
    public let heartRateSamples: [AnalyticsHeartRateSample]
    public let averageCadenceStepsPerMinute: Double?
    public let activeEnergyKilocalories: Double?
    public let track: [AnalyticsTrackSample]
    public let distanceSource: AnalyticsFieldSource
    public let durationSource: AnalyticsFieldSource
    public let elevationSource: AnalyticsFieldSource?
    public let heartRateSource: AnalyticsFieldSource?
    public let cadenceSource: AnalyticsFieldSource?
    public let energySource: AnalyticsFieldSource?
    public let trackSource: AnalyticsFieldSource?

    public var paceSecondsPerKilometer: Double? {
        guard distanceMeters >= 1, duration > 0 else { return nil }
        let pace = duration / (distanceMeters / 1_000)
        return pace.isFinite && pace > 0 ? pace : nil
    }

    public var primaryOrigin: AnalyticsOrigin {
        let sources: [AnalyticsFieldSource] = [
            distanceSource, durationSource, elevationSource, heartRateSource, cadenceSource, energySource, trackSource
        ].compactMap { $0 }
        return RunAnalytics.origin(of: sources) ?? .recordedRun
    }

    init(
        id: String,
        name: String,
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval,
        distanceMeters: Double,
        elevationGainMeters: Double?,
        averageHeartRate: Double?,
        heartRateSamples: [AnalyticsHeartRateSample],
        averageCadenceStepsPerMinute: Double?,
        activeEnergyKilocalories: Double?,
        track: [AnalyticsTrackSample],
        distanceSource: AnalyticsFieldSource,
        durationSource: AnalyticsFieldSource,
        elevationSource: AnalyticsFieldSource?,
        heartRateSource: AnalyticsFieldSource?,
        cadenceSource: AnalyticsFieldSource?,
        energySource: AnalyticsFieldSource?,
        trackSource: AnalyticsFieldSource?
    ) {
        let cleanedSamples = heartRateSamples.filter {
            $0.beatsPerMinute.isFinite && (30...230).contains($0.beatsPerMinute)
        }
        let cadence = averageCadenceStepsPerMinute.flatMap { value -> Double? in
            guard value.isFinite, (40...250).contains(value) else { return nil }
            return value
        }
        let energy = activeEnergyKilocalories.flatMap { value -> Double? in
            guard value.isFinite, value > 0 else { return nil }
            return value
        }
        let elevation = elevationGainMeters.flatMap { value -> Double? in
            guard value.isFinite, value >= 0 else { return nil }
            return value
        }
        let heartAverage = averageHeartRate.flatMap { value -> Double? in
            guard value.isFinite, (30...230).contains(value) else { return nil }
            return value
        }
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Run" : name
        self.startedAt = startedAt
        self.endedAt = max(endedAt, startedAt)
        self.duration = max(0, duration.isFinite ? duration : 0)
        self.distanceMeters = max(0, distanceMeters.isFinite ? distanceMeters : 0)
        self.elevationGainMeters = elevation
        self.averageHeartRate = heartAverage
        self.heartRateSamples = cleanedSamples
        self.averageCadenceStepsPerMinute = cadence
        self.activeEnergyKilocalories = energy
        self.track = track
        self.distanceSource = distanceSource
        self.durationSource = durationSource
        self.elevationSource = elevation == nil ? nil : elevationSource
        self.heartRateSource = heartAverage == nil && cleanedSamples.isEmpty ? nil : heartRateSource
        self.cadenceSource = cadence == nil ? nil : cadenceSource
        self.energySource = energy == nil ? nil : energySource
        self.trackSource = track.isEmpty ? nil : trackSource
    }
}

public enum HeartRateZone: Int, CaseIterable, Equatable, Sendable {
    case recovery = 1
    case endurance
    case tempo
    case threshold
    case anaerobic

    public var title: String {
        switch self {
        case .recovery: "Recovery"
        case .endurance: "Endurance"
        case .tempo: "Tempo"
        case .threshold: "Threshold"
        case .anaerobic: "Anaerobic"
        }
    }

    /// Bands Runna publishes as matching Strava: 65 / 81 / 89 / 97 percent of max.
    /// Readings above the estimated max stay in anaerobic.
    public static func classify(beatsPerMinute: Double, maxHeartRate: Double) -> HeartRateZone? {
        guard beatsPerMinute.isFinite, beatsPerMinute > 0, maxHeartRate > 1 else { return nil }
        let fraction = beatsPerMinute / maxHeartRate
        if fraction <= 0.65 { return .recovery }
        if fraction <= 0.81 { return .endurance }
        if fraction <= 0.89 { return .tempo }
        if fraction <= 0.97 { return .threshold }
        return .anaerobic
    }
}

public struct HeartRateZoneSettings: Equatable, Sendable {
    public static let fallbackMaxHeartRate = 190.0
    public static let minimumAge = 13
    public static let maximumAge = 100

    public let age: Int?

    public init(age: Int?) {
        if let age, (Self.minimumAge...Self.maximumAge).contains(age) {
            self.age = age
        } else {
            self.age = nil
        }
    }

    public var maxHeartRate: Double {
        if let age { return Double(220 - age) }
        return Self.fallbackMaxHeartRate
    }

    public var usesEstimatedMax: Bool { age == nil }
}

public struct HeartRateZoneShare: Equatable, Sendable, Identifiable {
    public let zone: HeartRateZone
    public let duration: TimeInterval
    public let fraction: Double
    public let lowerBeatsPerMinute: Int
    public let upperBeatsPerMinute: Int?
    public var id: Int { zone.rawValue }
}

public struct KilometerSplit: Equatable, Sendable, Identifiable {
    public let index: Int
    public let distanceMeters: Double
    public let duration: TimeInterval
    public var id: Int { index }
    public var isPartial: Bool { distanceMeters < RunAnalytics.splitLengthMeters - 10 }
    public var paceSecondsPerKilometer: Double {
        guard distanceMeters > 0, duration > 0 else { return 0 }
        return duration / (distanceMeters / 1_000)
    }
}

public struct DistanceBucket: Equatable, Sendable, Identifiable {
    public let start: Date
    public let label: String
    public let spokenLabel: String
    public let distanceMeters: Double
    public let duration: TimeInterval
    public var id: Date { start }

    public var paceSecondsPerKilometer: Double? {
        guard distanceMeters >= 1, duration > 0 else { return nil }
        let pace = duration / (distanceMeters / 1_000)
        return pace.isFinite && pace > 0 ? pace : nil
    }
}

/// How full a day is on the year activity grid. Levels are relative to the busiest day in that year.
public enum ActivityLevel: Int, CaseIterable, Equatable, Sendable {
    case none = 0
    case low
    case moderate
    case high
    case peak

    public static func level(distanceMeters: Double, peak: Double) -> ActivityLevel {
        guard distanceMeters > 0, peak > 0 else { return .none }
        let ratio = distanceMeters / peak
        if ratio <= 0.25 { return .low }
        if ratio <= 0.50 { return .moderate }
        if ratio <= 0.75 { return .high }
        return .peak
    }
}

public struct ActivityDayCell: Equatable, Sendable, Identifiable {
    public let date: Date
    public let distanceMeters: Double
    public let duration: TimeInterval
    public let runCount: Int
    public let level: ActivityLevel
    /// A day after today, drawn so the current week stays a full column.
    public let isFuture: Bool
    public var id: Date { date }
}

public struct ActivityMonthLabel: Equatable, Sendable, Identifiable {
    public let column: Int
    public let title: String
    public var id: Int { column }
}

/// Fifty-three week columns, seven rows, matching a contribution graph.
public struct ActivityYearGrid: Equatable, Sendable {
    public let weeks: [[ActivityDayCell]]
    public let monthLabels: [ActivityMonthLabel]
    /// Seven rows. Monday, Wednesday, and Friday are labeled; the other rows are nil.
    public let rowLabels: [String?]
    public let activeDays: Int
    public let distanceMeters: Double
    public let runCount: Int
}

public enum AnalyticsRange: String, CaseIterable, Equatable, Sendable {
    case week
    case month
    case year
}

public struct TrainingSnapshot: Equatable, Sendable {
    public let range: AnalyticsRange
    public let windowStart: Date
    public let windowEnd: Date
    public let activities: [AnalyticsActivity]
    public let distanceMeters: Double
    public let duration: TimeInterval
    public let averagePaceSecondsPerKilometer: Double?
    public let distanceOrigin: AnalyticsOrigin?
    public let durationOrigin: AnalyticsOrigin?
    public let elevationGainMeters: Double?
    public let elevationOrigin: AnalyticsOrigin?
    public let elevationCount: Int
    public let zones: [HeartRateZoneShare]
    public let measuredHeartRate: TimeInterval
    public let heartRateOrigin: AnalyticsOrigin?
    public let effort: Int?
    public let averageCadenceStepsPerMinute: Double?
    public let cadenceOrigin: AnalyticsOrigin?
    public let cadenceCount: Int
    public let activeEnergyKilocalories: Double?
    public let energyOrigin: AnalyticsOrigin?
    public let energyCount: Int
    public let buckets: [DistanceBucket]
    public let splits: [KilometerSplit]
    public let splitRunName: String?
    public let splitRunStartedAt: Date?
    public let splitOrigin: AnalyticsOrigin?
    public let zoneSettings: HeartRateZoneSettings

    public var runCount: Int { activities.count }
}

public enum RunAnalytics {
    public static let splitLengthMeters = 1_000.0
    /// Current week plus fifty-two weeks behind it.
    static let activityYearWeeks = 53
    public static let minimumPartialSplitMeters = 50.0
    /// GPS altitudes jitter. Only a net rise of at least this many meters counts as climb.
    static let elevationNoiseGateMeters = 3.0
    /// A missing heart-rate sample is not time spent in the previous zone.
    static let maximumHeartRateSampleGap: TimeInterval = 15
    /// Health series are often one sample a second. Zone time only counts gaps up to
    /// `maximumHeartRateSampleGap`, so keeping a sample every few seconds preserves the
    /// totals while making the analytics pass cheap enough to run on the phone.
    public static let heartRateSampleSpacing: TimeInterval = 5
    static let matchWindow: TimeInterval = 10 * 60
    static let minimumMeasuredHeartRate: TimeInterval = 30

    /// Drops heart-rate samples that are closer together than `spacing`, and always
    /// keeps the last sample so the series still reaches the end of the run.
    public static func thinnedHeartRateSamples(
        _ samples: [AnalyticsHeartRateSample],
        spacing: TimeInterval = heartRateSampleSpacing
    ) -> [AnalyticsHeartRateSample] {
        let ordered = samples.sorted { $0.timestamp < $1.timestamp }
        let minimumGap = spacing.isFinite ? max(0, spacing) : heartRateSampleSpacing
        guard ordered.count > 2, minimumGap > 0 else { return ordered }
        var kept: [AnalyticsHeartRateSample] = []
        kept.reserveCapacity(min(ordered.count, Int(ordered.count / 4) + 2))
        kept.append(ordered[0])
        for index in 1..<ordered.count {
            let sample = ordered[index]
            let isLast = index == ordered.count - 1
            let gap = sample.timestamp.timeIntervalSince(kept[kept.count - 1].timestamp)
            guard gap > 0 else { continue }
            if isLast || gap >= minimumGap {
                kept.append(sample)
            }
        }
        return kept
    }

    public static func activities(health: [ImportedHealthRun], recorded: [RecordedRun]) -> [AnalyticsActivity] {
        var seen = Set<String>()
        var remainingHealth = health.filter { seen.insert($0.id).inserted }
        var merged: [AnalyticsActivity] = []
        for run in recorded.sorted(by: { $0.startedAt > $1.startedAt }) {
            if let index = matchIndex(for: run, in: remainingHealth) {
                merged.append(merge(health: remainingHealth.remove(at: index), recorded: run))
            } else if let activity = fromRecorded(run) {
                merged.append(activity)
            }
        }
        for workout in remainingHealth {
            if let activity = fromHealth(workout) {
                merged.append(activity)
            }
        }
        return merged.sorted { $0.startedAt > $1.startedAt }
    }

    /// A year of daily activity, laid out like a contribution graph.
    /// Columns are weeks and rows follow the calendar's first weekday.
    public static func activityYear(activities: [AnalyticsActivity], now: Date, calendar: Calendar) -> ActivityYearGrid {
        let empty = ActivityYearGrid(weeks: [], monthLabels: [], rowLabels: Array(repeating: nil, count: 7), activeDays: 0, distanceMeters: 0, runCount: 0)
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let daysFromWeekStart = (weekday - calendar.firstWeekday + 7) % 7
        guard let thisWeekStart = calendar.date(byAdding: .day, value: -daysFromWeekStart, to: today),
              let gridStart = calendar.date(byAdding: .weekOfYear, value: -(activityYearWeeks - 1), to: thisWeekStart) else {
            return empty
        }

        var totals: [Date: (distance: Double, duration: TimeInterval, count: Int)] = [:]
        for activity in activities {
            let day = calendar.startOfDay(for: activity.startedAt)
            guard day >= gridStart, day <= today else { continue }
            var entry = totals[day] ?? (0, 0, 0)
            entry.distance += activity.distanceMeters
            entry.duration += activity.duration
            entry.count += 1
            totals[day] = entry
        }
        let peak = totals.values.map(\.distance).max() ?? 0

        var weeks: [[ActivityDayCell]] = []
        var weekStarts: [Date] = []
        weeks.reserveCapacity(activityYearWeeks)
        for week in 0..<activityYearWeeks {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: week, to: gridStart) else { return empty }
            weekStarts.append(weekStart)
            var column: [ActivityDayCell] = []
            column.reserveCapacity(7)
            for row in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: row, to: weekStart) else { return empty }
                let day = calendar.startOfDay(for: date)
                let future = day > today
                let stats = future ? nil : totals[day]
                let distance = stats?.distance ?? 0
                column.append(ActivityDayCell(
                    date: day,
                    distanceMeters: distance,
                    duration: stats?.duration ?? 0,
                    runCount: stats?.count ?? 0,
                    level: ActivityLevel.level(distanceMeters: distance, peak: peak),
                    isFuture: future
                ))
            }
            weeks.append(column)
        }

        let cells = weeks.flatMap { $0 }.filter { !$0.isFuture }
        return ActivityYearGrid(
            weeks: weeks,
            monthLabels: monthLabels(weekStarts: weekStarts, calendar: calendar),
            rowLabels: rowLabels(calendar: calendar),
            activeDays: cells.filter { $0.runCount > 0 }.count,
            distanceMeters: cells.reduce(0) { $0 + $1.distanceMeters },
            runCount: cells.reduce(0) { $0 + $1.runCount }
        )
    }

    public static func snapshot(
        activities: [AnalyticsActivity],
        range: AnalyticsRange,
        now: Date,
        calendar: Calendar,
        zones settings: HeartRateZoneSettings
    ) -> TrainingSnapshot {
        guard let buckets = makeBuckets(range: range, now: now, calendar: calendar),
              let first = buckets.first, let last = buckets.last else {
            return blank(range: range, now: now, settings: settings)
        }
        let windowActivities = activities
            .filter { $0.startedAt >= first.start && $0.startedAt < last.end }
            .sorted { $0.startedAt > $1.startedAt }
        let distance = windowActivities.reduce(0.0) { $0 + $1.distanceMeters }
        let duration = windowActivities.reduce(0.0) { $0 + $1.duration }
        let pace: Double? = distance >= 1 && duration > 0 ? duration / (distance / 1_000) : nil
        let elevated = windowActivities.compactMap { activity -> (Double, AnalyticsFieldSource)? in
            guard let gain = activity.elevationGainMeters, let source = activity.elevationSource else { return nil }
            return (gain, source)
        }
        let cadenceRuns = windowActivities.compactMap { activity -> (Double, TimeInterval, AnalyticsFieldSource)? in
            guard let cadence = activity.averageCadenceStepsPerMinute, let source = activity.cadenceSource, activity.duration > 0 else { return nil }
            return (cadence, activity.duration, source)
        }
        let energyRuns = windowActivities.compactMap { activity -> (Double, AnalyticsFieldSource)? in
            guard let energy = activity.activeEnergyKilocalories, let source = activity.energySource else { return nil }
            return (energy, source)
        }
        let zoneTotals = zoneDurations(in: windowActivities, maxHeartRate: settings.maxHeartRate)
        let measuredHeartRate = zoneTotals.values.reduce(0.0, +)
        let zoneShares = shares(from: zoneTotals, measured: measuredHeartRate, maxHeartRate: settings.maxHeartRate)
        let effort = effortScore(zoneTotals, measured: measuredHeartRate)
        let cadenceTotal = cadenceRuns.reduce(0.0) { $0 + $1.1 }
        let averageCadence = cadenceTotal > 0 ? cadenceRuns.reduce(0.0) { $0 + $1.0 * $1.1 } / cadenceTotal : nil
        let featured = windowActivities.first { !kilometerSplits(track: $0.track, distanceMeters: $0.distanceMeters).isEmpty } ?? windowActivities.first
        let splits = featured.map { kilometerSplits(track: $0.track, distanceMeters: $0.distanceMeters) } ?? []
        let splitOrigin: AnalyticsOrigin? = {
            guard !splits.isEmpty, let source = featured?.trackSource else { return nil }
            return origin(of: [source])
        }()
        let finitePace = pace.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        return TrainingSnapshot(
            range: range,
            windowStart: first.start,
            windowEnd: last.end,
            activities: windowActivities,
            distanceMeters: distance,
            duration: duration,
            averagePaceSecondsPerKilometer: finitePace,
            distanceOrigin: origin(of: windowActivities.map(\.distanceSource)),
            durationOrigin: origin(of: windowActivities.map(\.durationSource)),
            elevationGainMeters: elevated.isEmpty ? nil : elevated.reduce(0.0) { $0 + $1.0 },
            elevationOrigin: origin(of: elevated.map(\.1)),
            elevationCount: elevated.count,
            zones: zoneShares,
            measuredHeartRate: measuredHeartRate,
            heartRateOrigin: origin(of: windowActivities.compactMap(\.heartRateSource)),
            effort: effort,
            averageCadenceStepsPerMinute: averageCadence,
            cadenceOrigin: origin(of: cadenceRuns.map(\.2)),
            cadenceCount: cadenceRuns.count,
            activeEnergyKilocalories: energyRuns.isEmpty ? nil : energyRuns.reduce(0.0) { $0 + $1.0 },
            energyOrigin: origin(of: energyRuns.map(\.1)),
            energyCount: energyRuns.count,
            buckets: buckets.map { spec in
                let matching = windowActivities.filter { $0.startedAt >= spec.start && $0.startedAt < spec.end }
                return DistanceBucket(
                    start: spec.start,
                    label: spec.label,
                    spokenLabel: spec.spokenLabel,
                    distanceMeters: matching.reduce(0.0) { $0 + $1.distanceMeters },
                    duration: matching.reduce(0.0) { $0 + $1.duration }
                )
            },
            splits: splits,
            splitRunName: featured?.name,
            splitRunStartedAt: featured?.startedAt,
            splitOrigin: splitOrigin,
            zoneSettings: settings
        )
    }

    static func kilometerSplits(track: [AnalyticsTrackSample], distanceMeters: Double) -> [KilometerSplit] {
        let official = distanceMeters.isFinite ? max(0, distanceMeters) : 0
        let cumulative = cumulativeDistance(track)
        guard official > 1, let last = cumulative.last, last.distance > 1, let first = cumulative.first else { return [] }
        let scale = official / last.distance
        let scaled = cumulative.map { (distance: $0.distance * scale, time: $0.time) }
        return split(scaled, total: official, startTime: first.time)
    }

    static func elevationGainMeters(of track: [AnalyticsTrackSample]) -> Double? {
        var reference: Double?
        var gain = 0.0
        var sawSample = false
        for sample in track {
            guard let elevation = sample.elevationMeters, elevation.isFinite else { continue }
            sawSample = true
            guard let current = reference else {
                reference = elevation
                continue
            }
            let delta = elevation - current
            if abs(delta) >= elevationNoiseGateMeters {
                if delta > 0 { gain += delta }
                reference = elevation
            }
        }
        return sawSample ? gain : nil
    }

    static func origin(of sources: [AnalyticsFieldSource]) -> AnalyticsOrigin? {
        let unique = Set(sources)
        if unique.isEmpty { return nil }
        if unique.count > 1 { return .combined }
        return unique.contains(.health) ? .health : .recordedRun
    }

    private struct BucketSpec {
        let start: Date
        let end: Date
        let label: String
        let spokenLabel: String
    }

    private static func merge(health: ImportedHealthRun, recorded: RecordedRun) -> AnalyticsActivity {
        let distance: Double
        let distanceSource: AnalyticsFieldSource
        if let healthDistance = finitePositive(health.distanceMeters) {
            distance = healthDistance
            distanceSource = .health
        } else {
            distance = recorded.distanceMeters
            distanceSource = .recordedRun
        }
        let durationSource: AnalyticsFieldSource
        let duration: TimeInterval
        if recorded.activeDuration > 0 {
            duration = recorded.activeDuration
            durationSource = .recordedRun
        } else if health.duration > 0 {
            duration = health.duration
            durationSource = .health
        } else {
            duration = max(0, health.endedAt.timeIntervalSince(health.startedAt))
            durationSource = .health
        }
        let recordedTrack = track(from: recorded.points)
        let trackSource: AnalyticsFieldSource?
        let chosenTrack: [AnalyticsTrackSample]
        if recordedTrack.contains(where: { $0.latitude != nil && $0.longitude != nil }) {
            chosenTrack = recordedTrack
            trackSource = .recordedRun
        } else if health.track.contains(where: { $0.latitude != nil && $0.longitude != nil }) {
            chosenTrack = health.track
            trackSource = .health
        } else {
            chosenTrack = []
            trackSource = nil
        }
        let elevation = resolvedElevation(health: health, track: chosenTrack, trackSource: trackSource)
        let heart = resolvedHeartRate(health: health, recorded: recorded)
        return AnalyticsActivity(
            id: "health:\(health.id)",
            name: recorded.name,
            startedAt: min(health.startedAt, recorded.startedAt),
            endedAt: max(health.endedAt, recorded.endedAt),
            duration: duration,
            distanceMeters: distance,
            elevationGainMeters: elevation.value,
            averageHeartRate: heart.average,
            heartRateSamples: heart.samples,
            averageCadenceStepsPerMinute: cadence(stepCount: health.stepCount, duration: health.duration > 0 ? health.duration : duration),
            activeEnergyKilocalories: finitePositive(health.activeEnergyKilocalories),
            track: chosenTrack,
            distanceSource: distanceSource,
            durationSource: durationSource,
            elevationSource: elevation.source,
            heartRateSource: heart.source,
            cadenceSource: health.stepCount == nil ? nil : .health,
            energySource: health.activeEnergyKilocalories == nil ? nil : .health,
            trackSource: trackSource
        )
    }

    private static func fromHealth(_ health: ImportedHealthRun) -> AnalyticsActivity? {
        let distance = finitePositive(health.distanceMeters) ?? 0
        let duration = health.duration > 0 ? health.duration : max(0, health.endedAt.timeIntervalSince(health.startedAt))
        guard distance > 0 || duration > 0 else { return nil }
        let samples = cleanSamples(health.heartRateSamples)
        let average = finiteHeart(health.averageHeartRate) ?? averageHeartRate(samples)
        let elevation = resolvedElevation(health: health, track: health.track, trackSource: health.track.isEmpty ? nil : .health)
        return AnalyticsActivity(
            id: "health:\(health.id)",
            name: health.name,
            startedAt: health.startedAt,
            endedAt: health.endedAt,
            duration: duration,
            distanceMeters: distance,
            elevationGainMeters: elevation.value,
            averageHeartRate: average,
            heartRateSamples: samples,
            averageCadenceStepsPerMinute: cadence(stepCount: health.stepCount, duration: duration),
            activeEnergyKilocalories: finitePositive(health.activeEnergyKilocalories),
            track: health.track,
            distanceSource: .health,
            durationSource: .health,
            elevationSource: elevation.source,
            heartRateSource: average == nil && samples.isEmpty ? nil : .health,
            cadenceSource: .health,
            energySource: .health,
            trackSource: health.track.isEmpty ? nil : .health
        )
    }

    private static func fromRecorded(_ run: RecordedRun) -> AnalyticsActivity? {
        guard run.distanceMeters > 0 || run.activeDuration > 0 else { return nil }
        let samples = heartSamples(from: run.points)
        let chosenTrack = track(from: run.points)
        let elevation = elevationGainMeters(of: chosenTrack)
        return AnalyticsActivity(
            id: "phone:\(run.id.uuidString)",
            name: run.name,
            startedAt: run.startedAt,
            endedAt: run.endedAt,
            duration: run.activeDuration,
            distanceMeters: run.distanceMeters,
            elevationGainMeters: elevation,
            averageHeartRate: averageHeartRate(samples),
            heartRateSamples: samples,
            averageCadenceStepsPerMinute: nil,
            activeEnergyKilocalories: nil,
            track: chosenTrack,
            distanceSource: .recordedRun,
            durationSource: .recordedRun,
            elevationSource: .recordedRun,
            heartRateSource: .recordedRun,
            cadenceSource: nil,
            energySource: nil,
            trackSource: chosenTrack.isEmpty ? nil : .recordedRun
        )
    }

    private static func resolvedElevation(
        health: ImportedHealthRun,
        track: [AnalyticsTrackSample],
        trackSource: AnalyticsFieldSource?
    ) -> (value: Double?, source: AnalyticsFieldSource?) {
        if let gain = health.elevationGainMeters, gain.isFinite, gain >= 0 {
            return (gain, .health)
        }
        guard let gain = elevationGainMeters(of: track), let trackSource else { return (nil, nil) }
        return (gain, trackSource)
    }

    private static func resolvedHeartRate(health: ImportedHealthRun, recorded: RecordedRun) -> (samples: [AnalyticsHeartRateSample], average: Double?, source: AnalyticsFieldSource?) {
        let healthSamples = cleanSamples(health.heartRateSamples)
        if !healthSamples.isEmpty || finiteHeart(health.averageHeartRate) != nil {
            return (healthSamples, finiteHeart(health.averageHeartRate) ?? averageHeartRate(healthSamples), .health)
        }
        let recordedSamples = heartSamples(from: recorded.points)
        guard !recordedSamples.isEmpty else { return ([], nil, nil) }
        return (recordedSamples, averageHeartRate(recordedSamples), .recordedRun)
    }

    private static func matchIndex(for run: RecordedRun, in health: [ImportedHealthRun]) -> Int? {
        health.enumerated()
            .filter { _, workout in
                abs(workout.startedAt.timeIntervalSince(run.startedAt)) <= matchWindow
                    && distancesCompatible(workout.distanceMeters, run.distanceMeters)
            }
            .min { lhs, rhs in
                let leftGap = abs(lhs.element.startedAt.timeIntervalSince(run.startedAt))
                let rightGap = abs(rhs.element.startedAt.timeIntervalSince(run.startedAt))
                if leftGap != rightGap { return leftGap < rightGap }
                let leftDistance = abs((lhs.element.distanceMeters ?? run.distanceMeters) - run.distanceMeters)
                let rightDistance = abs((rhs.element.distanceMeters ?? run.distanceMeters) - run.distanceMeters)
                return leftDistance < rightDistance
            }?
            .offset
    }

    private static func distancesCompatible(_ healthDistance: Double?, _ recordedDistance: Double) -> Bool {
        guard let healthDistance, healthDistance > 0, recordedDistance > 0 else { return true }
        let ratio = healthDistance / recordedDistance
        return ratio >= 0.6 && ratio <= 1.67
    }

    private static func cadence(stepCount: Double?, duration: TimeInterval) -> Double? {
        guard let stepCount, stepCount.isFinite, stepCount > 0, duration >= 30 else { return nil }
        let stepsPerMinute = stepCount / (duration / 60)
        guard stepsPerMinute.isFinite, (40...250).contains(stepsPerMinute) else { return nil }
        return stepsPerMinute
    }

    private static func zoneDurations(in activities: [AnalyticsActivity], maxHeartRate: Double) -> [HeartRateZone: TimeInterval] {
        var totals: [HeartRateZone: TimeInterval] = [:]
        for activity in activities {
            for (zone, duration) in zoneTime(samples: activity.heartRateSamples, maxHeartRate: maxHeartRate) {
                totals[zone, default: 0] += duration
            }
        }
        return totals
    }

    private static func zoneTime(samples: [AnalyticsHeartRateSample], maxHeartRate: Double) -> [HeartRateZone: TimeInterval] {
        let ordered = samples.sorted { $0.timestamp < $1.timestamp }
        guard ordered.count >= 2 else { return [:] }
        var totals: [HeartRateZone: TimeInterval] = [:]
        for (previous, next) in zip(ordered, ordered.dropFirst()) {
            let gap = next.timestamp.timeIntervalSince(previous.timestamp)
            guard gap > 0, let zone = HeartRateZone.classify(beatsPerMinute: previous.beatsPerMinute, maxHeartRate: maxHeartRate) else { continue }
            totals[zone, default: 0] += min(gap, maximumHeartRateSampleGap)
        }
        return totals
    }

    private static func shares(from totals: [HeartRateZone: TimeInterval], measured: TimeInterval, maxHeartRate: Double) -> [HeartRateZoneShare] {
        guard measured >= minimumMeasuredHeartRate else { return [] }
        return HeartRateZone.allCases.map { zone in
            let duration = totals[zone] ?? 0
            let bounds = heartRateBounds(for: zone, maxHeartRate: maxHeartRate)
            return HeartRateZoneShare(
                zone: zone,
                duration: duration,
                fraction: duration / measured,
                lowerBeatsPerMinute: bounds.lower,
                upperBeatsPerMinute: bounds.upper
            )
        }
    }

    /// Minutes in each zone, multiplied by the zone number. This is the Edwards
    /// training impulse, which stays defined without a resting heart rate.
    private static func effortScore(_ totals: [HeartRateZone: TimeInterval], measured: TimeInterval) -> Int? {
        guard measured >= minimumMeasuredHeartRate else { return nil }
        let weightedMinutes = HeartRateZone.allCases.reduce(0.0) { partial, zone in
            partial + ((totals[zone] ?? 0) / 60) * Double(zone.rawValue)
        }
        let rounded = Int(weightedMinutes.rounded())
        return rounded > 0 ? rounded : nil
    }

    private static func heartRateBounds(for zone: HeartRateZone, maxHeartRate: Double) -> (lower: Int, upper: Int?) {
        func bpm(_ fraction: Double) -> Int { Int((fraction * maxHeartRate).rounded()) }
        switch zone {
        case .recovery:
            return (0, bpm(0.65))
        case .endurance:
            return (bpm(0.65) + 1, bpm(0.81))
        case .tempo:
            return (bpm(0.81) + 1, bpm(0.89))
        case .threshold:
            return (bpm(0.89) + 1, bpm(0.97))
        case .anaerobic:
            return (bpm(0.97) + 1, nil)
        }
    }

    private static func cumulativeDistance(_ track: [AnalyticsTrackSample]) -> [(distance: Double, time: Date)] {
        var points: [(distance: Double, time: Date)] = []
        var raw = 0.0
        var previous: (latitude: Double, longitude: Double, time: Date)?
        for sample in track.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard let latitude = sample.latitude, let longitude = sample.longitude,
                  latitude.isFinite, longitude.isFinite,
                  (-90...90).contains(latitude), (-180...180).contains(longitude) else { continue }
            if let previous {
                let elapsed = sample.timestamp.timeIntervalSince(previous.time)
                let segment = haversine(previous.latitude, previous.longitude, latitude, longitude)
                guard elapsed > 0, segment.isFinite, segment / elapsed <= 12 else { continue }
                raw += segment
                points.append((raw, sample.timestamp))
            } else {
                points.append((0, sample.timestamp))
            }
            previous = (latitude, longitude, sample.timestamp)
        }
        return points
    }

    private static func split(_ points: [(distance: Double, time: Date)], total: Double, startTime: Date) -> [KilometerSplit] {
        guard points.count >= 2, total >= minimumPartialSplitMeters else { return [] }
        var results: [KilometerSplit] = []
        var consumed = 0.0
        var index = 1
        while index <= 300 {
            let remaining = total - consumed
            let length: Double
            if remaining >= splitLengthMeters - 0.5 {
                length = min(splitLengthMeters, remaining)
            } else if remaining >= minimumPartialSplitMeters {
                length = remaining
            } else {
                break
            }
            guard let start = time(on: points, at: consumed, fallback: startTime),
                  let end = time(on: points, at: consumed + length, fallback: startTime) else { break }
            let duration = end.timeIntervalSince(start)
            if duration > 0 {
                results.append(KilometerSplit(index: index, distanceMeters: length, duration: duration))
            }
            consumed += length
            index += 1
            if length < splitLengthMeters - 0.5 { break }
        }
        return results
    }

    private static func time(on points: [(distance: Double, time: Date)], at distance: Double, fallback: Date) -> Date? {
        guard let first = points.first, let last = points.last else { return nil }
        if distance <= first.distance { return first.time }
        if distance >= last.distance { return last.time }
        for (left, right) in zip(points, points.dropFirst()) where right.distance >= distance && right.distance > left.distance {
            let fraction = (distance - left.distance) / (right.distance - left.distance)
            return left.time.addingTimeInterval(right.time.timeIntervalSince(left.time) * fraction)
        }
        return fallback
    }

    private static func makeBuckets(range: AnalyticsRange, now: Date, calendar: Calendar) -> [BucketSpec]? {
        let today = calendar.startOfDay(for: now)
        switch range {
        case .week:
            return (0..<7).compactMap { index in
                guard let start = calendar.date(byAdding: .day, value: index - 6, to: today),
                      let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
                return BucketSpec(start: start, end: end, label: format(start, "EEEEE", calendar), spokenLabel: format(start, "EEEE", calendar))
            }
        case .month:
            guard let windowStart = calendar.date(byAdding: .day, value: -27, to: today) else { return nil }
            return (0..<4).compactMap { index in
                guard let start = calendar.date(byAdding: .day, value: index * 7, to: windowStart),
                      let end = calendar.date(byAdding: .day, value: 7, to: start) else { return nil }
                return BucketSpec(start: start, end: end, label: format(start, "d MMM", calendar), spokenLabel: "Week of \(format(start, "MMMM d", calendar))")
            }
        case .year:
            let parts = calendar.dateComponents([.year, .month], from: now)
            guard let monthStart = calendar.date(from: parts),
                  let firstMonth = calendar.date(byAdding: .month, value: -11, to: monthStart) else { return nil }
            return (0..<12).compactMap { index in
                guard let start = calendar.date(byAdding: .month, value: index, to: firstMonth),
                      let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
                return BucketSpec(start: start, end: end, label: format(start, "MMM", calendar), spokenLabel: format(start, "MMMM yyyy", calendar))
            }
        }
    }

    private static func monthLabels(weekStarts: [Date], calendar: Calendar) -> [ActivityMonthLabel] {
        var labels: [ActivityMonthLabel] = []
        var seenMonth: Int?
        for (column, start) in weekStarts.enumerated() {
            let month = calendar.component(.month, from: start)
            let year = calendar.component(.year, from: start)
            let key = year * 12 + month
            if key != seenMonth {
                if labels.last.map({ column - $0.column >= 2 }) ?? true {
                    labels.append(ActivityMonthLabel(column: column, title: format(start, "MMM", calendar)))
                }
                seenMonth = key
            }
        }
        return labels
    }

    private static func rowLabels(calendar: Calendar) -> [String?] {
        let symbols = calendar.shortWeekdaySymbols
        guard symbols.count == 7 else { return Array(repeating: nil, count: 7) }
        return (0..<7).map { row in
            let weekday = ((calendar.firstWeekday - 1 + row) % 7) + 1
            switch weekday {
            case 2, 4, 6:
                return symbols[weekday - 1]
            default:
                return nil
            }
        }
    }

    private static func format(_ date: Date, _ template: String, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? Locale.current
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = template
        return formatter.string(from: date)
    }

    private static func blank(range: AnalyticsRange, now: Date, settings: HeartRateZoneSettings) -> TrainingSnapshot {
        TrainingSnapshot(
            range: range,
            windowStart: now,
            windowEnd: now,
            activities: [],
            distanceMeters: 0,
            duration: 0,
            averagePaceSecondsPerKilometer: nil,
            distanceOrigin: nil,
            durationOrigin: nil,
            elevationGainMeters: nil,
            elevationOrigin: nil,
            elevationCount: 0,
            zones: [],
            measuredHeartRate: 0,
            heartRateOrigin: nil,
            effort: nil,
            averageCadenceStepsPerMinute: nil,
            cadenceOrigin: nil,
            cadenceCount: 0,
            activeEnergyKilocalories: nil,
            energyOrigin: nil,
            energyCount: 0,
            buckets: [],
            splits: [],
            splitRunName: nil,
            splitRunStartedAt: nil,
            splitOrigin: nil,
            zoneSettings: settings
        )
    }

    private static func track(from points: [RecordedRunPoint]) -> [AnalyticsTrackSample] {
        points.map { point in
            AnalyticsTrackSample(
                latitude: coordinate(point.latitude, range: -90...90),
                longitude: coordinate(point.longitude, range: -180...180),
                elevationMeters: point.elevation.flatMap { $0.isFinite ? $0 : nil },
                timestamp: point.timestamp
            )
        }
    }

    private static func coordinate(_ value: Double?, range: ClosedRange<Double>) -> Double? {
        guard let value, value.isFinite, range.contains(value) else { return nil }
        return value
    }

    private static func heartSamples(from points: [RecordedRunPoint]) -> [AnalyticsHeartRateSample] {
        cleanSamples(points.compactMap { point in
            guard let heartRate = point.heartRate else { return nil }
            return AnalyticsHeartRateSample(timestamp: point.timestamp, beatsPerMinute: heartRate)
        })
    }

    private static func cleanSamples(_ samples: [AnalyticsHeartRateSample]) -> [AnalyticsHeartRateSample] {
        samples.filter { $0.beatsPerMinute.isFinite && (30...230).contains($0.beatsPerMinute) }
    }

    private static func averageHeartRate(_ samples: [AnalyticsHeartRateSample]) -> Double? {
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0.0) { $0 + $1.beatsPerMinute } / Double(samples.count)
    }

    private static func finitePositive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func finiteHeart(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (30...230).contains(value) else { return nil }
        return value
    }

    private static func haversine(_ latitudeA: Double, _ longitudeA: Double, _ latitudeB: Double, _ longitudeB: Double) -> Double {
        let radius = 6_371_008.8
        let phiA = latitudeA * .pi / 180
        let phiB = latitudeB * .pi / 180
        let deltaPhi = phiB - phiA
        let deltaLambda = (longitudeB - longitudeA) * .pi / 180
        let h = sin(deltaPhi / 2) * sin(deltaPhi / 2) + cos(phiA) * cos(phiB) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        return radius * 2 * atan2(sqrt(h), sqrt(max(0, 1 - h)))
    }
}
