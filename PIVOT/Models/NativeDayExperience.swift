import Foundation
import Combine

/// Visit progress is intentionally separate from permanent ride favorites.
enum NativeRideProgress: String, Codable, Sendable {
    case done, skip
}

enum NativeCommitmentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case show, lunch, manualReturn
    var id: String { rawValue }
    var label: String {
        switch self {
        case .show: return "Show"
        case .lunch: return "Lunch / break"
        case .manualReturn: return "Manual return window"
        }
    }
}

struct NativeDayCommitment: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let kind: NativeCommitmentKind
    let startAt: Date
    let endAt: Date
    let bufferMinutes: Int
    let location: AttractionLocation?
    var note: String? = nil

    var isValid: Bool {
        !id.isEmpty && id.count <= 160 && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && title.count <= 100 && startAt.timeIntervalSince1970.isFinite && endAt.timeIntervalSince1970.isFinite
        && endAt > startAt && endAt.timeIntervalSince(startAt) <= 12 * 3600
        && (0...60).contains(bufferMinutes) && (location == nil || NativeDayPlanning.validLocation(location))
        && (note?.count ?? 0) <= 500
    }

    func overlaps(_ other: NativeDayCommitment) -> Bool {
        startAt < other.endAt && endAt > other.startAt
    }
}

struct NativeDayState: Codable, Equatable, Sendable {
    var progress: [Int: NativeRideProgress] = [:]
    var start: String = "entrance"
    var commitments: [NativeDayCommitment] = []
    var visitStart: Date? = nil
    var visitEnd: Date? = nil

    var isValid: Bool {
        progress.count <= 1000 && progress.keys.allSatisfy { $0 >= 0 }
        && start.count <= 250 && commitments.count <= 30
        && commitments.allSatisfy(\.isValid)
        && Set(commitments.map(\.id)).count == commitments.count
        && !commitments.enumerated().contains { index, item in commitments.dropFirst(index + 1).contains { item.overlaps($0) } }
        && validWindow
    }

    private var validWindow: Bool {
        if visitStart == nil && visitEnd == nil { return true }
        guard let start = visitStart, let end = visitEnd else { return false }
        return start.timeIntervalSince1970.isFinite && end.timeIntervalSince1970.isFinite
            && end > start && end.timeIntervalSince(start) <= 24 * 3600
    }
}

struct NativeDayRouteStop: Codable, Identifiable, Equatable, Sendable {
    let rideID: Int
    let rideName: String
    let land: String
    let sequence: Int
    let arriveAt: Date
    let experienceAt: Date
    let completeAt: Date
    let walkMinutes: Int
    let distanceMiles: Double
    let expectedWaitMinutes: Int
    var id: Int { rideID }

    init(_ stop: DayPlanStop, sequence: Int) {
        rideID = stop.rideID; rideName = stop.rideName; land = stop.land
        self.sequence = sequence; arriveAt = stop.arriveAt; experienceAt = stop.experienceAt
        completeAt = stop.completeAt; walkMinutes = stop.walkMinutes
        distanceMiles = stop.distanceMiles; expectedWaitMinutes = stop.expectedWaitMinutes
    }
}

struct NativeCommitmentStop: Codable, Identifiable, Equatable, Sendable {
    let commitment: NativeDayCommitment
    let leaveBy: Date
    let transferMinutes: Int
    let transferDistanceMiles: Double
    let warnings: [String]
    var id: String { commitment.id }
}

struct NativeDayRoute: Codable, Equatable, Sendable {
    let generatedAt: Date
    let startAt: Date
    let endAt: Date
    let startLabel: String
    let stops: [NativeDayRouteStop]
    let commitments: [NativeCommitmentStop]
    let cutRideIDs: [Int]
    let unavailableRideIDs: [Int]
    let missingRideIDs: [Int]
    let remainingRideCount: Int
    let availableMinutes: Int
    let plannedMinutes: Int
    let walkMinutes: Int
    let distanceMiles: Double

