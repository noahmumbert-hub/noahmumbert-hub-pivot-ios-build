import SwiftUI
import Charts

// MARK: - HHN event-night scope and independent preferences

enum HorrorNightPhase: Equatable {
    case hidden, preview, live
}

enum HorrorHouseSort: String, CaseIterable, Identifiable {
    case shortest = "Shortest wait"
    case name = "Name"
    var id: String { rawValue }
}

enum HorrorNightPreferences {
    // House identifiers are strings and never enter the ride-favorite store.
    static let favoritesKey = "pivot.hhn.favorites.v1.65"
    static let sortKey = "pivot.hhn.sort.v1.65"
    static func doneKey(eventDate: String) -> String { "pivot.hhn.done.v1.65.\(eventDate)" }

    static func ids(from json: String) -> Set<String> {
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(values.filter { !$0.isEmpty })
    }

    static func toggling(_ id: String, in json: String) -> String {
        var values = ids(from: json)
        if values.contains(id) { values.remove(id) } else { values.insert(id) }
        guard let data = try? JSONEncoder().encode(values.sorted()),
              let encoded = String(data: data, encoding: .utf8) else { return json }
        return encoded
    }
}

enum HorrorNightPresentation {
    static let timeZone = TimeZone(identifier: "America/New_York")!

    static func phase(for event: HorrorNightSnapshot, at now: Date) -> HorrorNightPhase {
        let night = event.night
        guard isFresh(event.scheduleCheckedAt, now: now, maximumAge: 36 * 60 * 60),
              night.closingTime > night.openingTime,
              night.closingTime > night.modeStartsAt,
              night.closingTime.timeIntervalSince(night.modeStartsAt) <= 18 * 60 * 60,
              now < night.closingTime else { return .hidden }
        if now >= night.modeStartsAt { return .live }
        // Today's preview only. The previous event remains scoped to its API
        // date after midnight until its actual closing instant, not midnight.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now) == night.date ? .preview : .hidden
    }

    static func isFresh(_ date: Date, now: Date, maximumAge: TimeInterval) -> Bool {
        let age = now.timeIntervalSince(date)
        return age.isFinite && age >= -120 && age < maximumAge
    }

    static func liveWait(for house: HorrorHouse, event: HorrorNightSnapshot, now: Date, refreshFailed: Bool) -> Int? {
        guard !refreshFailed, phase(for: event, at: now) == .live, now >= event.night.openingTime,
              isFresh(event.fetchedAt, now: now, maximumAge: 15 * 60),
              isFresh(house.sourceUpdatedAt, now: now, maximumAge: 15 * 60),
              house.status == "OPEN", let wait = house.waitTime, wait >= 0 else { return nil }
        return wait
    }

    static func sortedHouses(_ event: HorrorNightSnapshot, sort: HorrorHouseSort, now: Date, refreshFailed: Bool) -> [HorrorHouse] {
        var seen = Set<String>()
        let houses = event.houses.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
        return houses.sorted { left, right in
            if sort == .shortest {
                let a = liveWait(for: left, event: event, now: now, refreshFailed: refreshFailed)
                let b = liveWait(for: right, event: event, now: now, refreshFailed: refreshFailed)
                switch (a, b) {
                case let (.some(a), .some(b)) where a != b: return a < b
                case (.some(_), .none): return true
                case (.none, .some(_)): return false
                default: break
                }
            }
            let comparison = left.name.localizedStandardCompare(right.name)
            return comparison == .orderedSame ? left.id < right.id : comparison == .orderedAscending
        }
    }
}

