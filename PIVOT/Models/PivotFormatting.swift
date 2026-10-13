import Foundation

struct DashboardFeedHealth: Equatable, Sendable {
    let isLive: Bool
    let status: String
    let retainedGuidance: String?

    var badgeLabel: String {
        isLive ? "Live" : retainedGuidance != nil ? "Saved" : "Updating"
    }

    // Match the existing live-wait and Live Activity freshness window. Source
    // version timestamps may stay unchanged for a long closure; age the fetch.
    static let maximumAge: TimeInterval = 15 * 60

    static func presentation(
        parkSelected: Bool,
        snapshot: LiveParkSnapshot?,
        isLoading: Bool,
        refreshFailed: Bool,
        at now: Date = Date()
    ) -> DashboardFeedHealth {
        guard parkSelected else {
            return Self(isLive: false, status: "Paused · choose a park", retainedGuidance: nil)
        }
        let retainedGuidance = snapshot == nil ? nil
            : "Saved wait times, ride status, and reopening guidance may have changed. Check current conditions before relying on them."
        // A previously healthy response cannot hide a later failed refresh.
        if refreshFailed {
            return Self(
                isLive: false,
                status: snapshot == nil ? "Refresh failed" : "Refresh failed · last update retained",
                retainedGuidance: retainedGuidance
            )
        }
        guard let snapshot else {
            return Self(isLive: false, status: isLoading ? "Refreshing" : "Waiting for live data", retainedGuidance: nil)
        }
        let fetchedAt = min(snapshot.fetchedAt, snapshot.themeParksWiki?.fetchedAt ?? snapshot.fetchedAt)
        let age = now.timeIntervalSince(fetchedAt)
        guard snapshot.feedHealthy, snapshot.themeParksWiki?.available != false,
              age.isFinite, age >= -120, age < maximumAge else {
            return Self(isLive: false, status: "Source too old to call live · last update retained", retainedGuidance: retainedGuidance)
        }
        let checked = ParkTimeFormatter.age(snapshot.fetchedAt, relativeTo: now)
        if snapshot.themeParksWiki?.cacheStale == true {
            return Self(isLive: false, status: "Saved snapshot · retrying · checked \(checked)", retainedGuidance: retainedGuidance)
        }
        return Self(isLive: true, status: "Live · auto 5s · checked \(checked)", retainedGuidance: nil)
    }
}

/// Source observations describe mapped activity, not the operator's reopening decision.
struct DashboardLightningHealth: Equatable, Sendable {
    let isCurrent: Bool
    let title: String
    static let maximumCheckAge: TimeInterval = 3 * 60
    static let maximumDensityAge: TimeInterval = 30 * 60

    static func presentation(lightning: LightningDetails, feedHealth: DashboardFeedHealth, at now: Date) -> Self {
        func fresh(_ date: Date?, maximumAge: TimeInterval) -> Bool {
            guard let date else { return false }
            let age = now.timeIntervalSince(date)
            return age.isFinite && age >= -120 && age < maximumAge
        }
        let glm = lightning.sourceKind == "GLM" ? lightning.glm : nil
        let observedAt = glm?.observedThrough ?? lightning.sourceUpdatedAt
        let hasCoverage = glm != nil
            ? glm?.status == "LIVE" && glm?.state != "UNKNOWN"
            : (lightning.completeFrames30Minutes ?? 0) > 0
        let current = feedHealth.isLive && lightning.status == "LIVE" && hasCoverage &&
            fresh(glm?.checkedAt ?? lightning.checkedAt, maximumAge: maximumCheckAge) &&
            fresh(observedAt, maximumAge: glm != nil ? 5 * 60 : maximumDensityAge)
        return Self(isCurrent: current, title: current ? "Mapped lightning observations"
            : observedAt == nil ? "Lightning observations unavailable" : "Saved lightning observations · current conditions unknown")
    }
}

struct DashboardClosureHealth {
    static func canAssertNoClosures(snapshot: LiveParkSnapshot?, feedHealth: DashboardFeedHealth) -> Bool {
        guard feedHealth.isLive, let snapshot, snapshot.parkActive else { return false }
        let rides = snapshot.rides.filter(\.radarEligible)
        return !rides.isEmpty && rides.allSatisfy {
            $0.status == .open || $0.status == .scheduled || $0.status == .parkInactive
        }
    }
}

extension ParkHoursSnapshot {
    func isCurrent(for park: FloridaPark, at now: Date = Date()) -> Bool {
        parkId == park.rawValue && date == Self.localDate(for: park, at: now)
    }

    static func localDate(for park: FloridaPark, at now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = park.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now)
    }

    static func current(
        for park: FloridaPark,
        candidates: [ParkHoursSnapshot?],
        at now: Date = Date()
    ) -> ParkHoursSnapshot? {
        candidates.compactMap { $0 }
            .filter { $0.isCurrent(for: park, at: now) }
            .sorted {
                if $0.stale != $1.stale { return !$0.stale }
                return $0.fetchedAt > $1.fetchedAt
            }
            .first
    }
}

struct ForecastPresentation: Equatable, Sendable {
    let headline: String
    let range: String
    let bestGuess: String
    let detail: String
    let inline: String
}