    var isValid: Bool {
        guard generatedAt.timeIntervalSince1970.isFinite, startAt.timeIntervalSince1970.isFinite,
              endAt.timeIntervalSince1970.isFinite, endAt > startAt,
              endAt.timeIntervalSince(startAt) <= 24 * 3600, startLabel.count <= 500,
              stops.count <= 1000, Set(stops.map(\.rideID)).count == stops.count,
              commitments.count <= 30 else { return false }
        let validStops = stops.enumerated().allSatisfy { index, stop in
            stop.rideID >= 0 && stop.sequence == index + 1 && stop.rideName.count <= 500
            && stop.arriveAt.timeIntervalSince1970.isFinite && stop.experienceAt >= stop.arriveAt
            && stop.completeAt >= stop.experienceAt && stop.arriveAt >= startAt && stop.completeAt <= endAt
            && (0...240).contains(stop.expectedWaitMinutes) && stop.walkMinutes >= 0
            && stop.distanceMiles.isFinite && stop.distanceMiles >= 0
        }
        let validCommitments = commitments.allSatisfy {
            $0.commitment.isValid && $0.leaveBy.timeIntervalSince1970.isFinite && $0.transferMinutes >= 0
            && $0.transferDistanceMiles.isFinite && $0.transferDistanceMiles >= 0 && $0.warnings.count <= 3
        }
        let validIDs = [cutRideIDs, unavailableRideIDs, missingRideIDs].allSatisfy {
            $0.count <= 1000 && $0.allSatisfy { $0 >= 0 }
        }
        return validStops && validCommitments && validIDs && (0...1000).contains(remainingRideCount)
            && availableMinutes >= 0 && plannedMinutes >= 0 && walkMinutes >= 0
            && distanceMiles.isFinite && distanceMiles >= 0
    }

    var fitsAll: Bool {
        remainingRideCount > 0 && cutRideIDs.isEmpty && unavailableRideIDs.isEmpty && missingRideIDs.isEmpty
            && commitments.allSatisfy { $0.warnings.isEmpty }
    }
}

enum NativeDayPlanning {
    static func validLocalDay(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }

    static func localDay(park: FloridaPark, at now: Date) -> String {
        ParkHoursSnapshot.localDate(for: park, at: now)
    }

    static func dayKey(park: FloridaPark, at now: Date) -> String {
        "\(park.id):\(localDay(park: park, at: now))"
    }

    static func validLocation(_ value: AttractionLocation?) -> Bool {
        guard let value else { return false }
        return value.latitude.isFinite && value.longitude.isFinite
            && (-90...90).contains(value.latitude) && (-180...180).contains(value.longitude)
    }

    static func entrance(for park: FloridaPark) -> AttractionLocation? {
        ParkEntranceLocations.coordinates[park].map { AttractionLocation(latitude: $0.latitude, longitude: $0.longitude) }
    }

    static func resolveStart(_ value: String, rides: [LiveRide], park: FloridaPark) -> (location: AttractionLocation?, label: String) {
        let eligible = rides.filter { $0.radarEligible && validLocation($0.location) }
        if value.hasPrefix("ride:"), let id = Int(value.dropFirst(5)), let ride = eligible.first(where: { $0.id == id }) {
            return (ride.location, ride.name)
        }
        if value.hasPrefix("land:") {
            let land = String(value.dropFirst(5))
            let points = eligible.filter { $0.land == land }.compactMap(\.location)
            if !points.isEmpty {
                return (AttractionLocation(latitude: points.reduce(0) { $0 + $1.latitude } / Double(points.count),
                                           longitude: points.reduce(0) { $0 + $1.longitude } / Double(points.count)),
                        "\(land) · approximate center")
            }
        }
        return (entrance(for: park), value == "entrance" ? "Park entrance" : "Park entrance · saved start unavailable")
    }