/// Use only for USF snapshots. Pre-event content starts collapsed so regular
/// wait times remain the main Waits surface. No route or walking claims.
struct NativeHorrorNightPanel: View {
    let event: HorrorNightSnapshot
    var showHouses: Bool = true
    var refreshFailed: Bool = false
    @State private var previewExpanded = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let phase = HorrorNightPresentation.phase(for: event, at: context.date)
            if phase != .hidden {
                VStack(alignment: .leading, spacing: 14) {
                    if phase == .preview {
                        DisclosureGroup(isExpanded: $previewExpanded) {
                            VStack(alignment: .leading, spacing: 14) {
                                eventDescription
                                if showHouses { checklist(now: context.date) }
                            }.padding(.top, 10)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Halloween Horror Nights").font(.headline)
                                Text("Tonight preview · opens \(clock(event.night.openingTime))")
                                    .font(.caption).foregroundStyle(Color.pivotMuted)
                            }
                        }
                        .tint(.orange)
                        .pivotCard(padding: 16)
                        .accessibilityIdentifier("hhn-tonight-preview")
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Halloween Horror Nights").font(.title3.bold())
                            eventDescription
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                        if showHouses { checklist(now: context.date) }
                    }
                }
                .foregroundStyle(.white)
            }
        }
        .onChange(of: event.night.date) { _, _ in previewExpanded = false }
    }

    private var eventDescription: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Event night \(event.night.date) · \(clock(event.night.openingTime))–\(clock(event.night.closingTime))")
                .font(.subheadline)
            Text("Separate event ticket required · checklist stays on this event night after midnight")
                .font(.footnote).foregroundStyle(Color.pivotMuted)
        }
    }

    private func checklist(now: Date) -> some View {
        NativeHorrorNightChecklist(event: event, now: now, refreshFailed: refreshFailed)
            .id(event.night.date)
    }

    private func clock(_ date: Date) -> String {
        NativeExtrasFormatting.clock(date, timeZone: HorrorNightPresentation.timeZone)
    }
}

private struct NativeHorrorNightChecklist: View {
    let event: HorrorNightSnapshot
    let now: Date
    let refreshFailed: Bool
    @AppStorage(HorrorNightPreferences.favoritesKey) private var favoritesJSON = "[]"
    @AppStorage(HorrorNightPreferences.sortKey) private var sortValue = HorrorHouseSort.shortest.rawValue
    @AppStorage private var doneJSON: String

    init(event: HorrorNightSnapshot, now: Date, refreshFailed: Bool) {
        self.event = event
        self.now = now
        self.refreshFailed = refreshFailed
        _doneJSON = AppStorage(wrappedValue: "[]", HorrorNightPreferences.doneKey(eventDate: event.night.date))
    }

