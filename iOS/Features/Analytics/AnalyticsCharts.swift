import RouteLatchCore
import SwiftUI

struct ChartDetailRow: Equatable {
    let label: String
    let value: String
}

struct TrendChartSample: Identifiable {
    let id: Int
    let label: String
    let title: String
    let value: Double?
    let spoken: String
    let rows: [ChartDetailRow]
}

struct ChartPointOverview: View {
    let title: String
    let rows: [ChartDetailRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LatchColor.ink)
                .lineLimit(2)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.label)
                        .font(.caption)
                        .foregroundStyle(LatchColor.muted)
                    Spacer(minLength: 8)
                    Text(row.value)
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(LatchColor.ink)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .latchGlass(radius: 16)
        .accessibilityElement(children: .combine)
    }
}

/// Area and bar chart with a vertical brand gradient, in the style of a training trend.
struct GradientTrendChart: View {
    let samples: [TrendChartSample]
    var showsBars = true
    @State private var selectedID: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let layout = TrendLayout(samples: samples, size: geo.size)
                Canvas { context, size in
                    drawChart(context: &context, layout: layout, canvasSize: size)
                }
                .overlay {
                    ZStack {
                        if selectedSample == nil {
                            peakMarker(layout)
                            callout(layout)
                        }
                        selectionMarker(layout)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            toggleSelection(at: value.location.x, layout: layout)
                        }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(selectedSample?.title ?? "Chart")
                .accessibilityValue(selectedAccessibilityValue)
                .accessibilityHint("Tap a point, or swipe up and down, to see its numbers.")
                .accessibilityAdjustableAction { direction in
                    adjustSelection(direction)
                }
            }
            .frame(height: 168)
            labels
            if let selectedSample {
                ChartPointOverview(title: selectedSample.title, rows: selectedSample.rows)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.2), value: selectedID)
        .onChange(of: samples.map(\.title)) { _, _ in
            selectedID = nil
        }
    }

    private var selectedSample: TrendChartSample? {
        samples.first { $0.id == selectedID }
    }

    private var selectedAccessibilityValue: String {
        guard let selectedSample else { return accessibilitySummary }
        let details = selectedSample.rows.map { "\($0.label) \($0.value)" }.joined(separator: ", ")
        return "\(selectedSample.title). \(details)"
    }

    private var labels: some View {
        HStack(spacing: 0) {
            ForEach(samples) { sample in
                let selected = sample.id == selectedID
                Button {
                    selectedID = selected ? nil : sample.id
                } label: {
                    Text(sample.label)
                        .font(.system(size: samples.count > 8 ? 9 : 11, weight: selected ? .bold : .semibold))
                        .foregroundStyle(selected ? LatchColor.accent : LatchColor.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(sample.title)
                .accessibilityValue(sample.rows.map { "\($0.label) \($0.value)" }.joined(separator: ", "))
                .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
            }
        }
    }

    private var accessibilitySummary: String {
        samples.map { "\($0.label), \($0.spoken)" }.joined(separator: ". ")
    }

    private func drawChart(context: inout GraphicsContext, layout: TrendLayout, canvasSize: CGSize) {
        if showsBars {
            for point in layout.points.compactMap({ $0 }) where point.value > 0 {
                let height = max(8, layout.bottom - point.y)
                let rect = CGRect(x: point.x - layout.barWidth / 2, y: layout.bottom - height, width: layout.barWidth, height: height)
                let path = Path(roundedRect: rect, cornerRadius: min(7, layout.barWidth / 2))
                context.fill(path, with: .linearGradient(
                    Gradient(colors: [LatchColor.accent, LatchColor.accent.opacity(0.16)]),
                    startPoint: CGPoint(x: point.x, y: rect.minY),
                    endPoint: CGPoint(x: point.x, y: rect.maxY)
                ))
            }
        }
        let bounds = CGRect(origin: .zero, size: canvasSize)
        context.fill(
            TrendFill(segments: layout.segments, bottom: layout.bottom).path(in: bounds),
            with: .linearGradient(
                Gradient(colors: [LatchColor.accent.opacity(0.48), LatchColor.accent.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: layout.bottom)
            )
        )
        context.stroke(
            TrendStroke(segments: layout.segments).path(in: bounds),
            with: .color(LatchColor.accent),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        )
    }

    private func peakMarker(_ layout: TrendLayout) -> some View {
        ZStack {
            if let peak = layout.peak {
                Circle()
                    .fill(LatchColor.canvas)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(LatchColor.accent, lineWidth: 2.5))
                    .position(peak.point)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func callout(_ layout: TrendLayout) -> some View {
        ZStack {
            if let peak = layout.peak {
                Text(peak.spoken)
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(LatchColor.canvas)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(LatchColor.ink, in: Capsule())
                    .position(x: layout.calloutX(for: peak.point), y: max(12, peak.point.y - 18))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func selectionMarker(_ layout: TrendLayout) -> some View {
        ZStack {
            if let selected = selectionPoint(layout) {
                Rectangle()
                    .fill(LatchColor.accent.opacity(0.45))
                    .frame(width: 1.5, height: max(1, layout.bottom - 28))
                    .position(x: selected.x, y: (layout.bottom + 28) / 2)
                Circle()
                    .fill(LatchColor.canvas)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(LatchColor.accent, lineWidth: 2.5))
                    .position(x: selected.x, y: selected.y)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func selectionPoint(_ layout: TrendLayout) -> CGPoint? {
        guard let index = samples.firstIndex(where: { $0.id == selectedID }) else { return nil }
        let count = CGFloat(max(samples.count, 1))
        let x = layout.width / count * (CGFloat(index) + 0.5)
        let y = layout.points.indices.contains(index) ? (layout.points[index]?.y ?? layout.bottom) : layout.bottom
        return CGPoint(x: x, y: y)
    }

    private func toggleSelection(at x: CGFloat, layout: TrendLayout) {
        guard !samples.isEmpty, layout.width > 0 else { return }
        let step = layout.width / CGFloat(samples.count)
        let index = min(samples.count - 1, max(0, Int(x / step)))
        let id = samples[index].id
        selectedID = selectedID == id ? nil : id
    }

    private func adjustSelection(_ direction: AccessibilityAdjustmentDirection) {
        guard !samples.isEmpty else { return }
        let current = samples.firstIndex { $0.id == selectedID }
        let next: Int
        switch direction {
        case .increment:
            next = min(samples.count - 1, (current ?? -1) + 1)
        case .decrement:
            next = max(0, (current ?? samples.count) - 1)
        @unknown default:
            return
        }
        selectedID = samples[next].id
    }
}

struct SplitPaceChart: View {
    let splits: [KilometerSplit]
    let paceText: (Double) -> String
    @State private var selectedIndex: Int?

    private var visible: [KilometerSplit] { Array(splits.prefix(12)) }

    var body: some View {
        let slowest = max(visible.map(\.paceSecondsPerKilometer).max() ?? 1, 1)
        let fastest = visible.map(\.paceSecondsPerKilometer).min() ?? slowest
        VStack(spacing: 7) {
            ForEach(visible) { split in
                let selected = selectedIndex == split.index
                Button {
                    selectedIndex = selected ? nil : split.index
                } label: {
                    HStack(spacing: 8) {
                        Text(split.isPartial ? String(format: "%.1f", split.distanceMeters / 1_000) : "\(split.index)")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(selected ? LatchColor.accent : LatchColor.muted)
                            .frame(width: 26, alignment: .trailing)
                        GeometryReader { geo in
                            let width = max(8, geo.size.width * split.paceSecondsPerKilometer / slowest)
                            let strength = paceStrength(split.paceSecondsPerKilometer, fastest: fastest, slowest: slowest)
                            Capsule()
                                .fill(LatchColor.chip)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [LatchColor.accent.opacity(strength), LatchColor.accent.opacity(0.22)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: width)
                                }
                        }
                        .frame(height: 10)
                        Text(paceText(split.paceSecondsPerKilometer))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(LatchColor.ink)
                            .frame(width: 72, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(selected ? LatchColor.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(split.isPartial ? "Partial kilometer" : "Kilometer \(split.index)")
                .accessibilityValue("\(split.distanceMeters.formattedDistance), \(chartClock(split.duration)), \(paceText(split.paceSecondsPerKilometer))")
                .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
            }
            if let split = visible.first(where: { $0.index == selectedIndex }) {
                ChartPointOverview(title: splitTitle(split), rows: splitRows(split))
            }
        }
        .animation(.snappy(duration: 0.2), value: selectedIndex)
    }

    private func splitTitle(_ split: KilometerSplit) -> String {
        split.isPartial ? String(format: "%.1f km", split.distanceMeters / 1_000) : "Kilometer \(split.index)"
    }

    private func splitRows(_ split: KilometerSplit) -> [ChartDetailRow] {
        [
            ChartDetailRow(label: "Distance", value: split.distanceMeters.formattedDistance),
            ChartDetailRow(label: "Time", value: chartClock(split.duration)),
            ChartDetailRow(label: "Pace", value: paceText(split.paceSecondsPerKilometer))
        ]
    }

    private func paceStrength(_ pace: Double, fastest: Double, slowest: Double) -> Double {
        guard slowest > fastest else { return 0.9 }
        let span = slowest - fastest
        let closeness = (slowest - pace) / span
        return 0.35 + 0.65 * min(1, max(0, closeness))
    }
}

struct ActivityYearChart: View {
    let grid: ActivityYearGrid
    @State private var selectedDay: Date?

    private let cellSize: CGFloat = 12
    private let cellGap: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 6) {
                weekdayLabels
                    .accessibilityHidden(true)
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: cellGap) {
                        monthLabels
                        HStack(alignment: .top, spacing: cellGap) {
                            ForEach(grid.weeks.indices, id: \.self) { column in
                                VStack(spacing: cellGap) {
                                    ForEach(grid.weeks[column]) { day in
                                        dayButton(day)
                                    }
                                }
                            }
                        }
                    }
                }
                .defaultScrollAnchor(.trailing)
                .accessibilityHidden(true)
            }
            legend
                .accessibilityHidden(true)
            if let selected = selectedCell {
                ChartPointOverview(title: selected.date.formatted(date: .abbreviated, time: .omitted), rows: dayRows(selected))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.2), value: selectedDay)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Year of activity")
        .accessibilityValue(selectedAccessibilityValue)
        .accessibilityHint("Swipe up or down to inspect an active day.")
        .accessibilityAdjustableAction { direction in
            adjustSelection(direction)
        }
    }

    private var selectedCell: ActivityDayCell? {
        guard let selectedDay else { return nil }
        return grid.weeks.flatMap { $0 }.first { $0.date == selectedDay && !$0.isFuture }
    }

    private var activeDays: [ActivityDayCell] {
        grid.weeks.flatMap { $0 }.filter { !$0.isFuture && $0.runCount > 0 }
    }

    private var selectedAccessibilityValue: String {
        guard let selected = selectedCell else { return summary }
        let details = dayRows(selected).map { "\($0.label) \($0.value)" }.joined(separator: ", ")
        return "\(selected.date.formatted(date: .abbreviated, time: .omitted)). \(details)"
    }

    private func dayButton(_ day: ActivityDayCell) -> some View {
        let selected = selectedDay == day.date && !day.isFuture
        return Button {
            guard !day.isFuture else { return }
            selectedDay = selected ? nil : day.date
        } label: {
            dayCell(day, selected: selected)
        }
        .buttonStyle(.plain)
        .disabled(day.isFuture)
        .accessibilityHidden(true)
    }

    private func dayRows(_ day: ActivityDayCell) -> [ChartDetailRow] {
        [
            ChartDetailRow(label: "Distance", value: day.distanceMeters > 0 ? day.distanceMeters.formattedDistance : "0 m"),
            ChartDetailRow(label: "Time", value: chartClock(day.duration)),
            ChartDetailRow(label: "Runs", value: "\(day.runCount)")
        ]
    }

    private func adjustSelection(_ direction: AccessibilityAdjustmentDirection) {
        let days = activeDays
        guard !days.isEmpty else { return }
        let current = days.firstIndex { $0.date == selectedDay }
        let next: Int
        switch direction {
        case .increment:
            next = min(days.count - 1, (current ?? -1) + 1)
        case .decrement:
            next = max(0, (current ?? days.count) - 1)
        @unknown default:
            return
        }
        selectedDay = days[next].date
    }

    private var summary: String {
        let days = grid.activeDays == 1 ? "1 active day" : "\(grid.activeDays) active days"
        let runs = grid.runCount == 1 ? "1 run" : "\(grid.runCount) runs"
        return "\(days), \(runs), \(grid.distanceMeters.formattedDistance)"
    }

    private var weekdayLabels: some View {
        VStack(spacing: cellGap) {
            Color.clear.frame(width: 28, height: 14)
            ForEach(grid.rowLabels.indices, id: \.self) { index in
                Text(grid.rowLabels[index] ?? "")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(LatchColor.muted)
                    .frame(width: 28, height: cellSize, alignment: .trailing)
            }
        }
    }

    private var monthLabels: some View {
        HStack(spacing: cellGap) {
            ForEach(grid.weeks.indices, id: \.self) { column in
                Color.clear
                    .frame(width: cellSize, height: 14)
                    .overlay(alignment: .leading) {
                        if let title = grid.monthLabels.first(where: { $0.column == column })?.title {
                            Text(title)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(LatchColor.muted)
                                .fixedSize()
                        }
                    }
            }
        }
    }

    private func dayCell(_ day: ActivityDayCell, selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(activityColor(day.level, future: day.isFuture))
            .frame(width: cellSize, height: cellSize)
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(LatchColor.ink, lineWidth: 1.5)
                }
            }
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(LatchColor.muted)
            ForEach(ActivityLevel.allCases, id: \.rawValue) { level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(activityColor(level, future: false))
                    .frame(width: cellSize, height: cellSize)
            }
            Text("More")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(LatchColor.muted)
            Spacer(minLength: 0)
        }
    }

    private func activityColor(_ level: ActivityLevel, future: Bool) -> Color {
        if future {
            return LatchColor.chip.opacity(0.35)
        }
        switch level {
        case .none:
            return LatchColor.chip
        case .low:
            return LatchColor.accentSoft
        case .moderate:
            return LatchColor.accent.opacity(0.5)
        case .high:
            return LatchColor.accent.opacity(0.78)
        case .peak:
            return LatchColor.accent
        }
    }
}

private struct TrendPoint {
    let x: CGFloat
    let y: CGFloat
    let value: Double
    let spoken: String
}

private struct TrendLayout {
    let points: [TrendPoint?]
    let segments: [[CGPoint]]
    let bottom: CGFloat
    let barWidth: CGFloat
    let width: CGFloat
    let peak: (point: CGPoint, spoken: String)?

    init(samples: [TrendChartSample], size: CGSize) {
        let topInset: CGFloat = 28
        let bottom = max(topInset + 1, size.height - 2)
        let count = max(samples.count, 1)
        let step = size.width / CGFloat(count)
        let peakValue = samples.compactMap(\.value).max() ?? 0
        let plotHeight = bottom - topInset
        var built: [TrendPoint?] = []
        for (index, sample) in samples.enumerated() {
            guard let value = sample.value else {
                built.append(nil)
                continue
            }
            let y = peakValue > 0 ? topInset + plotHeight * (1 - value / peakValue) : bottom
            built.append(TrendPoint(
                x: step * (CGFloat(index) + 0.5),
                y: y,
                value: value,
                spoken: sample.spoken
            ))
        }
        self.points = built
        self.bottom = bottom
        self.barWidth = max(4, step * 0.58)
        self.width = size.width
        self.segments = TrendLayout.segments(from: built)
        if peakValue > 0, let peak = built.compactMap({ $0 }).last(where: { $0.value == peakValue }) {
            self.peak = (CGPoint(x: peak.x, y: peak.y), peak.spoken)
        } else {
            self.peak = nil
        }
    }

    func calloutX(for point: CGPoint) -> CGFloat {
        let half: CGFloat = 36
        return min(max(point.x, half), max(half, width - half))
    }

    private static func segments(from points: [TrendPoint?]) -> [[CGPoint]] {
        var segments: [[CGPoint]] = []
        var current: [CGPoint] = []
        for point in points {
            if let point {
                current.append(CGPoint(x: point.x, y: point.y))
            } else if !current.isEmpty {
                segments.append(current)
                current = []
            }
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }
}

private struct TrendFill: Shape {
    var segments: [[CGPoint]]
    var bottom: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for segment in segments where segment.count > 1 {
            path.addPath(TrendCurve.path(through: segment))
            path.addLine(to: CGPoint(x: segment[segment.count - 1].x, y: bottom))
            path.addLine(to: CGPoint(x: segment[0].x, y: bottom))
            path.closeSubpath()
        }
        return path
    }
}

private struct TrendStroke: Shape {
    var segments: [[CGPoint]]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for segment in segments where segment.count > 1 {
            path.addPath(TrendCurve.path(through: segment))
        }
        return path
    }
}

private func chartClock(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    if total >= 3_600 {
        return String(format: "%d:%02d:%02d", total / 3_600, total % 3_600 / 60, total % 60)
    }
    return String(format: "%d:%02d", total / 60, total % 60)
}

private enum TrendCurve {
    static func path(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }
        for index in 0..<(points.count - 1) {
            let previous = points[max(0, index - 1)]
            let start = points[index]
            let end = points[index + 1]
            let next = points[min(points.count - 1, index + 2)]
            let control1 = CGPoint(
                x: start.x + (end.x - previous.x) / 6,
                y: start.y + (end.y - previous.y) / 6
            )
            let control2 = CGPoint(
                x: end.x - (next.x - start.x) / 6,
                y: end.y - (next.y - start.y) / 6
            )
            path.addCurve(to: end, control1: control1, control2: control2)
        }
        return path
    }
}