    static func defaultWindow(park: FloridaPark, hours: ParkHoursSnapshot?, at now: Date) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = park.timeZone
        let currentHours = hours?.isCurrent(for: park, at: now) == true ? hours : nil
        let opening = currentHours?.earlyEntry?.openingTime ?? currentHours?.regular?.openingTime
            ?? calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
        let closing = currentHours?.regular?.closingTime
            ?? calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? opening.addingTimeInterval(11 * 3600)
        let rounded = Date(timeIntervalSince1970: ceil(now.timeIntervalSince1970 / 900) * 900)
        let start = rounded >= opening && rounded < closing ? rounded : opening
        return (start, closing > start ? closing : start.addingTimeInterval(3600))
    }

    /// Same segment/reservation policy as day-experience.ts. Never call with an offline pack.
    static func build(rides: [LiveRide], favoriteIDs: Set<Int>, day: NativeDayState,
                      park: FloridaPark, startAt: Date, endAt: Date, now: Date) -> NativeDayRoute {
        // A duplicate/partial feed must not trap Dictionary(uniqueKeysWithValues:) in the base planner.
        var seen: Set<Int> = []
        let rides = rides.filter { seen.insert($0.id).inserted }
        let remaining = favoriteIDs.filter { day.progress[$0] == nil }
        let start = resolveStart(day.start, rides: rides, park: park)
        let effectiveStart = max(startAt, min(now, endAt))
        let base = DayPlanner.build(rides: rides, requestedRideIDs: remaining, startAt: startAt,
                                    endAt: endAt, now: now, startLocation: start.location)
        let commitments = day.commitments.filter(\.isValid)
            .filter { $0.endAt > max(startAt, now) && $0.startAt < endAt }
            .sorted { $0.startAt < $1.startAt }
        var cursor = effectiveStart
        var location = start.location
        var pending = remaining
        var stops: [NativeDayRouteStop] = []
        var fixed: [NativeCommitmentStop] = []
        var totalWalk = 0
        var totalDistance = 0.0

        // Include a final unreserved segment after the last commitment.
        for index in 0...commitments.count {
            let commitment = index < commitments.count ? commitments[index] : nil
            var transferMiles = 0.0
            var transferMinutes = 0
            var leaveBy = endAt
            if let commitment {
                let origins: [AttractionLocation?] = [location] + rides.filter { pending.contains($0.id) }.map(\.location)
                transferMiles = origins.map { origin -> Double in
                    guard validLocation(origin), validLocation(commitment.location),
                          let from = origin, let to = commitment.location else { return 0.75 }
                    return DayPlanner.distanceMiles(from: from, to: to) * 1.35
                }.max() ?? 0.75
                // No optimistic walking cap: distant commitments must remain visibly infeasible.
                transferMinutes = max(1, Int(ceil(transferMiles / 3 * 60)))
                leaveBy = commitment.startAt.addingTimeInterval(-Double(transferMinutes + commitment.bufferMinutes) * 60)
            }
            if leaveBy > cursor && cursor < endAt {
                let segment = DayPlanner.build(rides: rides, requestedRideIDs: pending, startAt: cursor,
                                               endAt: min(leaveBy, endAt), now: cursor, startLocation: location)
                for stop in segment.stops {
                    stops.append(NativeDayRouteStop(stop, sequence: stops.count + 1))
                    pending.remove(stop.rideID)
                }
                totalWalk += segment.totalWalkMinutes
                totalDistance += segment.totalDistanceMiles
                if let last = segment.stops.last {
                    cursor = last.completeAt
                    location = rides.first { $0.id == last.rideID }?.location
                }
            }
            if let commitment {
                var warnings: [String] = []
                if leaveBy < cursor { warnings.append("Not enough time for the reserved walk and arrival buffer. Check this stop.") }
                if commitment.startAt < startAt { warnings.append("This stop starts before your visit window.") }
                if commitment.endAt > endAt { warnings.append("This stop ends after your visit window.") }
                fixed.append(NativeCommitmentStop(commitment: commitment, leaveBy: leaveBy,
                                                  transferMinutes: transferMinutes, transferDistanceMiles: transferMiles, warnings: warnings))
                totalWalk += transferMinutes; totalDistance += transferMiles
                // A late/unreachable stop must not teleport the next leg to its venue.
                let earliestArrival = cursor.addingTimeInterval(Double(transferMinutes) * 60)
                cursor = max(commitment.endAt, earliestArrival)
                location = commitment.location
            }
        }
        let scheduled = Set(stops.map(\.rideID))
        let unavailable = Set(base.unavailableRides.map(\.rideID))
        let listed = Set(rides.filter(\.radarEligible).map(\.id))
        let cut = remaining.intersection(listed).subtracting(scheduled).subtracting(unavailable)
        let last = ([effectiveStart, min(cursor, endAt)] + stops.map(\.completeAt) + fixed.map { min($0.commitment.endAt, endAt) }).max() ?? effectiveStart
        return NativeDayRoute(generatedAt: now, startAt: startAt, endAt: endAt, startLabel: start.label,
                              stops: stops, commitments: fixed, cutRideIDs: cut.sorted(), unavailableRideIDs: unavailable.sorted(),
                              missingRideIDs: remaining.subtracting(listed).sorted(), remainingRideCount: remaining.count,
                              availableMinutes: base.availableMinutes,
                              plannedMinutes: max(0, Int(ceil(last.timeIntervalSince(effectiveStart) / 60))),
                              walkMinutes: totalWalk, distanceMiles: totalDistance)
    }
}