    private var favorites: Set<String> { HorrorNightPreferences.ids(from: favoritesJSON) }
    private var done: Set<String> { HorrorNightPreferences.ids(from: doneJSON) }
    private var houses: [HorrorHouse] {
        HorrorNightPresentation.sortedHouses(event, sort: HorrorHouseSort(rawValue: sortValue) ?? .shortest, now: now, refreshFailed: refreshFailed)
    }
    private var remaining: [HorrorHouse] { houses.filter { favorites.contains($0.id) && !done.contains($0.id) } }
    private var isPreview: Bool { now < event.night.openingTime }
    private var feedFresh: Bool { !refreshFailed && HorrorNightPresentation.isFresh(event.fetchedAt, now: now, maximumAge: 15 * 60) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack { Text("Haunted houses").font(.title2.bold()); Spacer(); sortMenu }
                VStack(alignment: .leading) { Text("Haunted houses").font(.title2.bold()); sortMenu }
            }
            if isPreview || !feedFresh {
                Text(isPreview ? "Tonight preview · live waits start with the event" : "House updates unavailable · waits are unknown")
                    .font(.subheadline).foregroundStyle(Color.pivotMuted)
            }
            ForEach(houses) { house in houseRow(house) }
            if houses.isEmpty {
                Text("House listings are unavailable from the live feed. PIVOT will retry automatically.")
                    .font(.subheadline).foregroundStyle(Color.pivotMuted)
            }
            DisclosureGroup("Remaining favorite houses · \(remaining.count)") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(remaining) { house in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(house.name).font(.subheadline.weight(.semibold))
                                Text(wait(for: house).map { "\($0) min" } ?? "Wait unknown")
                                    .font(.caption).foregroundStyle(Color.pivotMuted)
                            }
                            Spacer(minLength: 8)
                            Button("Done") { doneJSON = HorrorNightPreferences.toggling(house.id, in: doneJSON) }
                                .frame(minWidth: 44, minHeight: 44)
                                .accessibilityLabel("Mark \(house.name) done for event night \(event.night.date)")
                        }
                    }
                    if remaining.isEmpty {
                        Text(favorites.isEmpty ? "Favorite houses above to build your checklist." : "No listed favorites remaining. Use Undo on a completed house to bring it back.")
                            .font(.subheadline)
                    }
                    let missing = favorites.subtracting(Set(houses.map(\.id)))
                    if !missing.isEmpty {
                        Text("\(missing.count) saved favorite house(s) are absent from this feed. Their preferences are kept.")
                            .font(.caption).foregroundStyle(Color.pivotMuted)
                    }
                    Text("Order follows your selected sort. This is a checklist, not a walking-optimized route; verified house coordinates are unavailable.")
                        .font(.caption).foregroundStyle(Color.pivotMuted)
                }.padding(.top, 10)
            }
            .tint(.orange)
            .pivotCard(padding: 16)
            Text("House waits by ThemeParks.wiki · missing or stale waits stay unknown")
                .font(.footnote).foregroundStyle(Color.pivotMuted)
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort houses", selection: $sortValue) {
                ForEach(HorrorHouseSort.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
        } label: {
            Label(HorrorHouseSort(rawValue: sortValue)?.rawValue ?? "Shortest wait", systemImage: "arrow.up.arrow.down")
                .font(.subheadline).frame(minHeight: 44)
        }
        .tint(.orange)
        .accessibilityLabel("Sort haunted houses")
    }

    private func houseRow(_ house: HorrorHouse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(house.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(status(for: house)).font(.subheadline).foregroundStyle(Color.pivotMuted)
                }
                Spacer(minLength: 4)
                if let wait = wait(for: house) {
                    VStack(spacing: 2) {
                        Text("\(wait)").font(.title2.bold()).monospacedDigit()
                        Text("min").font(.caption)
                    }.accessibilityElement(children: .ignore).accessibilityLabel("\(wait) minute wait")
                } else {
                    Text("Wait unknown").font(.caption).foregroundStyle(Color.pivotMuted)
                        .frame(maxWidth: 80).multilineTextAlignment(.trailing)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { favoriteButton(house); doneButton(house); Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: 4) { favoriteButton(house); doneButton(house) }
            }
        }
        .pivotCard(padding: 16)
    }

    private func favoriteButton(_ house: HorrorHouse) -> some View {
        Button { favoritesJSON = HorrorNightPreferences.toggling(house.id, in: favoritesJSON) } label: {
            Label("Favorite", systemImage: favorites.contains(house.id) ? "star.fill" : "star")
                .font(.subheadline).frame(minHeight: 44)
        }
        .buttonStyle(.plain).foregroundStyle(.orange)
        .accessibilityLabel("\(favorites.contains(house.id) ? "Remove" : "Add") \(house.name) \(favorites.contains(house.id) ? "from" : "to") HHN favorites")
        .accessibilityValue(favorites.contains(house.id) ? "Favorited" : "Not favorited")
    }

    private func doneButton(_ house: HorrorHouse) -> some View {
        Button { doneJSON = HorrorNightPreferences.toggling(house.id, in: doneJSON) } label: {
            Label(done.contains(house.id) ? "Done · Undo" : "Mark done", systemImage: done.contains(house.id) ? "checkmark.circle.fill" : "circle")
                .font(.subheadline).frame(minHeight: 44)
        }
        .buttonStyle(.plain).foregroundStyle(done.contains(house.id) ? Color.pivotMint : Color.pivotMuted)
        .accessibilityLabel("\(done.contains(house.id) ? "Undo completion of" : "Mark done") \(house.name) for event night \(event.night.date)")
        .accessibilityValue(done.contains(house.id) ? "Done" : "Not done")
    }

    private func wait(for house: HorrorHouse) -> Int? {
        HorrorNightPresentation.liveWait(for: house, event: event, now: now, refreshFailed: refreshFailed)
    }

    private func status(for house: HorrorHouse) -> String {
        if isPreview { return "Tonight preview" }
        guard feedFresh, HorrorNightPresentation.isFresh(house.sourceUpdatedAt, now: now, maximumAge: 15 * 60) else { return "Updating status" }
        switch house.status {
        case "OPEN": return "Open"
        case "DOWN": return "Temporarily down"
        case "CLOSED": return "Closed"
        case "UPCOMING": return "Opens with event"
        default: return "Status unavailable"
        }
    }
}

// MARK: - Actual timestamped wait observations

enum WaitHistoryPresentation {
    static let window: TimeInterval = 6 * 60 * 60
    static let maximumSamples = 12

    static func samples(_ source: [WaitHistorySample]?, at now: Date) -> [WaitHistorySample] {
        let start = now.addingTimeInterval(-window)
        var seen = Set<Date>()
        let valid = (source ?? []).filter {
            $0.waitTime.isFinite && $0.waitTime >= 0 &&
            $0.observedAt >= start && $0.observedAt <= now &&
            seen.insert($0.observedAt).inserted
        }.sorted { $0.observedAt < $1.observedAt }
        return Array(valid.suffix(maximumSamples))
    }
}