/// A supported historical range is different from a park-confirmed reopening.
/// These gates also protect clients talking to older servers without metadata.
struct ReopeningGuidance: Equatable, Sendable {
    let headline: String
    let range: String?
    let bestGuess: String?
    let detail: String

    static func presentation(ride: LiveRide, snapshot: LiveParkSnapshot?, feedHealth: DashboardFeedHealth,
                             at now: Date, timeZone: TimeZone) -> Self {
        func uncertain(_ detail: String, title: String = "Reopening time uncertain") -> Self {
            Self(headline: title, range: nil, bestGuess: nil, detail: detail)
        }
        guard feedHealth.isLive, let snapshot, snapshot.parkActive,
              snapshot.rides.contains(where: { $0.id == ride.id && $0.status == .down }), ride.status == .down else {
            return uncertain("Refresh current ride observations before relying on reopening guidance.", title: "Saved guidance · time unavailable")
        }
        guard let estimate = ride.estimate else {
            return uncertain("A reliable reopening time is not available yet.")
        }
        let dates = [estimate.issuedAt, estimate.windowStart, estimate.historicalMedianAt, estimate.windowEnd]
        guard dates.allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              estimate.issuedAt <= now.addingTimeInterval(120), estimate.windowStart <= estimate.historicalMedianAt,
              estimate.historicalMedianAt <= estimate.windowEnd else {
            return uncertain("The reopening estimate could not be verified.")
        }
        guard now <= estimate.windowEnd else {
            return uncertain("The earlier window passed. The ride is still reported down; a reliable new time is unavailable.", title: "Earlier window missed")
        }
        let range = "\(ParkTimeFormatter.time(estimate.windowStart, timeZone: timeZone))–\(ParkTimeFormatter.time(estimate.windowEnd, timeZone: timeZone))"
        if ride.hasWeatherHold {
            let lightning = snapshot.weather.lightning
            guard lightning.sourceKind != "GLM",
                  DashboardLightningHealth.presentation(lightning: lightning, feedHealth: feedHealth, at: now).isCurrent else {
                return uncertain("Current lightning observations are unavailable. Weather reopening timing is unknown.", title: "Weather timing unavailable")
            }
            guard lightning.clearanceState == "VERIFIED", let verified = lightning.clearanceVerifiedAt,
                  let clearance = lightning.clearanceAt, verified >= clearance, verified <= now,
                  let observed = lightning.sourceUpdatedAt, observed >= verified,
                  (lightning.completeFrames30Minutes ?? 0) >= 2 else {
                return uncertain("Lightning may continue. The clear clock does not predict when the park will reopen a ride.", title: "Weather timing uncertain")
            }
            guard estimate.estimateKind == "WEATHER", estimate.reliability?.showRange == true,
                  (estimate.weatherRestartLagSampleSize ?? 0) >= 5,
                  let estimateClearance = estimate.weatherClearanceAt,
                  abs(estimateClearance.timeIntervalSince(clearance)) < 60 else {
                return uncertain("Mapped lightning has cleared. Waiting for the park to confirm reopening; comparable restart history is limited.", title: "Waiting for ride confirmation")
            }
            return Self(headline: "Historical restart range", range: range, bestGuess: nil,
                        detail: "Based on observed restarts after mapped lightning clearance. The park decides when the ride reopens.")
        }
        guard estimate.startQuality == "observed", estimate.closureSignal == "confirmed" else {
            return uncertain("The closure start or a second closed observation is not confirmed yet.")
        }
        func recent(_ timestamp: String?) -> Bool {
            guard let timestamp,
                  let data = try? JSONEncoder().encode(timestamp),
                  let date = try? PivotAPIClient.makeDecoder().decode(Date.self, from: data) else { return false }
            let age = estimate.issuedAt.timeIntervalSince(date)
            return age >= 0 && age <= 90 * 24 * 60 * 60
        }
        guard (estimate.sameRideSampleSize ?? 0) >= 4, estimate.effectiveSampleSize >= 4,
              estimate.distinctDayCount >= 3, estimate.recentSampleSize >= 4,
              recent(estimate.historyProvenance?.trainedThrough) else {
            return uncertain("Too few comparable closures for this ride at its current downtime. PIVOT is still learning.")
        }
        if let calibration = estimate.calibration, calibration.sampleSize >= 20,
           let coverage = calibration.historicalCoverage, !coverage.isFinite || coverage < 0.6 {
            return uncertain("Recent scored windows have missed too often to give a reliable reopening time.")
        }
        if let reliability = estimate.reliability, !reliability.showRange {
            return uncertain(reliability.reason)
        }
        let calibration = estimate.calibration
        let showBest = estimate.evidenceStrength == "Moderate" && (estimate.sameRideSampleSize ?? 0) >= 8 &&
            calibration?.version == "PIVOT-ONLINE-CALIBRATION-v4" &&
            calibration?.basis == "same-ride residuals" && (calibration?.sampleSize ?? 0) >= 20 &&
            (calibration?.effectiveSampleSize ?? 0) >= 12 && (calibration?.historicalCoverage ?? 0) >= 0.7 &&
            recent(calibration?.trainedThrough) && estimate.reliability?.showBestGuess != false
        return Self(headline: "Historical reopening range", range: range,
                    bestGuess: showBest ? ParkTimeFormatter.time(estimate.historicalMedianAt, timeZone: timeZone) : nil,
                    detail: "Based on comparable observed closures. The park has not announced a reopening time.")
    }
}
struct DownTimePresentation: Equatable, Sendable {
    let text: String
    let accessibilityLabel: String
}

