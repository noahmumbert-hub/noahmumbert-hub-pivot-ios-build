import Foundation

#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

struct PIVOTLiveActivityTarget: Equatable, Sendable {
    let attributes: PIVOTLiveActivityAttributes
    let state: PIVOTLiveActivityAttributes.ContentState
    let staleDate: Date
    let episodeIdentifier: String

    func requiresActivityUpdate(
        currentState: PIVOTLiveActivityAttributes.ContentState,
        currentStaleDate: Date?
    ) -> Bool {
        state != currentState || staleDate != currentStaleDate
    }
}

enum PIVOTLiveActivityRideSelector {
    static func featuredClosedRide(in rides: [LiveRide], pinnedRideID: Int?) -> LiveRide? {
        if let pinnedRideID,
           let pinned = rides.first(where: { $0.id == pinnedRideID && $0.isRadarDown }) {
            return pinned
        }
        return mostPopularClosedRide(in: rides)
    }

    static func mostPopularClosedRide(in rides: [LiveRide]) -> LiveRide? {
        rides
            .filter(\.isRadarDown)
            .sorted { first, second in
                switch (first.recentTypicalWait, second.recentTypicalWait) {
                case let (firstWait?, secondWait?) where firstWait != secondWait:
                    return firstWait > secondWait
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    if first.trend.count != second.trend.count {
                        return first.trend.count > second.trend.count
                    }
                    let nameOrder = first.name.localizedCaseInsensitiveCompare(second.name)
                    if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                    return first.id < second.id
                }
            }
            .first
    }
}

enum PIVOTLiveActivityTargetBuilder {
    private static let sourceStaleInterval: TimeInterval = 15 * 60

    static func makeTarget(
        selectedPark: FloridaPark?,
        snapshot: LiveParkSnapshot?,
        featuredRide: LiveRide?,
        accentName: String? = nil
    ) -> PIVOTLiveActivityTarget? {
        guard let selectedPark,
              let snapshot,
              snapshot.parkId == selectedPark.rawValue,
              snapshot.feedHealthy,
              snapshot.parkActive,
              let featuredRide,
              featuredRide.isRadarDown,
              snapshot.rides.contains(where: { $0.id == featuredRide.id && $0.isRadarDown }) else {
            return nil
        }

        let estimate = featuredRide.estimate
        // A freshly fetched snapshot is a fresh observation even when the
        // provider's per-ride timestamp is old. Use the successful snapshot
        // observation for ActivityKit freshness, duration copy, and staleness.
        let snapshotObservedAt = snapshot.fetchedAt
        let duration = featuredRide.downTimePresentation(referenceDate: snapshotObservedAt) ?? DownTimePresentation(
            text: "Closed · duration unavailable",
            accessibilityLabel: "Ride closed; closure duration is unavailable"
        )
        let closureStartedAt: Date?
        let closureDurationIsMinimum: Bool
        if let downSince = featuredRide.downSince {
            closureStartedAt = downSince
            closureDurationIsMinimum = false
        } else if let elapsedDownMinutes = featuredRide.elapsedDownMinutes {
            closureStartedAt = snapshot.fetchedAt.addingTimeInterval(-Double(max(0, elapsedDownMinutes)) * 60)
            closureDurationIsMinimum = false
        } else if let minimumDownMinutes = featuredRide.minimumDownMinutes {
            closureStartedAt = estimate?.episodeAnchorAt
                ?? snapshot.fetchedAt.addingTimeInterval(-Double(max(0, minimumDownMinutes)) * 60)
            closureDurationIsMinimum = true
        } else {
            closureStartedAt = nil
            closureDurationIsMinimum = false
        }
        let episodeAnchor = estimate?.episodeAnchorAt
            ?? featuredRide.downSince
            ?? snapshot.waitStatusUpdatedAt
            ?? snapshot.fetchedAt
        let episodeIdentifier = "\(selectedPark.rawValue):\(featuredRide.id):\(Int(episodeAnchor.timeIntervalSince1970))"

        return PIVOTLiveActivityTarget(
            attributes: PIVOTLiveActivityAttributes(
                parkID: selectedPark.rawValue,
                parkName: snapshot.park.name,
                timeZoneIdentifier: snapshot.park.timezone,
                accentName: accentName
            ),
            state: PIVOTLiveActivityAttributes.ContentState(
                rideID: featuredRide.id,
                episodeIdentifier: episodeIdentifier,
                rideName: featuredRide.name,
                landName: featuredRide.land,
                closureStartedAt: closureStartedAt,
                closureDurationIsMinimum: closureDurationIsMinimum,
                closureDurationText: duration.text,
                closureDurationAccessibilityLabel: duration.accessibilityLabel,
                delayType: featuredRide.delayType,
                statusSummary: featuredRide.statusDescription,
                forecastPhase: estimate?.forecastPhase.rawValue,
                forecastRevision: estimate?.revision,
                forecastRevisionReason: estimate?.revisionReason,
                windowStart: estimate?.windowStart,
                bestGuess: estimate?.historicalMedianAt,
                windowEnd: estimate?.windowEnd,
                evidenceStrength: estimate?.evidenceStrength,
                lastUpdated: snapshotObservedAt
            ),
            staleDate: snapshotObservedAt.addingTimeInterval(sourceStaleInterval),
            episodeIdentifier: episodeIdentifier
        )
    }
}