/// Offline payload is deliberately incapable of holding forecasts, weather, or a live-status flag.
struct NativeOfflineRide: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let land: String
    let savedStatus: String
    let savedWaitMinutes: Int?
    let sourceUpdatedAt: Date?
    let location: AttractionLocation?
    let details: RideDetails?

    init(_ ride: LiveRide) {
        id = ride.id; name = ride.name; land = ride.land; savedStatus = ride.status.rawValue
        savedWaitMinutes = ride.waitTime.flatMap { (0...240).contains($0) ? $0 : nil }
        sourceUpdatedAt = ride.lastUpdated; location = ride.location; details = ride.details
    }

    var isValid: Bool {
        guard id >= 0, !name.isEmpty, name.count <= 500, land.count <= 500, savedStatus.count <= 100,
              savedWaitMinutes == nil || (0...240).contains(savedWaitMinutes!),
              location == nil || NativeDayPlanning.validLocation(location) else { return false }
        guard let details else { return true }
        return details.facts.count <= 100 && details.sources.count <= 30 && details.unverified.count <= 100
            && details.riderNote.count <= 10_000 && details.reviewedAt.count <= 100
            && details.facts.allSatisfy { $0.label.count <= 200 && $0.value.count <= 5000 }
            && details.sources.allSatisfy { $0.label.count <= 500 && $0.url.absoluteString.count <= 2000 }
            && details.unverified.allSatisfy { $0.count <= 1000 }
    }
}

struct NativeOfflineDayPack: Codable, Sendable {
    static let schemaVersion = 1
    let version: Int
    let parkID: Int
    let parkName: String
    let timezone: String
    let localDay: String
    let savedAt: Date
    let fetchedAt: Date
    let sourceUpdatedAt: Date?
    let showSourceUpdatedAt: Date?
    let favorites: [Int]
    let day: NativeDayState
    let route: NativeDayRoute?
    let rides: [NativeOfflineRide]
    let shows: [LiveShow]
    let hours: ParkHoursSnapshot?