enum ShowScheduleState: Equatable, Sendable {
    case upcoming
    case finishedForToday
    case noScheduledPerformances
    case providerUnavailable
}

struct ShowSchedulePresentation: Equatable, Sendable {
    let state: ShowScheduleState
    let headline: String
    let detail: String
    let nextShowName: String?
    let nextShowAt: Date?
    let upcomingShowCount: Int
}

struct ShowScheduleRowPresentation: Equatable, Sendable {
    let statusLabel: String
    let countLabel: String
}

enum ShowScheduleRowFormatter {
    static func presentation(
        for show: LiveShow,
        referenceDate: Date = Date()
    ) -> ShowScheduleRowPresentation {
        let statusLabel: String
        if let next = show.sortedShowtimes.first(where: { $0.startTime >= referenceDate }) {
            statusLabel = "Next \(ParkTimeFormatter.time(next.startTime))"
        } else if let active = show.sortedShowtimes.first(where: {
            $0.startTime <= referenceDate && ($0.endTime ?? $0.startTime) > referenceDate
        }) {
            statusLabel = "In progress until \(ParkTimeFormatter.time(active.endTime ?? referenceDate))"
        } else if !show.showtimes.isEmpty {
            statusLabel = "Finished for today"
        } else {
            let publishedStatus = show.status?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "_", with: " ")
            if let publishedStatus, !publishedStatus.isEmpty,
               !["OPERATING", "OPEN"].contains(publishedStatus.uppercased()) {
                statusLabel = publishedStatus.capitalized
            } else {
                statusLabel = "Time not posted today"
            }
        }

        let countLabel = show.showtimes.isEmpty
            ? "Schedule"
            : "\(show.showtimes.count) \(show.showtimes.count == 1 ? "time" : "times")"
        return ShowScheduleRowPresentation(statusLabel: statusLabel, countLabel: countLabel)
    }

    static func pillLabel(for showtime: LiveShowtime) -> String {
        let start = ParkTimeFormatter.time(showtime.startTime)
        let normalizedType = showtime.type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedType == "operating", let endTime = showtime.endTime, endTime > showtime.startTime {
            return "Available \(start)–\(ParkTimeFormatter.time(endTime))"
        }
        if normalizedType == "at capacity" {
            return "\(start) · At capacity"
        }
        return start
    }

    static func accessibilityLabel(for showtime: LiveShowtime) -> String {
        let start = ParkTimeFormatter.time(showtime.startTime)
        let normalizedType = showtime.type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedType == "operating", let endTime = showtime.endTime, endTime > showtime.startTime {
            return "Available from \(start) to \(ParkTimeFormatter.time(endTime))"
        }
        if normalizedType == "at capacity" {
            return "\(start), at capacity"
        }
        return start
    }
}

private enum ClosureDurationFormatter {
    static func duration(minutes: Int) -> String {
        let minutes = max(0, minutes)
        guard minutes >= 60 else { return "\(minutes) min" }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        guard remainingMinutes > 0 else { return "\(hours) hr" }
        return "\(hours) hr \(remainingMinutes) min"
    }
}

enum ParkTimeFormatter {
    static let floridaTimeZone = TimeZone(identifier: "America/New_York")!

    static var selectedParkTimeZone: TimeZone {
        guard let value = UserDefaults.standard.object(forKey: "pivot.selectedPark") as? NSNumber,
              let park = FloridaPark(rawValue: value.intValue) else {
            return floridaTimeZone
        }
        return park.timeZone
    }

    static func time(_ date: Date, timeZone: TimeZone? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone ?? selectedParkTimeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func dateTime(_ date: Date?, timeZone: TimeZone? = nil) -> String {
        guard let date else { return "Not available" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone ?? selectedParkTimeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM d h:mm a z")
        return formatter.string(from: date)
    }

    static func observationTime(_ date: Date?, timeZone: TimeZone? = nil) -> String {
        guard let date else { return "Not available" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone ?? selectedParkTimeZone
        formatter.setLocalizedDateFormatFromTemplate("h:mm:ss a z")
        return formatter.string(from: date)
    }

    static func parkDate(_ date: Date = Date(), timeZone: TimeZone? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone ?? selectedParkTimeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEE MMMM d")
        return formatter.string(from: date).uppercased()
    }

    static func modelTimestamp(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "Not available" }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return dateTime(date) }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: value) { return dateTime(date) }

        let dateOnly = DateFormatter()
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.timeZone = selectedParkTimeZone
        dateOnly.dateFormat = "yyyy-MM-dd"
        guard let date = dateOnly.date(from: value) else { return value }

        dateOnly.locale = Locale(identifier: "en_US")
        dateOnly.setLocalizedDateFormatFromTemplate("MMM d y")
        return dateOnly.string(from: date)
    }