/// Insert as a disclosure below a row's main button, and as its own detail card.
/// Dots use real observation time on a continuous six-hour axis; no connecting
/// line, interpolated point, trend timestamp, or prediction is generated.
struct NativeWaitHistoryView: View {
    @Environment(\.pivotAccent) private var accent
    let ride: LiveRide
    let timeZone: TimeZone
    var initiallyExpanded: Bool = false
    @State private var expanded: Bool

    init(ride: LiveRide, timeZone: TimeZone, initiallyExpanded: Bool = false) {
        self.ride = ride
        self.timeZone = timeZone
        self.initiallyExpanded = initiallyExpanded
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let samples = WaitHistoryPresentation.samples(ride.waitHistory, at: context.date)
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 12) {
                    if samples.isEmpty {
                        Text("No recent observations yet. History appears after fresh park snapshots are collected.")
                            .font(.subheadline).foregroundStyle(Color.pivotMuted)
                    } else {
                        chart(samples: samples, now: context.date)
                        Text("Up to 12 PIVOT observations in the last 6 hours. Dots preserve collection gaps; these are posted waits, not predictions.")
                            .font(.caption).foregroundStyle(Color.pivotMuted)
                        DisclosureGroup("Sample times") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(samples) { sample in
                                    Text("\(NativeExtrasFormatting.timestamp(sample.observedAt, timeZone: timeZone)) · \(NativeExtrasFormatting.number(sample.waitTime)) min")
                                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                        }.font(.caption)
                    }
                }.padding(.top, 12)
            } label: {
                Text("Recent observed waits · \(samples.count) samples").font(.caption.weight(.medium))
            }
            .tint(accent)
        }
        .accessibilityIdentifier("wait-history-\(ride.id)")
    }

    private func chart(samples: [WaitHistorySample], now: Date) -> some View {
        let start = now.addingTimeInterval(-WaitHistoryPresentation.window)
        let maximum = max(10, samples.map(\.waitTime).max() ?? 10)
        return Chart(samples) { sample in
            PointMark(x: .value("Observed at", sample.observedAt), y: .value("Posted wait", sample.waitTime))
                .foregroundStyle(accent).symbolSize(36)
                .accessibilityLabel(NativeExtrasFormatting.timestamp(sample.observedAt, timeZone: timeZone))
                .accessibilityValue("\(NativeExtrasFormatting.number(sample.waitTime)) minutes")
        }
        .chartXScale(domain: start...now)
        .chartYScale(domain: 0...(maximum * 1.1))
        .chartXAxis {
            AxisMarks(values: [start, now]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(NativeExtrasFormatting.clock(date, timeZone: timeZone))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.0, maximum]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let minutes = value.as(Double.self) { Text("\(NativeExtrasFormatting.number(minutes)) m") }
                }
            }
        }
        .frame(height: 145)
        .accessibilityLabel("Observed posted wait samples for \(ride.name), last six hours. Gaps have no observations.")
    }
}

// MARK: - Server-controlled, uncalibrated storm-movement experiment

struct LightningDeparturePresentation {
    let range: ClosedRange<Date>?
    let headline: String
    let detail: String

    init(estimate: LightningDepartureEstimate, now: Date, refreshFailed: Bool = false) {
        range = Self.validRange(estimate, now: now, refreshFailed: refreshFailed)
        if estimate.status == "DISABLED" {
            headline = "Storm movement experiment is off"
            detail = estimate.label
        } else if range != nil {
            headline = "Storm movement outlook"
            detail = estimate.label
        } else {
            headline = "No dependable movement estimate"
            if refreshFailed { detail = "New weather data could not be fetched; the earlier movement window is withheld." }
            else if estimate.status == "EXPERIMENTAL_RANGE" { detail = "The earlier movement evidence is expired, incomplete, or not current enough to show a window." }
            else { detail = estimate.label }
        }
    }