    var isValid: Bool {
        guard version == Self.schemaVersion, FloridaPark(rawValue: parkID) != nil,
              TimeZone(identifier: timezone) != nil, NativeDayPlanning.validLocalDay(localDay),
              !parkName.isEmpty, parkName.count <= 200,
              savedAt.timeIntervalSince1970.isFinite, fetchedAt.timeIntervalSince1970.isFinite,
              favorites.count <= 1000, favorites.allSatisfy({ $0 >= 0 }), day.isValid,
              rides.count <= 1000, shows.count <= 1000,
              Set(rides.map(\.id)).count == rides.count, Set(shows.map(\.id)).count == shows.count,
              rides.allSatisfy(\.isValid) else { return false }
        let validShows = shows.allSatisfy { show in
            show.name.count <= 500 && show.showtimes.count <= 200 && show.showtimes.allSatisfy {
                $0.startTime.timeIntervalSince1970.isFinite && ($0.endTime == nil || $0.endTime! >= $0.startTime)
            }
        }
        return validShows && (route == nil || route!.isValid)
    }
}

enum NativeDayExperienceError: LocalizedError {
    case invalidCommitment, overlap(String), tooManyCommitments, invalidWindow, unavailableSource
    case corruptFile, tooLarge, quota, storageUnavailable
    var errorDescription: String? {
        switch self {
        case .invalidCommitment: return "Choose a name, valid times, and a duration no longer than 12 hours."
        case .overlap(let title): return "This overlaps \(title). Choose different times."
        case .tooManyCommitments: return "You can save up to 30 fixed stops per park day."
        case .invalidWindow: return "Departure must be after arrival and within 24 hours."
        case .unavailableSource: return "Refresh this park successfully before saving or updating its offline pack."
        case .corruptFile: return "Some saved day data could not be read. Other saved packs are still available. Refresh and save a new pack to replace the damaged one."
        case .tooLarge: return "This day pack is too large to save. The previous saved pack has been kept."
        case .quota: return "Offline storage is full. Remove an old park pack, then try again. The previous pack has been kept."
        case .storageUnavailable: return "Could not save on this device. Free some storage and try again; the previous saved data has been kept."
        }
    }
}

/// One root-owned instance, shared by Plan and Shows. No network or booking calls.
@MainActor
final class NativeDayExperienceStore: ObservableObject {
    @Published private(set) var revision = 0
    @Published private(set) var packs: [Int: NativeOfflineDayPack] = [:]
    @Published private(set) var storageMessage: String?

    private struct StoredDay: Codable {
        let parkID: Int
        let localDay: String
        var updatedAt: Date
        var state: NativeDayState
    }
    private struct DayEnvelope: Codable {
        let version: Int
        let days: [String: StoredDay]
    }
    private var days: [String: StoredDay] = [:]
    private let defaults: UserDefaults
    private let directory: URL
    private let manager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    static let maximumPackBytes = 2 * 1024 * 1024
    static let maximumStateBytes = 512 * 1024
    static let maximumTotalBytes = 24 * 1024 * 1024
    static let maximumStoredDays = 90

    init(directory: URL? = nil, defaults: UserDefaults = .standard, manager: FileManager = .default) {
        self.defaults = defaults; self.manager = manager
        self.directory = directory ?? manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PIVOTDayExperience", isDirectory: true)
        encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        loadFromDisk()
    }

