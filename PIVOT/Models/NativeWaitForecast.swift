import Foundation

/// Bounded local learning from real observations. Polls in one quarter-hour have
/// one vote; each operating day has one vote in an hourly forecast.
struct WaitLearningBin: Codable, Equatable, Sendable {
    let parkID: Int
    let rideID: Int
    let day: String
    let weekday: Int
    let hour: Int
    var quarters: [Int: Double]
    var lastSeen: Date
    var mean: Double { quarters.values.reduce(0, +) / Double(max(1, quarters.count)) }
}

struct WaitForecastPoint: Identifiable, Equatable, Sendable {
    let start: Date
    let end: Date
    let minutes: Int
    let lower: Int
    let upper: Int
    let days: Int
    let sameWeekday: Bool
    let crowdAdjusted: Bool
    var id: Date { start }
}

struct ParkCrowdEstimate: Equatable, Sendable {
    let typicalWait: Int
    let rideCount: Int
    let hourCount: Int
    let days: Int
    let basis: String
    /// Queue-pressure index, not attendance or percent capacity.
    var score: Int { max(1, min(10, Int(ceil(Double(typicalWait) / 10)))) }
    var label: String {
        switch typicalWait {
        case ..<15: "Quiet"
        case 15..<30: "Moderate"
        case 30..<60: "Busy"
        default: "Very busy"
        }
    }
}

struct WaitLearningHistory: Codable, Equatable, Sendable {
    static let storageKey = "pivot.waitLearning.v1"
    static let retention: TimeInterval = 56 * 86_400
    static let maximumBins = 40_000
    var bins: [String: WaitLearningBin] = [:]
    var eligibleCounts: [String: Int] = [:]