    static func age(_ date: Date?, relativeTo now: Date = Date()) -> String {
        guard let date else { return "unknown" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }
}

extension LiveShowtime {
    var scheduleLabel: String {
        guard let endTime, endTime > startTime else {
            return ParkTimeFormatter.time(startTime)
        }
        return "\(ParkTimeFormatter.time(startTime))–\(ParkTimeFormatter.time(endTime))"
    }
}

extension LiveShow {
    var sortedShowtimes: [LiveShowtime] {
        showtimes.sorted { lhs, rhs in
            if lhs.startTime == rhs.startTime {
                return (lhs.endTime ?? lhs.startTime) < (rhs.endTime ?? rhs.startTime)
            }
            return lhs.startTime < rhs.startTime
        }
    }

    var dailyScheduleText: String {
        let labels = sortedShowtimes.map(\.scheduleLabel)
        return labels.isEmpty ? "No timed performances published" : labels.joined(separator: "  ·  ")
    }
}

extension LiveParkSnapshot {
    func showSchedulePresentation(referenceDate now: Date = Date()) -> ShowSchedulePresentation {
        let scheduledEntries = showList.flatMap { show in
            show.sortedShowtimes.map { showtime in
                (show: show, showtime: showtime)
            }
        }
        let futureEntries = scheduledEntries
            .filter { $0.showtime.startTime >= now }
            .sorted { $0.showtime.startTime < $1.showtime.startTime }
        let upcomingShowCount = Set(futureEntries.map { $0.show.id }).count

        if let next = futureEntries.first {
            return ShowSchedulePresentation(
                state: .upcoming,
                headline: next.show.name,
                detail: "Next at \(ParkTimeFormatter.time(next.showtime.startTime))",
                nextShowName: next.show.name,
                nextShowAt: next.showtime.startTime,
                upcomingShowCount: upcomingShowCount
            )
        }

        if let active = scheduledEntries
            .filter({ entry in
                entry.showtime.startTime <= now && (entry.showtime.endTime ?? entry.showtime.startTime) > now
            })
            .sorted(by: { ($0.showtime.endTime ?? $0.showtime.startTime) < ($1.showtime.endTime ?? $1.showtime.startTime) })
            .first {
            return ShowSchedulePresentation(
                state: .upcoming,
                headline: active.show.name,
                detail: "In progress until \(ParkTimeFormatter.time(active.showtime.endTime ?? now))",
                nextShowName: active.show.name,
                nextShowAt: active.showtime.startTime,
                upcomingShowCount: 0
            )
        }

        if !scheduledEntries.isEmpty {
            return ShowSchedulePresentation(
                state: .finishedForToday,
                headline: "Finished for today",
                detail: "All published performances have ended.",
                nextShowName: nil,
                nextShowAt: nil,
                upcomingShowCount: 0
            )
        }

        if showScheduleProviderUnavailable {
            let warning = showsSource?.warning ?? themeParksWiki?.warning
            let detail = warning.flatMap { $0.isEmpty ? nil : $0 }
                ?? "PIVOT could not load today’s provider schedule."
            return ShowSchedulePresentation(
                state: .providerUnavailable,
                headline: "Entertainment schedule unavailable",
                detail: detail,
                nextShowName: nil,
                nextShowAt: nil,
                upcomingShowCount: 0
            )
        }

        return ShowSchedulePresentation(
            state: .noScheduledPerformances,
            headline: "No scheduled performances today",
            detail: showList.isEmpty
                ? "The published daily schedule contains no performances for this park."
                : "Entertainment is listed, but no timed performances are published.",
            nextShowName: nil,
            nextShowAt: nil,
            upcomingShowCount: 0
        )
    }

    var showScheduleSourceLabel: String {
        showsSource?.label ?? themeParksWiki?.source.label ?? "Entertainment schedule"
    }

    var showScheduleSourceUpdatedAt: Date? {
        showsSource?.sourceUpdatedAt
            ?? showsSource?.fetchedAt
            ?? showsSourceUpdatedAt
            ?? themeParksWiki?.showSourceUpdatedAt
            ?? themeParksWiki?.sourceUpdatedAt
    }

    var showScheduleIsStale: Bool {
        showsSource?.stale ?? themeParksWiki?.cacheStale ?? false
    }

    private var showScheduleProviderUnavailable: Bool {
        if let showsSource {
            return showList.isEmpty && showsSource.warning?.isEmpty == false
        }
        if let themeParksWiki {
            return !themeParksWiki.available || (showList.isEmpty && themeParksWiki.warning?.isEmpty == false)
        }
        return true
    }
}

extension ReopeningEstimate {
    var isMissedWindowRevision: Bool {
        revision > 0 && revisionReason == "WINDOW_MISSED"
    }

    var isModelUpdateRevision: Bool {
        revision > 0 && revisionReason == "MODEL_UPDATE"
    }

    var radarFallbackRejectedRevisionDescription: String? {
        guard revisionReason == "RADAR_FALLBACK_REJECTED" else { return nil }
        return "Revision \(revision) issued \(ParkTimeFormatter.dateTime(issuedAt)). NOAA covering evidence rejected provisional park-weather classification, so a new operational estimate replaced it."
    }

    var presentation: ForecastPresentation {
        presentation(timeZone: ParkTimeFormatter.selectedParkTimeZone)
    }