    func state(for park: FloridaPark, at now: Date = Date()) -> NativeDayState {
        let key = NativeDayPlanning.dayKey(park: park, at: now)
        if let current = days[key] { return current.state }
        // An explicit current-day record above is authoritative, including an empty
        // commitment list after removal. Only a day with no record inherits prior plans.
        let localDay = NativeDayPlanning.localDay(park: park, at: now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = park.timeZone
        let dayStart = calendar.startOfDay(for: now)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 3600)
        let candidates: [(updatedAt: Date, localDay: String, state: NativeDayState)] = days.values.compactMap { stored in
            guard stored.parkID == park.id, stored.localDay < localDay else { return nil }
            let windowIsRelevant: Bool
            if let start = stored.state.visitStart, let end = stored.state.visitEnd {
                windowIsRelevant = end > now && (start <= now || (start >= dayStart && start < nextDay))
            } else {
                windowIsRelevant = false
            }
            let pending = stored.state.commitments.filter { commitment in
                guard commitment.endAt > now else { return false }
                // Include an active stop, a later stop today, or a stop inside the
                // carried window (which may itself extend past the next midnight).
                if commitment.startAt <= now || (commitment.startAt >= dayStart && commitment.startAt < nextDay) { return true }
                if windowIsRelevant, let start = stored.state.visitStart, let end = stored.state.visitEnd {
                    return commitment.startAt < end && commitment.endAt > start
                }
                return false
            }
            guard windowIsRelevant || !pending.isEmpty else { return nil }
            var inherited = stored.state
            inherited.progress = [:]
            inherited.commitments = pending
            // A pending stop can outlive an old window. Let today's default window
            // apply instead of reviving an already-ended or unrelated future visit.
            if !windowIsRelevant { inherited.visitStart = nil; inherited.visitEnd = nil }
            return (stored.updatedAt, stored.localDay, inherited)
        }
        let inherited = candidates.max {
            $0.updatedAt == $1.updatedAt ? $0.localDay < $1.localDay : $0.updatedAt < $1.updatedAt
        }
        if let inherited { return inherited.state }
        return legacyWindow(for: park, at: now) ?? NativeDayState()
    }

    // Preserve both old RootView key variants without removing their UserDefaults values.
    // The imported window is persisted into the new day file on the next explicit day edit.
    private func legacyWindow(for park: FloridaPark, at now: Date) -> NativeDayState? {
        let localDay = NativeDayPlanning.localDay(park: park, at: now)
        let labels = [localDay, ParkTimeFormatter.parkDate(now, timeZone: park.timeZone)]
        for label in labels {
            let key = "pivot.dayPlan.\(park.id).\(label)"
            guard let start = defaults.object(forKey: key + ".start") as? Date,
                  let end = defaults.object(forKey: key + ".end") as? Date,
                  start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
                  NativeDayPlanning.localDay(park: park, at: start) == localDay,
                  end > start, end.timeIntervalSince(start) <= 24 * 3600 else { continue }
            var imported = NativeDayState()
            imported.visitStart = start; imported.visitEnd = end
            return imported
        }
        return nil
    }

    func favorites(for park: FloridaPark) -> Set<Int> {
        Set((defaults.array(forKey: favoriteKey(park)) as? [Int] ?? []).filter { $0 >= 0 }.prefix(1000))
    }

    func setFavorite(_ selected: Bool, rideID: Int, park: FloridaPark) {
        guard rideID >= 0 else { return }
        var values = favorites(for: park)
        if selected { guard values.count < 1000 else { return }; values.insert(rideID) } else { values.remove(rideID) }
        // Never intersect with the current feed: it may be incomplete.
        defaults.set(values.sorted(), forKey: favoriteKey(park)); revision += 1
    }

    func setProgress(_ progress: NativeRideProgress?, rideID: Int, park: FloridaPark, now: Date = Date()) throws {
        guard rideID >= 0 else { return }
        try update(park, at: now) { $0.progress[rideID] = progress }
    }

    func setStart(_ value: String, park: FloridaPark, now: Date = Date()) throws {
        guard value.count <= 250 else { return }
        try update(park, at: now) { $0.start = value }
    }

    func setVisitWindow(start: Date, end: Date, park: FloridaPark, now: Date = Date()) throws {
        guard end > start, end.timeIntervalSince(start) <= 24 * 3600 else { throw NativeDayExperienceError.invalidWindow }
        try update(park, at: now) { $0.visitStart = start; $0.visitEnd = end }
    }

    func addCommitment(_ commitment: NativeDayCommitment, park: FloridaPark, now: Date = Date()) throws {
        guard commitment.isValid else { throw NativeDayExperienceError.invalidCommitment }
        let current = state(for: park, at: now)
        guard current.commitments.count < 30 else { throw NativeDayExperienceError.tooManyCommitments }
        if let existing = current.commitments.first(where: { $0.overlaps(commitment) || $0.id == commitment.id }) {
            throw NativeDayExperienceError.overlap(existing.title)
        }
        try update(park, at: now) { $0.commitments.append(commitment) }
    }