@MainActor
final class LiveActivityService {
    private(set) var desiredTarget: PIVOTLiveActivityTarget?
    private(set) var lastErrorDescription: String?

    private static let lastRequestedEpisodeKey = "pivot.liveActivity.lastRequestedEpisode"
    private static let presentationVersionKey = "pivot.liveActivity.presentationVersion"
    private static let blankDynamicIslandPresentationVersion = "watch-accent-v3"

    private let defaults: UserDefaults
    private var synchronizationTask: Task<Void, Never>?
    private var lastRequestedEpisodeIdentifier: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastRequestedEpisodeIdentifier = defaults.string(forKey: Self.lastRequestedEpisodeKey)
    }

    deinit {
        synchronizationTask?.cancel()
    }

    func synchronize(_ target: PIVOTLiveActivityTarget?) {
        desiredTarget = target
        synchronizationTask?.cancel()
        synchronizationTask = nil
        if target == nil {
            // Clear synchronously so a quick No Park → park change can start
            // the same closure even if the asynchronous end is cancelled.
            forgetLastRequestedEpisode()
        }

#if canImport(ActivityKit) && os(iOS)
        synchronizationTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            await self.apply(target)
        }
#endif
    }

    private func rememberLastRequestedEpisode(_ identifier: String) {
        lastRequestedEpisodeIdentifier = identifier
        defaults.set(identifier, forKey: Self.lastRequestedEpisodeKey)
    }

    private func forgetLastRequestedEpisode() {
        lastRequestedEpisodeIdentifier = nil
        defaults.removeObject(forKey: Self.lastRequestedEpisodeKey)
    }

#if canImport(ActivityKit) && os(iOS)
    private func apply(_ target: PIVOTLiveActivityTarget?) async {
        let activities = Activity<PIVOTLiveActivityAttributes>.activities

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            await end(activities)
            forgetLastRequestedEpisode()
            lastErrorDescription = nil
            return
        }

        // Activities created by an older widget extension can keep their old
        // Dynamic Island rendering until they end. End them once after this
        // presentation change, then recreate the current target using the
        // blank island regions from the new widget.
        let needsPresentationMigration = defaults.string(forKey: Self.presentationVersionKey) != Self.blankDynamicIslandPresentationVersion
        if needsPresentationMigration {
            await end(activities)
            forgetLastRequestedEpisode()
            defaults.set(Self.blankDynamicIslandPresentationVersion, forKey: Self.presentationVersionKey)
        }

        guard let target else {
            if !needsPresentationMigration {
                await end(activities)
            }
            // This was an app-driven end (No Park, a clear Radar, or an
            // inactive park), so the same closure may start again later.
            forgetLastRequestedEpisode()
            lastErrorDescription = nil
            return
        }

        var matchingActivity: Activity<PIVOTLiveActivityAttributes>?
        for activity in needsPresentationMigration ? [] : activities {
            if matchingActivity == nil, activity.attributes == target.attributes {
                matchingActivity = activity
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
                // A settings change is an app-driven replacement, not a dismissal.
                if activity.attributes.parkID == target.attributes.parkID {
                    forgetLastRequestedEpisode()
                }
            }
        }

        guard !Task.isCancelled else { return }
        let content = ActivityContent(
            state: target.state,
            staleDate: target.staleDate,
            relevanceScore: 100
        )

        if let matchingActivity {
            guard target.requiresActivityUpdate(
                currentState: matchingActivity.content.state,
                currentStaleDate: matchingActivity.content.staleDate
            ) else {
                rememberLastRequestedEpisode(target.episodeIdentifier)
                lastErrorDescription = nil
                return
            }
            await matchingActivity.update(content)
            rememberLastRequestedEpisode(target.episodeIdentifier)
            lastErrorDescription = nil
            return
        }

        // If the person dismisses this closure's Live Activity, respect that
        // choice instead of recreating it on the next 5-second refresh.
        guard lastRequestedEpisodeIdentifier != target.episodeIdentifier else {
            lastErrorDescription = nil
            return
        }

        do {
            _ = try Activity.request(
                attributes: target.attributes,
                content: content,
                pushType: nil
            )
            rememberLastRequestedEpisode(target.episodeIdentifier)
            lastErrorDescription = nil
        } catch {
            lastErrorDescription = error.localizedDescription
        }
    }

    private func end(_ activities: [Activity<PIVOTLiveActivityAttributes>]) async {
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
#endif
}