    func presentation(timeZone: TimeZone) -> ForecastPresentation {
        let range = "\(ParkTimeFormatter.time(windowStart, timeZone: timeZone))–\(ParkTimeFormatter.time(windowEnd, timeZone: timeZone))"
        let best = ParkTimeFormatter.time(historicalMedianAt, timeZone: timeZone)

        switch forecastPhase {
        case .upcoming:
            if isModelUpdateRevision {
                return ForecastPresentation(
                    headline: "Updated reopening window",
                    range: range,
                    bestGuess: best,
                    detail: "Newly calibrated model · \(range) · best guess \(best)",
                    inline: "Updated window · \(range) · best guess \(best)"
                )
            }
            if isMissedWindowRevision {
                return ForecastPresentation(
                    headline: "Revised reopening window",
                    range: range,
                    bestGuess: best,
                    detail: "Updated after the prior window was missed · \(range) · best guess \(best)",
                    inline: "Revised window · \(range) · best guess \(best)"
                )
            }
            return ForecastPresentation(
                headline: "Upcoming reopening window",
                range: range,
                bestGuess: best,
                detail: "Expected \(range) · best guess \(best)",
                inline: "Upcoming window · \(range) · best guess \(best)"
            )
        case .inWindow:
            if isModelUpdateRevision {
                return ForecastPresentation(
                    headline: "Inside updated window",
                    range: range,
                    bestGuess: best,
                    detail: "Updated reopening window now · \(range) · best guess \(best)",
                    inline: "Inside updated window · \(range) · best guess \(best)"
                )
            }
            if isMissedWindowRevision {
                return ForecastPresentation(
                    headline: "Inside revised window",
                    range: range,
                    bestGuess: best,
                    detail: "Revised reopening window now · \(range) · best guess \(best)",
                    inline: "Inside revised window · \(range) · best guess \(best)"
                )
            }
            return ForecastPresentation(
                headline: "Inside predicted window",
                range: range,
                bestGuess: best,
                detail: "Reopening window now · \(range) · best guess \(best)",
                inline: "Inside predicted window · \(range) · best guess \(best)"
            )
        case .pastWindow:
            if isMissedWindowRevision {
                return ForecastPresentation(
                    headline: "Revised window missed by \(lateMinutes) min",
                    range: range,
                    bestGuess: best,
                    detail: "Revised window missed by \(lateMinutes) min · ride still down · best guess was \(best)",
                    inline: "Revised window missed by \(lateMinutes) min · \(range) · best guess was \(best)"
                )
            }
            return ForecastPresentation(
                headline: "Past original window by \(lateMinutes) min",
                range: range,
                bestGuess: best,
                detail: "Original window missed by \(lateMinutes) min · ride still down · original best guess \(best)",
                inline: "Past original window by \(lateMinutes) min · \(range) · best guess \(best)"
            )
        case .unknown:
            if isMissedWindowRevision {
                return ForecastPresentation(
                    headline: "Revised reopening forecast",
                    range: range,
                    bestGuess: best,
                    detail: "Revised window \(range) · best guess \(best)",
                    inline: "Revised forecast window \(range) · best guess \(best)"
                )
            }
            return ForecastPresentation(
                headline: "Reopening forecast",
                range: range,
                bestGuess: best,
                detail: "Window \(range) · best guess \(best)",
                inline: "Forecast window \(range) · best guess \(best)"
            )
        }
    }
}

struct DayPlanStop: Identifiable, Equatable, Sendable {
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
    let experienceMinutes: Int

    var id: Int { rideID }
}

struct DayPlan: Equatable, Sendable {
    let startAt: Date
    let endAt: Date
    let effectiveStartAt: Date
    let generatedAt: Date
    let availableMinutes: Int
    let plannedMinutes: Int
    let remainingMinutes: Int
    let totalWalkMinutes: Int
    let totalDistanceMiles: Double
    let requestedRideCount: Int
    let selectionRequired: Bool
    let startsFromNow: Bool
    let fitsAllRequested: Bool
    let minimumMinutesForAll: Int?
    let extraMinutesNeeded: Int
    let cutRides: [DayPlanRideDecision]
    let unavailableRides: [DayPlanRideDecision]
    let stops: [DayPlanStop]
    let locatedRideCount: Int
    let eligibleRideCount: Int
}

struct DayPlanRideDecision: Identifiable, Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        case time
        case unavailable
    }

    let rideID: Int
    let rideName: String
    let status: RideStatus
    let reason: Reason

    var id: Int { rideID }
}

enum DayPlanner {
    private static let walkingSpeedMPH = 3.0
    private static let parkPathFactor = 1.35

    static func distanceMiles(from first: AttractionLocation, to second: AttractionLocation) -> Double {
        let earthRadiusMiles = 3_958.8
        let firstLatitude = first.latitude * .pi / 180
        let secondLatitude = second.latitude * .pi / 180
        let latitudeDelta = (second.latitude - first.latitude) * .pi / 180
        let longitudeDelta = (second.longitude - first.longitude) * .pi / 180
        let a = pow(sin(latitudeDelta / 2), 2)
            + cos(firstLatitude) * cos(secondLatitude) * pow(sin(longitudeDelta / 2), 2)
        return earthRadiusMiles * 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }

    static func build(
        rides: [LiveRide],
        requestedRideIDs: Set<Int>,
        startAt: Date,
        endAt: Date,
        now: Date = Date(),
        startLocation: AttractionLocation?
    ) -> DayPlan {
        let effectiveStart = max(startAt, min(now, endAt))
        let availableMinutes = max(0, min(14 * 60, Int(endAt.timeIntervalSince(effectiveStart) / 60)))
        let requested = rides.filter { requestedRideIDs.contains($0.id) && $0.radarEligible }
        let eligible = requested.filter {
            $0.radarEligible
                && $0.status == .open
                && $0.waitTime.map { (0...240).contains($0) } == true
        }
        let eligibleIDs = Set(eligible.map(\.id))
        let unavailable = requested.filter { !eligibleIDs.contains($0.id) }
        let fullRoute = orderedRoute(rides: eligible, startLocation: startLocation)
        let fitted = routeThatFits(rides: eligible, availableMinutes: availableMinutes, startLocation: startLocation)
        var stops: [DayPlanStop] = []
        var cursor = effectiveStart
        var totalWalkMinutes = 0
        var totalDistanceMiles = 0.0

        for leg in fitted.route.legs {
            let wait = leg.ride.waitTime ?? 0
            let arriveAt = cursor.addingTimeInterval(TimeInterval(leg.walkMinutes * 60))
            let experienceAt = arriveAt.addingTimeInterval(TimeInterval(wait * 60))
            cursor = experienceAt.addingTimeInterval(TimeInterval(leg.experienceMinutes * 60))
            totalWalkMinutes += leg.walkMinutes
            totalDistanceMiles += leg.distanceMiles
            stops.append(DayPlanStop(
                rideID: leg.ride.id,
                rideName: leg.ride.name,
                land: leg.ride.land,
                sequence: stops.count + 1,
                arriveAt: arriveAt,
                experienceAt: experienceAt,
                completeAt: cursor,
                walkMinutes: leg.walkMinutes,
                distanceMiles: leg.distanceMiles,
                expectedWaitMinutes: wait,
                experienceMinutes: leg.experienceMinutes
            ))
        }

        let plannedMinutes = max(0, Int(cursor.timeIntervalSince(effectiveStart) / 60))
        let cutRides = fitted.removed.map {
            DayPlanRideDecision(rideID: $0.id, rideName: $0.name, status: $0.status, reason: .time)
        }.sorted { $0.rideName.localizedStandardCompare($1.rideName) == .orderedAscending }
        let unavailableRides = unavailable.map {
            DayPlanRideDecision(rideID: $0.id, rideName: $0.name, status: $0.status, reason: .unavailable)
        }.sorted { $0.rideName.localizedStandardCompare($1.rideName) == .orderedAscending }
        let selectionRequired = requestedRideIDs.isEmpty
        return DayPlan(
            startAt: startAt,
            endAt: endAt,
            effectiveStartAt: effectiveStart,
            generatedAt: now,
            availableMinutes: availableMinutes,
            plannedMinutes: plannedMinutes,
            remainingMinutes: max(0, availableMinutes - plannedMinutes),
            totalWalkMinutes: totalWalkMinutes,
            totalDistanceMiles: totalDistanceMiles,
            requestedRideCount: requestedRideIDs.count,
            selectionRequired: selectionRequired,
            startsFromNow: now > startAt && now < endAt,
            fitsAllRequested: !selectionRequired && cutRides.isEmpty && unavailableRides.isEmpty,
            minimumMinutesForAll: selectionRequired ? nil : fullRoute.durationMinutes,
            extraMinutesNeeded: selectionRequired ? 0 : max(0, fullRoute.durationMinutes - availableMinutes),
            cutRides: cutRides,
            unavailableRides: unavailableRides,
            stops: stops,
            locatedRideCount: eligible.filter { $0.location != nil }.count,
            eligibleRideCount: eligible.count
        )
    }

    private struct OrderedLeg {
        let ride: LiveRide
        let walkMinutes: Int
        let distanceMiles: Double
        let experienceMinutes: Int
    }

    private struct OrderedRoute {
        let legs: [OrderedLeg]
        let durationMinutes: Int
        let demandScore: Int
    }

    private struct RemovalEstimate {
        let removedRide: LiveRide
        let minutesSaved: Int
    }