    static func calendar(for park: FloridaPark) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = park.timeZone
        return calendar
    }

    static func dayKey(_ date: Date, park: FloridaPark) -> String {
        let parts = calendar(for: park).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func matchingDay(_ date: Date, from sourcePark: FloridaPark, to park: FloridaPark) -> Date {
        var parts = calendar(for: sourcePark).dateComponents([.year, .month, .day], from: date)
        parts.hour = 12
        return calendar(for: park).date(from: parts) ?? date
    }

    static func fresh(_ date: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(date)
        return age.isFinite && age >= -120 && age < 900
    }

    static func validWait(_ wait: Double) -> Bool { wait.isFinite && wait >= 0 && wait <= 1440 }

    static func usable(_ snapshot: LiveParkSnapshot?, park: FloridaPark, failed: Bool, now: Date) -> Bool {
        guard let snapshot, snapshot.parkId == park.rawValue, !failed else { return false }
        return snapshot.parkActive && DashboardFeedHealth.presentation(parkSelected: true,
            snapshot: snapshot, isLoading: false, refreshFailed: failed, at: now).isLive
    }

    static func interval(_ hours: ParkHoursSnapshot?, park: FloridaPark, now: Date) -> ParkHoursPeriod? {
        guard let hours, hours.parkId == park.rawValue, !hours.stale,
              hours.fetchedAt.timeIntervalSince1970.isFinite,
              now.timeIntervalSince(hours.fetchedAt) >= -120, now.timeIntervalSince(hours.fetchedAt) < 36 * 3600,
              hours.sourceUpdatedAt.map({ $0.timeIntervalSince1970.isFinite && $0 <= now.addingTimeInterval(120) }) != false,
              let period = hours.regular,
              period.openingTime.timeIntervalSince1970.isFinite,
              period.closingTime.timeIntervalSince1970.isFinite,
              period.closingTime > period.openingTime,
              period.closingTime.timeIntervalSince(period.openingTime) <= 24 * 3600,
              period.closingTime > now else { return nil }
        return period
    }

    static func currentWaits(_ snapshot: LiveParkSnapshot, now: Date = Date()) -> [Int: Double] {
        var waits: [Int: Double] = [:]
        let duplicate = Set(Dictionary(grouping: snapshot.rides, by: \.id).filter { $0.value.count > 1 }.keys)
        for ride in snapshot.rides where ride.radarEligible {
            guard ride.status == .open, ride.isOpen, let wait = ride.waitTime,
                  validWait(Double(wait)), let version = ride.lastUpdated,
                  version.timeIntervalSince1970.isFinite,
                  version <= min(snapshot.fetchedAt, now).addingTimeInterval(120),
                  !duplicate.contains(ride.id) else { continue }
            waits[ride.id] = Double(wait)
        }
        for id in duplicate { waits.removeValue(forKey: id) }
        return waits
    }

    /// At least five rides and 35% of eligible rides must report. Closed and
    /// missing rides never contribute zero or imply that a park is quiet.
    static func hasCoverage(_ snapshot: LiveParkSnapshot, count: Int) -> Bool {
        let total = Set(snapshot.rides.filter(\.radarEligible).map(\.id)).count
        return count >= max(5, Int(ceil(Double(total) * 0.35)))
    }

    @discardableResult
    mutating func record(_ snapshot: LiveParkSnapshot, now: Date) -> Bool {
        guard let park = FloridaPark(rawValue: snapshot.parkId),
              Self.usable(snapshot, park: park, failed: false, now: now),
              let period = Self.interval(snapshot.parkHours, park: park, now: now),
              snapshot.fetchedAt >= period.openingTime, snapshot.fetchedAt < period.closingTime else { return false }
        let calendar = Self.calendar(for: park)
        let day = Self.dayKey(period.openingTime, park: park)
        let weekday = calendar.component(.weekday, from: period.openingTime)
        var changed = false
        func key(_ ride: Int, _ hour: Int) -> String { "\(park.rawValue):\(ride):\(day):\(hour)" }
        let current = Self.currentWaits(snapshot, now: now)
        let totalEligible = Set(snapshot.rides.filter(\.radarEligible).map(\.id)).count
        let duplicateIDs = Set(Dictionary(grouping: snapshot.rides, by: \.id).filter { $0.value.count > 1 }.keys)
        for ride in snapshot.rides where ride.radarEligible && !duplicateIDs.contains(ride.id) {
            var samples = ride.waitHistory ?? []
            if let wait = current[ride.id] { samples.append(WaitHistorySample(observedAt: snapshot.fetchedAt, waitTime: wait)) }
            // Conflicting observations at one timestamp are withheld completely.
            let grouped = Dictionary(grouping: samples, by: \.observedAt)
            for (time, values) in grouped.sorted(by: { $0.key < $1.key }) {
                guard time.timeIntervalSince1970.isFinite, time <= now,
                      time <= snapshot.fetchedAt, time >= period.openingTime,
                      time < period.closingTime, now.timeIntervalSince(time) < 6 * 3600,
                      let wait = values.first?.waitTime, Self.validWait(wait),
                      values.allSatisfy({ $0.waitTime == wait }) else { continue }
                let hour = calendar.component(.hour, from: time)
                let coverageKey = "\(park.rawValue):\(day):\(hour)"
                let coverage = max(eligibleCounts[coverageKey] ?? 0, totalEligible)
                if eligibleCounts[coverageKey] != coverage { eligibleCounts[coverageKey] = coverage; changed = true }
                let quarter = calendar.component(.minute, from: time) / 15
                let id = key(ride.id, hour)
                var bin = bins[id] ?? WaitLearningBin(parkID: park.rawValue, rideID: ride.id,
                    day: day, weekday: weekday, hour: hour, quarters: [:], lastSeen: time)
                guard bin.quarters[quarter] == nil else { continue }
                bin.quarters[quarter] = wait
                bin.lastSeen = max(bin.lastSeen, time)
                bins[id] = bin
                changed = true
            }
        }
        if changed { prune(now: now) }
        return changed
    }

    mutating func prune(now: Date) {
        bins = bins.filter { _, bin in
            FloridaPark(rawValue: bin.parkID) != nil && bin.rideID >= 0 && (0...23).contains(bin.hour)
            && (1...7).contains(bin.weekday) && bin.day.count == 10 && !bin.quarters.isEmpty
            && bin.quarters.count <= 4 && bin.quarters.allSatisfy { (0...3).contains($0.key) && Self.validWait($0.value) }
            && bin.lastSeen <= now && now.timeIntervalSince(bin.lastSeen) < Self.retention
        }
        let activeCoverage = Set(bins.values.map { "\($0.parkID):\($0.day):\($0.hour)" })
        eligibleCounts = eligibleCounts.filter { activeCoverage.contains($0.key) && $0.value > 0 }
        if bins.count > Self.maximumBins {
            bins = Dictionary(uniqueKeysWithValues: bins.sorted { $0.value.lastSeen > $1.value.lastSeen }.prefix(Self.maximumBins).map { ($0.key, $0.value) })
        }
    }

    static func load(from defaults: UserDefaults, now: Date = Date()) -> Self {
        guard let data = defaults.data(forKey: storageKey), data.count <= 16_000_000,
              var result = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        result.prune(now: now)
        return result
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }

    static func quantile(_ values: [Double], _ fraction: Double = 0.5) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let position = Double(sorted.count - 1) * fraction
        let lower = Int(floor(position)), upper = Int(ceil(position))
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
    }

    private func comparable(park: FloridaPark, rideID: Int, hour: Int, day: Date, now: Date) -> [WaitLearningBin] {
        let dayKey = Self.dayKey(day, park: park)
        let weekday = Self.calendar(for: park).component(.weekday, from: day)
        let prior = bins.values.filter { $0.parkID == park.rawValue && $0.rideID == rideID && $0.hour == hour
            && $0.day < dayKey && $0.lastSeen <= now && now.timeIntervalSince($0.lastSeen) < Self.retention }
        let same = prior.filter { $0.weekday == weekday }
        return Set(same.map(\.day)).count >= 3 ? same : prior
    }

    func liveCrowd(park: FloridaPark, snapshot: LiveParkSnapshot?, failed: Bool, now: Date) -> ParkCrowdEstimate? {
        guard Self.usable(snapshot, park: park, failed: failed, now: now), let snapshot else { return nil }
        let waits = Self.currentWaits(snapshot, now: now)
        guard Self.hasCoverage(snapshot, count: waits.count) else { return nil }
        return ParkCrowdEstimate(typicalWait: Int(Self.quantile(Array(waits.values)).rounded()),
            rideCount: waits.count, hourCount: 1, days: 1, basis: "Live · posted waits")
    }

    /// Daily estimates give rides and hours equal weight. A future day uses
    /// previous days only, preferring the same weekday when three are present.
    func dailyCrowd(park: FloridaPark, date: Date, now: Date) -> ParkCrowdEstimate? {
        let key = Self.dayKey(date, park: park)
        let records = bins.values.filter { $0.parkID == park.rawValue && $0.lastSeen <= now
            && now.timeIntervalSince($0.lastSeen) < Self.retention }
        let actual = records.filter { $0.day == key }
        func summary(_ dayBins: [WaitLearningBin], basis: String, days: Int) -> ParkCrowdEstimate? {
            let rides = Set(dayBins.map(\.rideID))
            guard rides.count >= 5 else { return nil }
            let hours = Dictionary(grouping: dayBins, by: \.hour).values.compactMap { rows -> Double? in
                let total = rows.map { eligibleCounts["\($0.parkID):\($0.day):\($0.hour)"] ?? 0 }.max() ?? 0
                guard total > 0, Set(rows.map(\.rideID)).count >= max(5, Int(ceil(Double(total) * 0.35))) else { return nil }
                return Self.quantile(rows.map(\.mean))
            }
            guard !hours.isEmpty else { return nil }
            return ParkCrowdEstimate(typicalWait: Int(Self.quantile(hours).rounded()), rideCount: rides.count,
                hourCount: hours.count, days: days, basis: basis)
        }
        if !actual.isEmpty { return summary(actual, basis: "Observed · sampled hours only", days: 1) }
        guard key > Self.dayKey(now, park: park) else { return nil }
        let prior = records.filter { $0.day < key }
        let weekday = Self.calendar(for: park).component(.weekday, from: date)
        let same = prior.filter { $0.weekday == weekday }
        let useSame = Set(same.map(\.day)).count >= 3
        let byDay = Dictionary(grouping: useSame ? same : prior, by: \.day)
        let days = byDay.values.compactMap { summary($0, basis: "", days: 1) }
        guard days.count >= 3 else { return nil }
        return ParkCrowdEstimate(typicalWait: Int(Self.quantile(days.map { Double($0.typicalWait) }).rounded()),
            rideCount: days.map(\.rideCount).min() ?? 0, hourCount: days.map(\.hourCount).min() ?? 0,
            days: days.count, basis: useSame ? "Estimate · same weekday · limited confidence" : "Estimate · recent days · limited confidence")
    }

    func forecast(rideID: Int, park: FloridaPark, hours: ParkHoursSnapshot?, snapshot: LiveParkSnapshot?, failed: Bool, now: Date) -> [WaitForecastPoint] {
        guard let period = Self.interval(hours, park: park, now: now) else { return [] }
        let calendar = Self.calendar(for: park)
        let day = period.openingTime
        let weekday = calendar.component(.weekday, from: day)
        let live = Self.usable(snapshot, park: park, failed: failed, now: now)
        var ratios: [Double] = []
        if live, let snapshot, Self.hasCoverage(snapshot, count: Self.currentWaits(snapshot, now: now).count) {
            let currentHour = calendar.component(.hour, from: now)
            for (id, wait) in Self.currentWaits(snapshot, now: now) {
                let history = comparable(park: park, rideID: id, hour: currentHour, day: day, now: now)
                guard Set(history.map(\.day)).count >= 3 else { continue }
                let normal = Self.quantile(history.map(\.mean))
                if normal >= 5 { ratios.append(wait / normal) }
            }
        }
        let adjusted = ratios.count >= 5
        let factor = adjusted ? max(0.5, min(2, Self.quantile(ratios))) : 1
        var start = max(period.openingTime, now)
        var points: [WaitForecastPoint] = []
        while start < period.closingTime, points.count < 25 {
            let hour = calendar.component(.hour, from: start)
            let next = calendar.dateInterval(of: .hour, for: start)?.end ?? start.addingTimeInterval(3600)
            let end = min(next, period.closingTime)
            let history = comparable(park: park, rideID: rideID, hour: hour, day: day, now: now)
            let count = Set(history.map(\.day)).count
            if count >= 3 {
                let values = history.map { min(1440, $0.mean * factor) }
                let median = Self.quantile(values)
                // Descriptive spread plus 5 minutes, not a calibrated probability interval.
                let low = max(0, Self.quantile(values, 0.2) - 5)
                let high = min(1440, Self.quantile(values, 0.8) + 5)
                points.append(WaitForecastPoint(start: start, end: end,
                    minutes: min(1440, Int((median / 5).rounded()) * 5),
                    lower: Int(floor(low / 5)) * 5, upper: Int(ceil(high / 5)) * 5,
                    days: count, sameWeekday: history.allSatisfy { $0.weekday == weekday }, crowdAdjusted: adjusted))
            }
            guard end > start else { break }
            start = end
        }
        return points
    }
}