    static func validRange(_ value: LightningDepartureEstimate, now: Date, refreshFailed: Bool) -> ClosedRange<Date>? {
        guard !refreshFailed,
              value.status == "EXPERIMENTAL_RANGE", value.reason == "PATTERN_TRANSLATING",
              value.algorithmVersion == "PIVOT_SPATIAL_DEPARTURE_EXPERIMENT_V1",
              value.calibration == "UNCALIBRATED", value.trackedRadiusMiles == 5,
              value.issuedAt <= now.addingTimeInterval(120),
              let radar = value.radarObservedAt, radar <= now,
              now.timeIntervalSince(radar) <= 12 * 60,
              let lightning = value.lightningIntervalEndAt,
              lightning <= now.addingTimeInterval(120), now.timeIntervalSince(lightning) <= 25 * 60,
              value.frameCount >= 3, value.frameTimes.count == value.frameCount, value.motion != nil,
              Set(value.frameTimes).count == value.frameTimes.count,
              value.frameTimes.allSatisfy({ $0 <= now && now.timeIntervalSince($0) <= 30 * 60 }),
              value.diagnostics.unknownRadarCells.count == value.frameCount,
              value.diagnostics.unknownRadarCells.allSatisfy({ $0 == 0 }),
              value.diagnostics.unknownLightningCells == 0,
              let start = value.earliestDepartureAt, let end = value.latestDepartureAt,
              start < end, end > now, start >= radar,
              end.timeIntervalSince(radar) <= 60 * 60 else { return nil }
        return start...end
    }
}

/// Add only when weather.lightningDeparture is present. This does not turn on
/// the server experiment, synthesize estimates, or alter operational guidance.
struct NativeLightningDepartureCard: View {
    let estimate: LightningDepartureEstimate
    let timeZone: TimeZone
    var refreshFailed: Bool = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let presentation = LightningDeparturePresentation(estimate: estimate, now: context.date, refreshFailed: refreshFailed)
            VStack(alignment: .leading, spacing: 12) {
                Text("EXPERIMENTAL · UNCALIBRATED").font(.caption.weight(.bold)).foregroundStyle(.orange)
                Text(presentation.headline).font(.title3.bold())
                Text(presentation.detail).font(.subheadline)
                if let range = presentation.range {
                    Text("\(clock(range.lowerBound))–\(clock(range.upperBound))")
                        .font(.title2.weight(.semibold)).monospacedDigit()
                        .accessibilityLabel("Uncalibrated storm footprint departure window, \(clock(range.lowerBound)) to \(clock(range.upperBound))")
                }
                Text("Estimates when a lightning-associated radar footprint may move beyond five miles. New lightning can develop. This is not a final-strike prediction, a safety all-clear, or a ride-reopening signal.")
                    .font(.subheadline).foregroundStyle(Color.pivotMuted)
                DisclosureGroup("Evidence behind this estimate") {
                    VStack(alignment: .leading, spacing: 10) {
                        evidence("Radar observations", "\(estimate.frameCount) distinct frames · latest \(timestamp(estimate.radarObservedAt))")
                        evidence("Lightning density", "15-minute interval ending \(timestamp(estimate.lightningIntervalEndAt))")
                        evidence("Observed area", estimate.watchRadiusMiles.map { "\(NativeExtrasFormatting.number($0))-mile radius around the park" } ?? "Not available")
                        evidence("Pattern motion", estimate.motion.map { "\(NativeExtrasFormatting.number($0.speedMph)) mph toward \(NativeExtrasFormatting.number($0.bearingDegrees))° · \($0.agreement)" } ?? "Not established")
                        evidence("Footprint sizes", estimate.diagnostics.footprintPixelCounts.isEmpty ? "Not available" : estimate.diagnostics.footprintPixelCounts.map(String.init).joined(separator: " → ") + " rendered cells")
                        evidence("Radar source", estimate.source.radar)
                        evidence("Lightning source", estimate.source.lightning)
                        evidence("Issued", "\(timestamp(estimate.issuedAt)) · \(estimate.algorithmVersion)")
                        Text("Tracking diagnostics are not calibrated probabilities.")
                        Text(estimate.limitations)
                    }.font(.caption).foregroundStyle(Color.pivotMuted).padding(.top, 10)
                }
                .font(.subheadline).tint(.orange)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pivotCard()
            .accessibilityIdentifier("experimental-storm-departure")
        }
    }

    private func evidence(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).fontWeight(.semibold).foregroundStyle(.white)
            Text(value).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func clock(_ date: Date) -> String { NativeExtrasFormatting.clock(date, timeZone: timeZone) }
    private func timestamp(_ date: Date?) -> String {
        date.map { NativeExtrasFormatting.timestamp($0, timeZone: timeZone) } ?? "Not available"
    }
}

private enum NativeExtrasFormatting {
    static func clock(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, h:mm a z"
        return formatter.string(from: date)
    }
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