    private static func orderedRoute(rides: [LiveRide], startLocation: AttractionLocation?) -> OrderedRoute {
        var remaining = Dictionary(uniqueKeysWithValues: rides.map { ($0.id, $0) })
        var legs: [OrderedLeg] = []
        var currentLocation = startLocation
        var currentLand: String?
        var durationMinutes = 0
        var demandScore = 0

        while !remaining.isEmpty {
            let candidates = remaining.values.map { ride -> (ride: LiveRide, walking: (miles: Double, minutes: Int), experience: Int, score: Double) in
                let sameLand = currentLand != nil && currentLand == ride.land
                let walking = walkingLeg(from: currentLocation, to: ride.location, sameLand: sameLand)
                let experience = experienceMinutes(for: ride.name)
                return (
                    ride,
                    walking,
                    experience,
                    score(for: ride, walkMinutes: walking.minutes, experienceMinutes: experience, sameLand: sameLand)
                )
            }.sorted {
                if legs.isEmpty {
                    let firstIsLocated = $0.ride.location != nil
                    let secondIsLocated = $1.ride.location != nil
                    if firstIsLocated != secondIsLocated { return firstIsLocated }
                    if currentLocation != nil, firstIsLocated, secondIsLocated,
                       $0.walking.miles != $1.walking.miles {
                        return $0.walking.miles < $1.walking.miles
                    }
                }
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.walking.minutes != $1.walking.minutes { return $0.walking.minutes < $1.walking.minutes }
                return $0.ride.name.localizedStandardCompare($1.ride.name) == .orderedAscending
            }
            guard let selected = candidates.first else { break }
            legs.append(OrderedLeg(
                ride: selected.ride,
                walkMinutes: selected.walking.minutes,
                distanceMiles: selected.walking.miles,
                experienceMinutes: selected.experience
            ))
            durationMinutes += selected.walking.minutes + (selected.ride.waitTime ?? 0) + selected.experience
            demandScore += recentDemandMinutes(for: selected.ride)
            remaining.removeValue(forKey: selected.ride.id)
            currentLocation = selected.ride.location
            currentLand = selected.ride.land
        }

        return OrderedRoute(legs: legs, durationMinutes: durationMinutes, demandScore: demandScore)
    }

    private static func routeThatFits(
        rides: [LiveRide],
        availableMinutes: Int,
        startLocation: AttractionLocation?
    ) -> (route: OrderedRoute, removed: [LiveRide]) {
        var kept = rides
        var removed: [LiveRide] = []
        var route = orderedRoute(rides: kept, startLocation: startLocation)

        while !kept.isEmpty, route.durationMinutes > availableMinutes {
            let estimates = route.legs.enumerated().map { index, leg -> RemovalEstimate in
                var minutesSaved = leg.walkMinutes
                    + (leg.ride.waitTime ?? 0)
                    + leg.experienceMinutes

                if route.legs.indices.contains(index + 1) {
                    let nextLeg = route.legs[index + 1]
                    let previousRide = index > 0 ? route.legs[index - 1].ride : nil
                    let replacementOrigin = previousRide == nil ? startLocation : previousRide?.location
                    let replacementWalk = walkingLeg(
                        from: replacementOrigin,
                        to: nextLeg.ride.location,
                        sameLand: previousRide?.land == nextLeg.ride.land
                    )
                    minutesSaved += nextLeg.walkMinutes - replacementWalk.minutes
                }

                return RemovalEstimate(
                    removedRide: leg.ride,
                    minutesSaved: max(1, minutesSaved)
                )
            }

            let minutesNeeded = route.durationMinutes - availableMinutes
            let fitting = estimates.filter { $0.minutesSaved >= minutesNeeded }
            let selected = (fitting.isEmpty ? estimates : fitting).sorted { first, second in
                if !fitting.isEmpty {
                    let firstDemand = recentDemandMinutes(for: first.removedRide)
                    let secondDemand = recentDemandMinutes(for: second.removedRide)
                    if firstDemand != secondDemand { return firstDemand < secondDemand }
                    if first.minutesSaved != second.minutesSaved { return first.minutesSaved > second.minutesSaved }
                    return first.removedRide.name.localizedStandardCompare(second.removedRide.name) == .orderedAscending
                }
                let firstEfficiency = Double(first.minutesSaved) / Double(max(15, recentDemandMinutes(for: first.removedRide)))
                let secondEfficiency = Double(second.minutesSaved) / Double(max(15, recentDemandMinutes(for: second.removedRide)))
                if firstEfficiency != secondEfficiency { return firstEfficiency > secondEfficiency }
                let firstDemand = recentDemandMinutes(for: first.removedRide)
                let secondDemand = recentDemandMinutes(for: second.removedRide)
                if firstDemand != secondDemand { return firstDemand < secondDemand }
                return first.removedRide.name.localizedStandardCompare(second.removedRide.name) == .orderedAscending
            }.first
            guard let selected else { break }
            removed.append(selected.removedRide)
            kept.removeAll { $0.id == selected.removedRide.id }
            route = orderedRoute(rides: kept, startLocation: startLocation)
        }

        return (route, removed)
    }

    private static func walkingLeg(
        from: AttractionLocation?,
        to: AttractionLocation?,
        sameLand: Bool
    ) -> (miles: Double, minutes: Int) {
        guard let from, let to else {
            return sameLand ? (0.08, 2) : (0.24, 7)
        }
        let miles = distanceMiles(from: from, to: to) * parkPathFactor
        let minutes = max(1, min(24, Int(ceil(miles / walkingSpeedMPH * 60))))
        return (miles, minutes)
    }

    private static func recentDemandMinutes(for ride: LiveRide) -> Int {
        let values = ride.trend.filter { $0 >= 0 }.suffix(12).sorted()
        guard !values.isEmpty else { return max(15, ride.waitTime ?? 15) }
        let middle = values.count / 2
        return values.count.isMultiple(of: 2)
            ? Int((Double(values[middle - 1] + values[middle]) / 2).rounded())
            : values[middle]
    }

