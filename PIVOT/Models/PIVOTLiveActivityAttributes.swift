import Foundation

struct PIVOTLiveActivityAttributes: Codable, Hashable, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        let rideID: Int
        let episodeIdentifier: String?
        let rideName: String
        let landName: String
        let closureStartedAt: Date?
        let closureDurationIsMinimum: Bool
        let closureDurationText: String
        let closureDurationAccessibilityLabel: String
        let delayType: String?
        let statusSummary: String
        let forecastPhase: String?
        let forecastRevision: Int?
        let forecastRevisionReason: String?
        let windowStart: Date?
        let bestGuess: Date?
        let windowEnd: Date?
        let evidenceStrength: String?
        let lastUpdated: Date
        // Older server pushes do not carry the current evidence gates.
        var guidanceVersion: Int? = nil

        var isWeatherDelay: Bool {
            delayType == "WEATHER"
        }

        var isMissedWindowRevision: Bool {
            (forecastRevision ?? 0) > 0 && forecastRevisionReason == "WINDOW_MISSED"
        }

        var animationKey: String {
            episodeIdentifier
                ?? "\(rideID):\(Int(closureStartedAt?.timeIntervalSince1970 ?? 0))"
        }

    }

    let parkID: Int
    let parkName: String
    let timeZoneIdentifier: String
    // Attributes survive content updates and are shared with the Watch.
    var accentName: String? = nil

    var accentRGB: UInt32 {
        switch accentName {
        case "blue": return 0x87c7ff
        case "purple": return 0xc1a5ff
        case "pink": return 0xff9fce
        case "orange": return 0xffb477
        case "gold": return 0xf2d369
        default: return 0x78e3bf
        }
    }
}

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

extension PIVOTLiveActivityAttributes: ActivityAttributes {}
#endif