    /// Shows UI integration: caller presents localized errors in its own sheet/banner.
    func addShow(_ show: LiveShow, showtime: LiveShowtime, park: FloridaPark, now: Date = Date()) throws {
        guard showtime.startTime.timeIntervalSince1970.isFinite, showtime.startTime > now else { throw NativeDayExperienceError.invalidCommitment }
        let validEnd = showtime.endTime.flatMap { $0 > showtime.startTime ? $0 : nil }
        let commitment = NativeDayCommitment(id: "show:\(show.id):\(Int(showtime.startTime.timeIntervalSince1970))",
                                            title: String(show.name.prefix(100)), kind: .show,
                                            startAt: showtime.startTime, endAt: validEnd ?? showtime.startTime.addingTimeInterval(30 * 60),
                                            bufferMinutes: 15, location: nil,
                                            note: validEnd == nil ? "End time not published; 30 minutes reserved. Check the venue’s schedule." : "Check the venue for schedule changes and entry requirements.")
        try addCommitment(commitment, park: park, now: now)
    }

    func removeCommitment(id: String, park: FloridaPark, now: Date = Date()) throws {
        try update(park, at: now) { $0.commitments.removeAll { $0.id == id } }
    }

    func pack(for park: FloridaPark) -> NativeOfflineDayPack? { packs[park.id] }
    func hasPackFile(for park: FloridaPark) -> Bool { manager.fileExists(atPath: packURL(park).path) }

    /// Explicit saves alone replace a pack. Daily edits never mutate a saved snapshot.
    func savePack(snapshot: LiveParkSnapshot, park: FloridaPark, route: NativeDayRoute?,
                  sourceIsLive: Bool, now: Date = Date()) throws {
        guard sourceIsLive, snapshot.parkId == park.id,
              DashboardFeedHealth.presentation(parkSelected: true, snapshot: snapshot, isLoading: false,
                                               refreshFailed: false, at: now).isLive else { throw NativeDayExperienceError.unavailableSource }
        var rideIDs: Set<Int> = []; var showIDs: Set<String> = []
        let pack = NativeOfflineDayPack(version: NativeOfflineDayPack.schemaVersion, parkID: park.id, parkName: park.name,
                                       timezone: park.timeZone.identifier, localDay: NativeDayPlanning.localDay(park: park, at: now),
                                       savedAt: now, fetchedAt: snapshot.fetchedAt, sourceUpdatedAt: snapshot.waitStatusUpdatedAt,
                                       showSourceUpdatedAt: snapshot.showScheduleSourceUpdatedAt,
                                       favorites: favorites(for: park).sorted(), day: state(for: park, at: now), route: route,
                                       rides: snapshot.rides.filter { $0.radarEligible && rideIDs.insert($0.id).inserted }.map(NativeOfflineRide.init),
                                       shows: snapshot.showList.filter { showIDs.insert($0.id).inserted }, hours: snapshot.parkHours)
        guard pack.isValid else { throw NativeDayExperienceError.tooLarge }
        do {
            try write(pack, to: packURL(park), limit: Self.maximumPackBytes)
            packs[park.id] = pack; revision += 1; storageMessage = nil
        } catch { throw publish(error) }
    }

    func removePack(for park: FloridaPark) throws {
        do {
            let url = packURL(park)
            if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
            packs.removeValue(forKey: park.id); revision += 1; storageMessage = nil
        } catch { throw publish(error) }
    }

    private func favoriteKey(_ park: FloridaPark) -> String { "pivot.favoriteRides.\(park.id)" }
    private var stateURL: URL { directory.appendingPathComponent("days-v1.json") }
    private func packURL(_ park: FloridaPark) -> URL { directory.appendingPathComponent("pack-v1-\(park.id).json") }