    private static func experienceMinutes(for name: String) -> Int {
        let normalized = name.lowercased()
        if ["railroad", "railway", "train", "monorail", "ferry", "transport", "express"].contains(where: normalized.contains) {
            return 18
        }
        if ["river", "rapids", "cruise", "safari", "tour"].contains(where: normalized.contains) {
            return 12
        }
        return 8
    }

    private static func score(
        for ride: LiveRide,
        walkMinutes: Int,
        experienceMinutes: Int,
        sameLand: Bool
    ) -> Double {
        let demand = min(120, recentDemandMinutes(for: ride))
        let attractionValue = 38 + Double(demand) * 0.9
        let timeCost = max(1, (ride.waitTime ?? 0) + experienceMinutes + walkMinutes)
        return attractionValue / Double(timeCost) + (sameLand ? 0.12 : 0)
    }
}

extension DelayEvidence {
    var closureWaveOpenNonVetoDescription: String? {
        guard weatherOriginSignal == "RADAR_CLOSURE_WAVE",
              (closureWaveIgnoredOpenOutliers ?? 0) > 0 else {
            return nil
        }
        return "One contradictory OPEN row did not veto the park signal; its raw provider status was not overridden."
    }

    var rideWeatherClearanceDescription: String {
        if weatherOriginSignal == "RADAR_CLOSURE_WAVE" {
            return "Provisional radar/NWS weather range · no verified strike"
        }
        switch clearanceState {
        case "ACTIVE":
            return "Lightning clear clock reset"
        case "COUNTDOWN":
            return "Lightning clear \(clearMinutes ?? 0) of \(requiredClearMinutes ?? 30) min"
        case "VERIFIED":
            return "30 min lightning clear · restart pending"
        default:
            return "Lightning clearance updating"
        }
    }
}

extension LiveRide {
    var hasWeatherHold: Bool {
        status == .down && (weatherHoldActive == true || delayType == "WEATHER" || estimate?.estimateKind == "WEATHER")
    }

    var downStatusLabel: String {
        guard status == .down else { return "" }
        if weatherHoldActive == true { return "Weather delay · lightning hold" }
        return hasWeatherHold ? "Weather delay likely" : "Temporarily down"
    }

    var retainedOperationalWeatherNote: String? {
        hasWeatherHold && estimate?.estimateKind == "OPERATIONAL"
            ? "Original ride estimate retained; active weather may delay reopening."
            : nil
    }

    var isPostOperationalWeatherConstraint: Bool {
        status == .down &&
            estimate?.estimateKind == "WEATHER" &&
            delayEvidence?.closureTimingMatched == false
    }

    func downTimePresentation(referenceDate: Date) -> DownTimePresentation? {
        guard status == .down else { return nil }
        if let downSince, downSince <= referenceDate {
            let elapsed = max(0, Int(referenceDate.timeIntervalSince(downSince) / 60))
            let text = "Closed for \(ClosureDurationFormatter.duration(minutes: elapsed))"
            return DownTimePresentation(
                text: text,
                accessibilityLabel: text
            )
        }
        if let elapsedDownMinutes, elapsedDownMinutes >= 0 {
            let text = "Closed for \(ClosureDurationFormatter.duration(minutes: elapsedDownMinutes))"
            return DownTimePresentation(
                text: text,
                accessibilityLabel: text
            )
        }
        if let minimumDownMinutes, minimumDownMinutes >= 0 {
            let text = "Closed for at least \(ClosureDurationFormatter.duration(minutes: minimumDownMinutes))"
            return DownTimePresentation(
                text: text,
                accessibilityLabel: "\(text); the exact closure start time is unavailable"
            )
        }
        return DownTimePresentation(
            text: "Closed · duration unavailable",
            accessibilityLabel: "Ride closed; closure duration is unavailable"
        )
    }

    var downTimePresentation: DownTimePresentation? {
        downTimePresentation(referenceDate: Date())
    }

    var statusDescription: String {
        switch status {
        case .open:
            if waitTime == nil {
                return "ThemeParks.wiki reports open · wait not recently posted"
            }
            return waitTime == 0
                ? "Walk-on reported · ThemeParks.wiki"
                : "ThemeParks.wiki reports open"
        case .down where isPostOperationalWeatherConstraint:
            return "Ride delay · reopening now limited by lightning"
        case .down where retainedOperationalWeatherNote != nil:
            return "Ride delay · lightning nearby"
        case .down where hasWeatherHold:
            return "Weather delay likely · waiting for ride confirmation"
        case .down where delayEvidence?.label == "Weather possible; awaiting nearby lightning confirmation":
            return "Weather check pending · awaiting the newest NOAA lightning frame"
        case .down where delayType == "RIDE":
            return "Ride delay · cause not published"
        case .down:
            return "Delay cause not published"
        case .scheduled:
            if let operatingWindow {
                return operatingWindow.label
            }
            if let scheduledClosure {
                return "\(scheduledClosure.source.name) lists refurbishment"
            }
            return scheduledReason == "REFURBISHMENT"
                ? "ThemeParks.wiki reports refurbishment"
                : "ThemeParks.wiki reports closed"
        case .parkInactive:
            return "Park not active"
        case .stale:
            return statusAgreement == "CONFLICT"
                ? "Status update pending · checking the newest source"
                : "Source updated \(ParkTimeFormatter.age(lastUpdated))"
        case .unknown(let value):
            return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