    private func update(_ park: FloridaPark, at now: Date, change: (inout NativeDayState) -> Void) throws {
        let key = NativeDayPlanning.dayKey(park: park, at: now)
        var next = state(for: park, at: now); change(&next)
        guard next.isValid else { throw NativeDayExperienceError.invalidCommitment }
        var updated = days
        updated[key] = StoredDay(parkID: park.id, localDay: NativeDayPlanning.localDay(park: park, at: now), updatedAt: now, state: next)
        let recent = updated.sorted { $0.value.updatedAt == $1.value.updatedAt ? $0.key < $1.key : $0.value.updatedAt > $1.value.updatedAt }
            .prefix(Self.maximumStoredDays)
        updated = Dictionary(uniqueKeysWithValues: recent.map { ($0.key, $0.value) })
        do {
            try write(DayEnvelope(version: 1, days: updated), to: stateURL, limit: Self.maximumStateBytes)
            days = updated; revision += 1; storageMessage = nil
        } catch { throw publish(error) }
    }

    private func fileSize(_ url: URL) -> Int {
        ((try? manager.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.intValue ?? 0
    }

    private func read<T: Decodable>(_ type: T.Type, url: URL, limit: Int) throws -> T {
        guard fileSize(url) > 0, fileSize(url) <= limit else { throw NativeDayExperienceError.corruptFile }
        return try decoder.decode(type, from: Data(contentsOf: url))
    }

    private func write<T: Encodable>(_ value: T, to url: URL, limit: Int) throws {
        let bytes = try encoder.encode(value)
        guard bytes.count <= limit else { throw NativeDayExperienceError.tooLarge }
        let knownFiles = [stateURL] + FloridaPark.allCases.map { packURL($0) }
        let total = knownFiles.reduce(0) { $0 + fileSize($1) } - fileSize(url) + bytes.count
        guard total <= Self.maximumTotalBytes else { throw NativeDayExperienceError.quota }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        try bytes.write(to: url, options: .atomic)
    }

    private func publish(_ error: Error) -> Error {
        let mapped = (error as? NativeDayExperienceError) ?? .storageUnavailable
        storageMessage = mapped.localizedDescription
        return mapped
    }

    private func loadFromDisk() {
        if manager.fileExists(atPath: stateURL.path) {
            do {
                let envelope = try read(DayEnvelope.self, url: stateURL, limit: Self.maximumStateBytes)
                guard envelope.version == 1, envelope.days.count <= Self.maximumStoredDays,
                      envelope.days.allSatisfy({ key, day in
                          FloridaPark(rawValue: day.parkID) != nil && key == "\(day.parkID):\(day.localDay)"
                          && NativeDayPlanning.validLocalDay(day.localDay) && day.updatedAt.timeIntervalSince1970.isFinite && day.state.isValid
                      }) else { throw NativeDayExperienceError.corruptFile }
                days = envelope.days
            } catch { storageMessage = NativeDayExperienceError.corruptFile.localizedDescription }
        }
        // Enumerate known parks, never arbitrary unbounded filenames or payload lengths.
        var readBytes = 0
        for park in FloridaPark.allCases where manager.fileExists(atPath: packURL(park).path) {
            do {
                let size = fileSize(packURL(park))
                guard size > 0, size <= Self.maximumPackBytes else { throw NativeDayExperienceError.corruptFile }
                guard readBytes + size <= Self.maximumTotalBytes else { throw NativeDayExperienceError.quota }
                let pack = try read(NativeOfflineDayPack.self, url: packURL(park), limit: Self.maximumPackBytes)
                guard pack.parkID == park.id, pack.isValid else { throw NativeDayExperienceError.corruptFile }
                readBytes += size
                packs[park.id] = pack
            } catch { storageMessage = NativeDayExperienceError.corruptFile.localizedDescription }
        }
    }
}
