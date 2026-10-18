import Foundation
import CoreLocation

enum FloridaPark: Int, CaseIterable, Codable, Identifiable, Sendable {
    case epcot = 5
    case magicKingdom = 6
    case hollywoodStudios = 7
    case animalKingdom = 8
    case seaWorldOrlando = 21
    case buschGardensTampaBay = 24
    case sixFlagsMagicMountain = 32
    case sixFlagsDiscoveryKingdom = 33
    case sixFlagsOverTexas = 34
    case sixFlagsOverGeorgia = 35
    case sixFlagsGreatAdventure = 37
    case sixFlagsGreatAmerica = 38
    case sixFlagsFiestaTexas = 39
    case hurricaneHarborLosAngeles = 41
    case sixFlagsNewEngland = 43
    case hurricaneHarborNewJersey = 44
    case cedarPoint = 50
    case californiasGreatAmerica = 57
    case canadasWonderland = 58
    case carowinds = 59
    case kingsIsland = 60
    case knottsBerryFarm = 61
    case kingsDominion = 62
    case islandsOfAdventure = 64
    case universalStudiosFlorida = 65
    case volcanoBay = 67
    case dorneyPark = 69
    case sixFlagsDarienLake = 281
    case frontierCity = 282
    case hurricaneHarborPhoenix = 295
    case epicUniverse = 334
    case schlitterbahnNewBraunfels = 339

    var id: Int { rawValue }

    private var profile: ParkProfile {
        switch self {
        case .epcot:
            ParkProfile(name: "EPCOT", destination: "Walt Disney World", operatorName: "Disney", portfolioName: "Disney", country: "United States", region: "FL", timeZoneIdentifier: "America/New_York")
        case .magicKingdom:
            ParkProfile(name: "Magic Kingdom Park", destination: "Walt Disney World", operatorName: "Disney", portfolioName: "Disney", country: "United States", region: "FL", timeZoneIdentifier: "America/New_York")
        case .hollywoodStudios:
            ParkProfile(name: "Disney’s Hollywood Studios", destination: "Walt Disney World", operatorName: "Disney", portfolioName: "Disney", country: "United States", region: "FL", timeZoneIdentifier: "America/New_York")
        case .animalKingdom:
            ParkProfile(name: "Disney’s Animal Kingdom", destination: "Walt Disney World", operatorName: "Disney", portfolioName: "Disney", country: "United States", region: "FL", timeZoneIdentifier: "America/New_York")
        case .seaWorldOrlando:
            ParkProfile(name: "SeaWorld Orlando", destination: "SeaWorld Orlando", operatorName: "United Parks & Resorts", portfolioName: "United Parks", country: "United States", region: "FL", timeZoneIdentifier: "America/New_York")
        case .buschGardensTampaBay:
            ParkProfile(name: "Busch Gardens Tampa Bay", destination: "Busch Gardens Tampa Bay", operatorName: "United Parks & Resorts", portfolioName: "United Parks", country: "United States", region: "FL", timeZoneIdentifier: "America/New_York")
        case .sixFlagsMagicMountain:
            ParkProfile(name: "Six Flags Magic Mountain", destination: "Six Flags Magic Mountain", operatorName: "Six Flags", portfolioName: "Legacy Six Flags", country: "United States", region: "CA", timeZoneIdentifier: "America/Los_Angeles")
        case .sixFlagsDiscoveryKingdom:
            ParkProfile(name: "Six Flags Discovery Kingdom", destination: "Six Flags Discovery Kingdom", operatorName: "Six Flags", portfolioName: "Legacy Six Flags", country: "United States", region: "CA", timeZoneIdentifier: "America/Los_Angeles")
        case .sixFlagsOverTexas:
            ParkProfile(name: "Six Flags Over Texas", destination: "Six Flags Over Texas", operatorName: "Six Flags", portfolioName: "Legacy Six Flags", country: "United States", region: "TX", timeZoneIdentifier: "America/Chicago")
        case .sixFlagsOverGeorgia:
            ParkProfile(name: "Six Flags Over Georgia", destination: "Six Flags Over Georgia", operatorName: "Six Flags", portfolioName: "Legacy Six Flags", country: "United States", region: "GA", timeZoneIdentifier: "America/New_York")
        case .sixFlagsGreatAdventure:
            ParkProfile(name: "Six Flags Great Adventure", destination: "Six Flags Great Adventure", operatorName: "Six Flags", portfolioName: "Legacy Six Flags", country: "United States", region: "NJ", timeZoneIdentifier: "America/New_York")
        case .sixFlagsGreatAmerica:
            ParkProfile(name: "Six Flags Great America", destination: "Six Flags Great America", operatorName: "Six Flags", portfolioName: "Legacy Six Flags", country: "United States", region: "IL", timeZoneIdentifier: "America/Chicago")
        case .sixFlagsFiestaTexas:
            ParkProfile(name: "Six Flags Fiesta Texas", destination: "Six Flags Fiesta Texas", operatorName: "Six Flags", portfolioName: "Legacy Six Flags", country: "United States", region: "TX", timeZoneIdentifier: "America/Chicago")
        case .hurricaneHarborLosAngeles:
            ParkProfile(name: "Hurricane Harbor Los Angeles", destination: "Six Flags Magic Mountain", operatorName: "Six Flags", portfolioName: "Legacy Six Flags", country: "United States", region: "CA", timeZoneIdentifier: "America/Los_Angeles")
        case .sixFlagsNewEngland:
            ParkProfile(name: "Six Flags New England", destination: "Six Flags New England", operatorName: "Six Flags", portfolioName: "Legacy Six Flags", country: "United States", region: "MA", timeZoneIdentifier: "America/New_York")
        case .hurricaneHarborNewJersey:
            ParkProfile(name: "Hurricane Harbor New Jersey", destination: "Six Flags Great Adventure", operatorName: "Six Flags", portfolioName: "Legacy Six Flags", country: "United States", region: "NJ", timeZoneIdentifier: "America/New_York")
        case .cedarPoint:
            ParkProfile(name: "Cedar Point", destination: "Cedar Point", operatorName: "Six Flags", portfolioName: "Legacy Cedar Fair", country: "United States", region: "OH", timeZoneIdentifier: "America/New_York")
        case .californiasGreatAmerica:
            ParkProfile(name: "California’s Great America", destination: "California’s Great America", operatorName: "Six Flags", portfolioName: "Legacy Cedar Fair", country: "United States", region: "CA", timeZoneIdentifier: "America/Los_Angeles")
        case .canadasWonderland:
            ParkProfile(name: "Canada’s Wonderland", destination: "Canada’s Wonderland", operatorName: "Six Flags", portfolioName: "Legacy Cedar Fair", country: "Canada", region: "ON", timeZoneIdentifier: "America/Toronto")
        case .carowinds:
            ParkProfile(name: "Carowinds", destination: "Carowinds", operatorName: "Six Flags", portfolioName: "Legacy Cedar Fair", country: "United States", region: "NC", timeZoneIdentifier: "America/New_York")
        case .kingsIsland:
            ParkProfile(name: "Kings Island", destination: "Kings Island", operatorName: "Six Flags", portfolioName: "Legacy Cedar Fair", country: "United States", region: "OH", timeZoneIdentifier: "America/New_York")
        case .knottsBerryFarm:
            ParkProfile(name: "Knott’s Berry Farm", destination: "Knott’s Berry Farm", operatorName: "Six Flags", portfolioName: "Legacy Cedar Fair", country: "United States", region: "CA", timeZoneIdentifier: "America/Los_Angeles")
        case .kingsDominion:
            ParkProfile(name: "Kings Dominion", destination: "Kings Dominion", operatorName: "Six Flags", portfolioName: "Legacy Cedar Fair", country: "United States", region: "VA", timeZoneIdentifier: "America/New_York")
        case .islandsOfAdventure:
            ParkProfile(name: "Islands of Adventure", destination: "Universal Orlando Resort", operatorName: "Universal", portfolioName: "Universal", country: "United States", region: "FL", timeZoneIdentifier: "America/New_York")
        case .universalStudiosFlorida:
            ParkProfile(name: "Universal Studios Florida", destination: "Universal Orlando Resort", operatorName: "Universal", portfolioName: "Universal", country: "United States", region: "FL", timeZoneIdentifier: "America/New_York")
        case .volcanoBay:
            ParkProfile(name: "Volcano Bay", destination: "Universal Orlando Resort", operatorName: "Universal", portfolioName: "Universal", country: "United States", region: "FL", timeZoneIdentifier: "America/New_York")
        case .dorneyPark:
            ParkProfile(name: "Dorney Park & Wildwater Kingdom", destination: "Dorney Park", operatorName: "Six Flags", portfolioName: "Legacy Cedar Fair", country: "United States", region: "PA", timeZoneIdentifier: "America/New_York")
        case .sixFlagsDarienLake:
            ParkProfile(name: "Six Flags Darien Lake", destination: "Six Flags Darien Lake", operatorName: "Six Flags", portfolioName: "Legacy Six Flags", country: "United States", region: "NY", timeZoneIdentifier: "America/New_York")
        case .frontierCity:
            ParkProfile(name: "Frontier City", destination: "Frontier City", operatorName: "Six Flags", portfolioName: "Legacy Six Flags", country: "United States", region: "OK", timeZoneIdentifier: "America/Chicago")
        case .hurricaneHarborPhoenix:
            ParkProfile(name: "Hurricane Harbor Phoenix", destination: "Hurricane Harbor Phoenix", operatorName: "Six Flags", portfolioName: "Legacy Six Flags", country: "United States", region: "AZ", timeZoneIdentifier: "America/Phoenix")
        case .epicUniverse:
            ParkProfile(name: "Epic Universe", destination: "Universal Orlando Resort", operatorName: "Universal", portfolioName: "Universal", country: "United States", region: "FL", timeZoneIdentifier: "America/New_York")
        case .schlitterbahnNewBraunfels:
            ParkProfile(name: "Schlitterbahn New Braunfels", destination: "Schlitterbahn New Braunfels", operatorName: "Six Flags", portfolioName: "Legacy Cedar Fair", country: "United States", region: "TX", timeZoneIdentifier: "America/Chicago")
        }
    }

    var name: String { profile.name }
    var destination: String { profile.destination }
    var operatorName: String { profile.operatorName }
    var portfolioName: String { profile.portfolioName }
    var country: String { profile.country }
    var region: String { profile.region }
    var timeZoneIdentifier: String { profile.timeZoneIdentifier }
    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    var monogram: String {
        switch portfolioName {
        case "Disney": "D"
        case "Universal": "U"
        case "United Parks": "UP"
        case "Legacy Cedar Fair": "CF"
        default: "SF"
        }
    }
}

private struct ParkProfile {
    let name: String
    let destination: String
    let operatorName: String
    let portfolioName: String
    let country: String
    let region: String
    let timeZoneIdentifier: String
}

struct ParkLocationMatch: Equatable, Sendable {
    let park: FloridaPark
    let distanceMiles: Double
}

enum ParkLocationDetector {
    static let autoSelectRadiusMiles = 1.15

    static let coordinates: [FloridaPark: CLLocationCoordinate2D] = [
        .epcot: CLLocationCoordinate2D(latitude: 28.3747, longitude: -81.5494),
        .magicKingdom: CLLocationCoordinate2D(latitude: 28.4177, longitude: -81.5812),
        .hollywoodStudios: CLLocationCoordinate2D(latitude: 28.3575, longitude: -81.5583),
        .animalKingdom: CLLocationCoordinate2D(latitude: 28.3553, longitude: -81.5901),
        .seaWorldOrlando: CLLocationCoordinate2D(latitude: 28.4109798106776, longitude: -81.4609839717373),
        .buschGardensTampaBay: CLLocationCoordinate2D(latitude: 28.0374, longitude: -82.42144),
        .sixFlagsMagicMountain: CLLocationCoordinate2D(latitude: 34.42423428947369, longitude: -118.59764502631579),
        .sixFlagsDiscoveryKingdom: CLLocationCoordinate2D(latitude: 38.13835972972973, longitude: -122.2343589189189),
        .sixFlagsOverTexas: CLLocationCoordinate2D(latitude: 32.75678647727272, longitude: -97.06974006818183),
        .sixFlagsOverGeorgia: CLLocationCoordinate2D(latitude: 33.76792149999999, longitude: -84.5505920952381),
        .sixFlagsGreatAdventure: CLLocationCoordinate2D(latitude: 40.13633274468086, longitude: -74.44006631914895),
        .sixFlagsGreatAmerica: CLLocationCoordinate2D(latitude: 42.367267555555564, longitude: -87.93380948888893),
        .sixFlagsFiestaTexas: CLLocationCoordinate2D(latitude: 29.597864140350886, longitude: -98.61022963157892),
        .hurricaneHarborLosAngeles: CLLocationCoordinate2D(latitude: 34.42548385714285, longitude: -118.594412),
        .sixFlagsNewEngland: CLLocationCoordinate2D(latitude: 42.0375025357143, longitude: -72.61397444642856),
        .hurricaneHarborNewJersey: CLLocationCoordinate2D(latitude: 40.14619736363637, longitude: -74.43860154545455),
        .cedarPoint: CLLocationCoordinate2D(latitude: 41.482612666666675, longitude: -82.68423844927537),
        .californiasGreatAmerica: CLLocationCoordinate2D(latitude: 37.39552196296297, longitude: -121.97205129629629),
        .canadasWonderland: CLLocationCoordinate2D(latitude: 43.833872654761905, longitude: -79.53832102380952),
        .carowinds: CLLocationCoordinate2D(latitude: 35.1018777118644, longitude: -80.94225120338986),
        .kingsIsland: CLLocationCoordinate2D(latitude: 39.34189289041095, longitude: -84.26907257534245),
        .knottsBerryFarm: CLLocationCoordinate2D(latitude: 33.84520797297297, longitude: -118.00004456756756),
        .kingsDominion: CLLocationCoordinate2D(latitude: 37.83834903508771, longitude: -77.4436007894737),
        .islandsOfAdventure: CLLocationCoordinate2D(latitude: 28.4717, longitude: -81.4717),
        .universalStudiosFlorida: CLLocationCoordinate2D(latitude: 28.4758, longitude: -81.4682),
        .volcanoBay: CLLocationCoordinate2D(latitude: 28.4623, longitude: -81.4732),
        .dorneyPark: CLLocationCoordinate2D(latitude: 40.579241383333326, longitude: -75.53177849999999),
        .sixFlagsDarienLake: CLLocationCoordinate2D(latitude: 42.92829273913043, longitude: -78.38435410869565),
        .frontierCity: CLLocationCoordinate2D(latitude: 35.58476892857143, longitude: -97.44063714285717),
        .hurricaneHarborPhoenix: CLLocationCoordinate2D(latitude: 33.695868235294114, longitude: -112.14940505882352),
        .epicUniverse: CLLocationCoordinate2D(latitude: 28.4406, longitude: -81.4477),
        .schlitterbahnNewBraunfels: CLLocationCoordinate2D(latitude: 29.708827093023253, longitude: -98.12138525581396)
    ]

    static func nearestPark(
        latitude: Double,
        longitude: Double,
        radiusMiles: Double = autoSelectRadiusMiles
    ) -> ParkLocationMatch? {
        guard latitude.isFinite, longitude.isFinite, radiusMiles > 0 else { return nil }
        let deviceLocation = CLLocation(latitude: latitude, longitude: longitude)
        return FloridaPark.allCases.compactMap { park in
            guard let coordinate = coordinates[park] else { return nil }
            let distanceMiles = deviceLocation.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) / 1_609.344
            guard distanceMiles <= radiusMiles else { return nil }
            return ParkLocationMatch(park: park, distanceMiles: distanceMiles)
        }
        .min { $0.distanceMiles < $1.distanceMiles }
    }
}

/// ThemeParks.wiki's park entity coordinate used as the route's public-gate
/// anchor. Keep this separate from `ParkLocationDetector.coordinates`: those
/// coarse park centers are shared with park auto-selection, while these points
/// define where an entrance-based day plan begins.
enum ParkEntranceLocations {
    static let coordinates: [FloridaPark: CLLocationCoordinate2D] = [
        .epcot: CLLocationCoordinate2D(latitude: 28.3762301397, longitude: -81.5494047655),
        .magicKingdom: CLLocationCoordinate2D(latitude: 28.4160036778, longitude: -81.5811902834),
        .hollywoodStudios: CLLocationCoordinate2D(latitude: 28.3584111691, longitude: -81.558689232),
        .animalKingdom: CLLocationCoordinate2D(latitude: 28.3553842507, longitude: -81.5900898529),
        .seaWorldOrlando: CLLocationCoordinate2D(latitude: 28.4109798106776, longitude: -81.4609839717373),
        .buschGardensTampaBay: CLLocationCoordinate2D(latitude: 28.0374, longitude: -82.42144),
        .sixFlagsMagicMountain: CLLocationCoordinate2D(latitude: 34.42423428947369, longitude: -118.59764502631579),
        .sixFlagsDiscoveryKingdom: CLLocationCoordinate2D(latitude: 38.13835972972973, longitude: -122.2343589189189),
        .sixFlagsOverTexas: CLLocationCoordinate2D(latitude: 32.756825599999985, longitude: -97.0697714888889),
        .sixFlagsOverGeorgia: CLLocationCoordinate2D(latitude: 33.76792149999999, longitude: -84.5505920952381),
        .sixFlagsGreatAdventure: CLLocationCoordinate2D(latitude: 40.13633274468086, longitude: -74.44006631914895),
        .sixFlagsGreatAmerica: CLLocationCoordinate2D(latitude: 42.367275181818194, longitude: -87.93385511363641),
        .sixFlagsFiestaTexas: CLLocationCoordinate2D(latitude: 29.597864140350886, longitude: -98.61022963157892),
        .hurricaneHarborLosAngeles: CLLocationCoordinate2D(latitude: 34.42548385714285, longitude: -118.594412),
        .sixFlagsNewEngland: CLLocationCoordinate2D(latitude: 42.0375025357143, longitude: -72.61397444642856),
        .hurricaneHarborNewJersey: CLLocationCoordinate2D(latitude: 40.14619736363637, longitude: -74.43860154545455),
        .cedarPoint: CLLocationCoordinate2D(latitude: 41.482612666666675, longitude: -82.68423844927537),
        .californiasGreatAmerica: CLLocationCoordinate2D(latitude: 37.39552196296297, longitude: -121.97205129629629),
        .canadasWonderland: CLLocationCoordinate2D(latitude: 43.833872654761905, longitude: -79.53832102380952),
        .carowinds: CLLocationCoordinate2D(latitude: 35.1018777118644, longitude: -80.94225120338986),
        .kingsIsland: CLLocationCoordinate2D(latitude: 39.34189289041095, longitude: -84.26907257534245),
        .knottsBerryFarm: CLLocationCoordinate2D(latitude: 33.84520797297297, longitude: -118.00004456756756),
        .kingsDominion: CLLocationCoordinate2D(latitude: 37.83834903508771, longitude: -77.4436007894737),
        .islandsOfAdventure: CLLocationCoordinate2D(latitude: 28.47225, longitude: -81.467594),
        .universalStudiosFlorida: CLLocationCoordinate2D(latitude: 28.477986, longitude: -81.468386),
        .volcanoBay: CLLocationCoordinate2D(latitude: 28.461355, longitude: -81.472286),
        .dorneyPark: CLLocationCoordinate2D(latitude: 40.579241383333326, longitude: -75.53177849999999),
        .sixFlagsDarienLake: CLLocationCoordinate2D(latitude: 42.92829273913043, longitude: -78.38435410869565),
        .frontierCity: CLLocationCoordinate2D(latitude: 35.58476892857143, longitude: -97.44063714285717),
        .hurricaneHarborPhoenix: CLLocationCoordinate2D(latitude: 33.695868235294114, longitude: -112.14940505882352),
        .epicUniverse: CLLocationCoordinate2D(latitude: 28.4414454548964, longitude: -81.4486740912188),
        .schlitterbahnNewBraunfels: CLLocationCoordinate2D(latitude: 29.708827093023253, longitude: -98.12138525581396)
    ]
}

struct ParkMetadata: Codable, Sendable {
    let name: String
    let destination: String
    let operatorName: String
    let country: String
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case name, destination, country, timezone
        case operatorName = "operator"
    }
}

enum RideStatus: Codable, Equatable, Hashable, Sendable {
    case open
    case down
    case scheduled
    case parkInactive
    case stale
    case unknown(String)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "OPEN": self = .open
        case "DOWN": self = .down
        case "SCHEDULED": self = .scheduled
        case "PARK_INACTIVE": self = .parkInactive
        case "STALE": self = .stale
        default: self = .unknown(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var rawValue: String {
        switch self {
        case .open: "OPEN"
        case .down: "DOWN"
        case .scheduled: "SCHEDULED"
        case .parkInactive: "PARK_INACTIVE"
        case .stale: "STALE"
        case .unknown(let value): value
        }
    }
}

enum ForecastPhase: Codable, Equatable, Hashable, Sendable {
    case upcoming
    case inWindow
    case pastWindow
    case unknown(String)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "UPCOMING": self = .upcoming
        case "IN_WINDOW": self = .inWindow
        case "PAST_WINDOW": self = .pastWindow
        default: self = .unknown(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var rawValue: String {
        switch self {
        case .upcoming: "UPCOMING"
        case .inWindow: "IN_WINDOW"
        case .pastWindow: "PAST_WINDOW"
        case .unknown(let value): value
        }
    }
}

struct ForecastCalibration: Codable, Sendable {
    let version: String
    let basis: String
    let sampleSize: Int
    let effectiveSampleSize: Double
    let distinctRideCount: Int
    let distinctParkCount: Int
    let historicalCoverage: Double?
    let medianAdjustmentMinutes: Int
    let intervalPaddingMinutes: Int
    let trainedThrough: String?
}

struct ReopenHistoryProvenance: Codable, Sendable {
    let trainedThrough: String?
    let confirmedTransitionCount: Int
    let forecastLifecycleCount: Int
    let activeCensoredCount: Int
    let legacyCount: Int
}

struct FrozenHistoricalPriorMetadata: Codable, Sendable {
    let version: String?
    let trainedThrough: String?
    let basis: String
    let sourceName: String?
    let sourceReference: String?
    let license: String?
    let sampleSize: Int
    let distinctDayCount: Int
    let firstObserved: String?
    let lastObserved: String?
    let continuity: String?
    let continuityWeight: Double?
    let intervalUncertaintyMinutes: Double
}

struct AggregateReliabilityProvenance: Codable, Sendable {
    let version: String
    let publisher: String
    let sourceUrl: String
    let reliabilityPageUrl: String
    let documentationUrl: String
    let repositoryCommit: String
    let sourceSha256: String
    let license: String
    let licenseUrl: String
    let attribution: String
    let sourceFreshAsOf: String
    let retrievedAt: String
    let availableFrom: String?
    let documentedRollingWindowDays: Int
    let role: String
    let eventLevelGroundTruth: Bool
}

struct AggregateReliabilityEvidenceAccounting: Codable, Sendable {
    let countsAsObservedOutage: Bool
    let sampleSizeContribution: Int
    let distinctDayCountContribution: Int
    let distinctRideCountContribution: Int
    let recentSampleSizeContribution: Int
}

struct AggregateReliabilityPrior: Codable, Sendable {
    let applied: Bool
    let role: String
    let provenance: AggregateReliabilityProvenance
    let meanOutageMinutes: Int?
    let aggregateOutageCount: Int
    let operatingDays: Int
    let availabilityPercent: Double?
    let timeScale: Double
    let totalWeight: Double
    let pointCount: Int
    let matchKind: String?
    let sourceRideName: String?
    let exposure: String
    let eventLevel: Bool
    let evidenceCount: Int
    let evidenceAccounting: AggregateReliabilityEvidenceAccounting
}

struct ForecastReliability: Codable, Sendable {
    let status: String
    let showRange: Bool
    let showBestGuess: Bool
    let reason: String
}

struct ReopeningEstimate: Codable, Sendable {
    let modelVersion: String
    let estimateKind: String
    let windowStart: Date
    let historicalMedianAt: Date
    let windowEnd: Date
    let evidenceStrength: String
    let sampleSize: Int
    let effectiveSampleSize: Double
    let distinctDayCount: Int
    let recentSampleSize: Int
    let distinctRideCount: Int
    let distinctParkCount: Int
    let censoredSampleSize: Int
    let sameRideSampleSize: Int?
    let sameRideCensoredSampleSize: Int?
    let basis: String
    let intervalCoverage: String
    let method: String
    let priorVersion: String
    let startQuality: String
    let closureSignal: String
    let priorTrainedThrough: String?
    let survivalEstimator: String?
    let calibration: ForecastCalibration?
    let historyProvenance: ReopenHistoryProvenance?
    let historicalPrior: FrozenHistoricalPriorMetadata?
    let aggregateReliabilityPrior: AggregateReliabilityPrior?
    let weatherClearanceEarliestAt: Date?
    let weatherClearanceAt: Date?
    let weatherClearanceVerifiedAt: Date?
    let radarProjectedClearAt: Date?
    let radarTrend: String?
    let weatherRestartLagSampleSize: Int?
    let weatherClosureSampleSize: Int?
    let issuedAt: Date
    let anchorAt: Date
    let episodeAnchorAt: Date
    let forecastPhase: ForecastPhase
    let lateMinutes: Int
    let revision: Int
    let revisionReason: String
    let lockedForOutage: Bool
    var reliability: ForecastReliability? = nil
}

struct ProviderAttractionHours: Codable, Sendable {
    let type: String?
    let startTime: Date
    let endTime: Date?
}

struct ThemeParksWikiRideStatus: Codable, Sendable {
    var operatingHours: [ProviderAttractionHours]? = nil
    let entityId: String
    let entityName: String
    let status: String
    let sourceUpdatedAt: Date
    let matchedBy: String
    let sourceAgeSeconds: Int?
}

struct ScheduledClosureSource: Codable, Sendable {
    let name: String
    let url: String
    let verifiedAt: Date?
}

struct ScheduledClosure: Codable, Sendable {
    let parkId: Int
    let rideId: Int
    let rideName: String
    let startsAt: Date
    let expectedReopenAt: Date?
    let source: ScheduledClosureSource
    let reason: String
}

struct AttractionOperatingWindow: Codable, Sendable, Equatable {
    let state: String
    let openingTime: String?
    let closingTime: String?
    let label: String
    let source: String
    let confidence: String
    let observedDays: Int
}

struct DelayEvidence: Codable, Sendable {
    let label: String
    let phase: String
    let weatherOriginSignal: String?
    let weatherOriginAt: Date?
    let closureTimingMatched: Bool
    let correlatedClosureCount: Int
    let minimumCorrelatedClosures: Int
    let closureWaveExposedRideCount: Int?
    let closureWaveRecentClosureCount: Int?
    let closureWaveOpenRideCount: Int?
    let closureWaveUnknownRideCount: Int?
    let closureWaveIgnoredOpenOutliers: Int?
    let matchedLightningAt: Date?
    let lastLightningDensityAt: Date?
    let nearestPositiveSampleMiles: Double?
    let lightningPeriods30Minutes: Int
    let observedThunderstorm: Bool?
    let forecastThunderstorm: Bool?
    let convectiveAlertLevel: String?
    let clearanceAt: Date?
    let clearanceVerifiedAt: Date?
    let clearanceState: String?
    let clearMinutes: Int?
    let requiredClearMinutes: Int?
    let radarTrend: String?
    let radarReflectivityDbz: Double?
    let radarProjectedClearAt: Date?
}

struct AttractionLocation: Codable, Sendable, Equatable {
    let latitude: Double
    let longitude: Double
}

struct RideDetailFact: Codable, Identifiable, Sendable {
    let id: String
    let label: String
    let value: String
    let sourceId: String
}

struct RideDetailSource: Codable, Identifiable, Sendable {
    let id: String
    let label: String
    let url: URL
}

struct RidePhoto: Codable, Sendable {
    let url: URL
    let sourceURL: URL
    let credit: String
    let license: String
    let licenseURL: URL
    let alt: String
}

struct RideDetails: Codable, Sendable {
    var photo: RidePhoto? = nil
    let reviewedAt: String
    let facts: [RideDetailFact]
    let sources: [RideDetailSource]
    let unverified: [String]
    let riderNote: String
}

struct LiveRide: Codable, Identifiable, Sendable {
    var statusObservedAt: Date? = nil
    var statusEpisodeAnchorAt: Date? = nil
    let id: Int
    let name: String
    let land: String
    var status: RideStatus
    var isOpen: Bool
    var waitTime: Int?
    let lastUpdated: Date?
    var downSince: Date?
    var elapsedDownMinutes: Int?
    var minimumDownMinutes: Int?
    var estimate: ReopeningEstimate?
    var estimateReason: String?
    let delayType: String?
    var weatherHoldActive: Bool? = nil
    var details: RideDetails? = nil
    let delayEvidence: DelayEvidence?
    let weatherExposure: String
    let radarEligible: Bool
    let radarCategory: String
    var reopenPending: Bool
    let trend: [Int]
    let location: AttractionLocation?
    let themeParksWikiStatus: ThemeParksWikiRideStatus?
    let waitTimeSource: String?
    let scheduledClosure: ScheduledClosure?
    let statusAgreement: String?
    let statusProvenance: String?
    let statusComparisonReason: String?
    let scheduledReason: String?
    var operatingWindow: AttractionOperatingWindow?
    /// Real timestamped API observations; legacy trend values have no timestamps.
    var waitHistory: [WaitHistorySample]? = nil

    var isRadarDown: Bool {
        status == .down && radarEligible
    }

    var recentTypicalWait: Int? {
        let values = trend.filter { $0 >= 0 }.sorted()
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return Int(((Double(values[middle - 1]) + Double(values[middle])) / 2.0).rounded())
        }
        return values[middle]
    }
}

struct LiveShowtime: Codable, Sendable, Identifiable {
    let type: String?
    let startTime: Date
    let endTime: Date?

    var id: String {
        "\(startTime.timeIntervalSince1970)-\(endTime?.timeIntervalSince1970 ?? 0)-\(type ?? "")"
    }
}

struct LiveShow: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let status: String?
    let showtimes: [LiveShowtime]
    let nextShowAt: Date?
    let nextShowEndAt: Date?
    let nextShowType: String?
    let sourceUpdatedAt: Date
}

struct ShowScheduleSource: Codable, Sendable {
    let name: String
    let label: String
    let url: String
    let fetchedAt: Date?
    let sourceUpdatedAt: Date?
    let scheduleDate: String?
    let stale: Bool
    let warning: String?
    let updateCadenceMinutes: Int
}

struct ParkMetrics: Codable, Sendable {
    let openCount: Int
    let downCount: Int
    let scheduledCount: Int?
    let averageWait: Int?
    let reportingCount: Int
}

struct SourceDetails: Codable, Sendable {
    let name: String
    let url: String
    let updateCadenceMinutes: Int
}

struct ProviderSourceTimes: Codable, Sendable {
    let queueTimes: Date?
    let themeParksWiki: Date?
}

struct ThemeParksWikiAttribution: Codable, Sendable {
    let name: String
    let label: String
    let url: String
    let termsUrl: String
    let updateCadenceMinutes: Int
}

struct ParkHoursPeriod: Codable, Sendable {
    let openingTime: Date
    let closingTime: Date
    let label: String
    let type: String
}

struct ParkHoursSnapshot: Codable, Sendable {
    let parkId: Int
    let parkName: String
    let timezone: String
    let date: String
    let fetchedAt: Date
    let sourceUpdatedAt: Date?
    let cacheAgeSeconds: Int
    let cacheHit: Bool
    let stale: Bool
    let warning: String?
    let regular: ParkHoursPeriod?
    let earlyEntry: ParkHoursPeriod?
    let source: ThemeParksWikiAttribution
}

struct ThemeParksWikiUnmatchedRide: Codable, Sendable {
    let rideId: Int
    let rideName: String
    let normalizedName: String
    let reason: String
}

struct ThemeParksWikiSummary: Codable, Sendable {
    let available: Bool
    let cacheStale: Bool
    let fetchedAt: Date?
    let sourceUpdatedAt: Date?
    let cacheAgeSeconds: Int?
    let cacheHit: Bool?
    let matchedRideCount: Int
    let unmatchedRides: [ThemeParksWikiUnmatchedRide]
    let showCount: Int?
    let showsWithUpcomingTimes: Int?
    let showSourceUpdatedAt: Date?
    let warning: String?
    let role: String
    let statusSemantics: String
    let usedForWaitTimes: Bool
    let usedForOperationalEligibility: Bool?
    let usedForOperationalTraining: Bool
    let source: ThemeParksWikiAttribution
}

struct WeatherLocation: Codable, Sendable {
    let parkId: Int
    let parkName: String
    let latitude: Double
    let longitude: Double
}

struct WeatherAlert: Codable, Identifiable, Sendable {
    let event: String
    let severity: String?
    let endsAt: Date?

    var id: String { "\(event)-\(endsAt?.timeIntervalSince1970 ?? 0)" }
}

struct NWSDetails: Codable, Sendable {
    let status: String
    let observedAt: Date?
    let forecastUpdatedAt: Date?
    let alertsCheckedAt: Date?
    let observationStatus: String
    let forecastStatus: String
    let alertsStatus: String
    let stationName: String?
    let url: String
}

struct LightningDetails: Codable, Sendable {
    var sourceKind: String? = nil
    var glm: GlmDetails? = nil
    let status: String
    let checkedAt: Date?
    let densityDetectedAt: [Date]
    let parkCoordinateDensityDetectedAt: [Date]
    let lastDensityDetectedAt: Date?
    let nearestPositiveSampleMiles: Double?
    let sampleRadiusMiles: Double
    let periodsDetected30Minutes: Int
    let maximumStrikeDensity: Double?
    let coverageMinutes: Int
    let sourceUpdatedAt: Date?
    let url: String
    let clearSinceAt: Date?
    let clearMinutes: Int?
    let requiredClearMinutes: Int?
    let clearanceAt: Date?
    let clearanceVerifiedAt: Date?
    let clearanceState: String?
    let completeFrames30Minutes: Int?
    let gridResolutionMiles: Double?
}

struct GlmDetails: Codable, Sendable {
    let satellite: Int
    let status: String
    let checkedAt: Date?
    let observedThrough: Date?
    let lastDetectedAt: Date?
    let targetAt: Date?
    let state: String
    let clearMinutes: Int
    let boundaryUncertain: Bool
}

struct RadarDetails: Codable, Sendable {
    let status: String
    let checkedAt: Date?
    let sourceUpdatedAt: Date?
    let sampleRadiusMiles: Double
    let maximumReflectivityDbz: Double?
    let trend: String
    let trendDbzPerMinute: Double?
    let projectedClearAt: Date?
    let coverageMinutes: Int
    let url: String
}

struct WeatherSnapshot: Codable, Sendable {
    let location: WeatherLocation
    let fetchedAt: Date
    let condition: String?
    let temperatureF: Double?
    let windMph: Double?
    let precipitationChance: Double?
    let observedThunderstorm: Bool?
    let forecastThunderstorm: Bool?
    let forecastThunderstormUntil: Date?
    let convectiveAlertLevel: String?
    let activeAlerts: [WeatherAlert]
    let nws: NWSDetails
    let lightning: LightningDetails
    let radar: RadarDetails?
    /// Absent on older servers. The experiment remains server-controlled and off by default.
    var lightningDeparture: LightningDepartureEstimate? = nil
}

struct HorrorNight: Codable, Sendable {
    let date: String
    let modeStartsAt: Date
    let openingTime: Date
    let closingTime: Date

    func isActive(at now: Date) -> Bool {
        now >= modeStartsAt && now < closingTime
    }
}

struct HorrorHouse: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let status: String
    let waitTime: Int?
    let sourceUpdatedAt: Date
}

struct HorrorNightSnapshot: Codable, Sendable {
    let night: HorrorNight
    let scheduleCheckedAt: Date
    let fetchedAt: Date
    let houses: [HorrorHouse]

    func isActive(at now: Date) -> Bool {
        night.isActive(at: now) && now.timeIntervalSince(scheduleCheckedAt) < 36 * 60 * 60
    }
}

struct LiveParkSnapshot: Codable, Sendable {
    let parkId: Int
    let park: ParkMetadata
    let parkActive: Bool
    let feedHealthy: Bool
    let fetchedAt: Date
    let sourceUpdatedAt: Date?
    let sourceUpdatedAtByProvider: ProviderSourceTimes?
    let cacheAgeSeconds: Int
    var rides: [LiveRide]
    var shows: [LiveShow]? = nil
    var nextShowAt: Date? = nil
    var nextShowName: String? = nil
    var showsSourceUpdatedAt: Date? = nil
    var showsSource: ShowScheduleSource? = nil
    var parkHours: ParkHoursSnapshot? = nil
    var halloweenHorrorNights: HorrorNightSnapshot? = nil
    var metrics: ParkMetrics
    let source: SourceDetails
    let themeParksWiki: ThemeParksWikiSummary?
    let weather: WeatherSnapshot

    var queueTimesUpdatedAt: Date? {
        sourceUpdatedAtByProvider?.queueTimes ?? sourceUpdatedAt
    }

    var themeParksWikiUpdatedAt: Date? {
        sourceUpdatedAtByProvider?.themeParksWiki ?? themeParksWiki?.sourceUpdatedAt
    }

    /// Current wait/status source version. ThemeParks.wiki is PIVOT's live
    /// provider; the other fields remain decode fallbacks for older snapshots.
    var waitStatusUpdatedAt: Date? {
        themeParksWikiUpdatedAt
            ?? sourceUpdatedAt
            ?? sourceUpdatedAtByProvider?.queueTimes
    }

    var showList: [LiveShow] {
        shows ?? []
    }
}

struct APIErrorEnvelope: Codable, Sendable {
    let error: String
}

struct ParkHoursEnvelope: Codable, Sendable {
    let parkId: Int
    let parkHours: ParkHoursSnapshot?
}

enum RideListFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case open = "Open"
    case radar = "Radar"

    var id: String { rawValue }
}

enum RideSort: String, CaseIterable, Identifiable {
    static let storageKey = "pivot.rideSort"
    case status = "Status"
    case shortest = "Shortest"
    case longest = "Longest"
    case name = "Name"

    var id: String { rawValue }
}


/// A posted wait observation, never a forecast or a fabricated trend timestamp.
struct WaitHistorySample: Codable, Sendable, Equatable, Identifiable {
    let observedAt: Date
    let waitTime: Double
    var id: Date { observedAt }
}

/// Exact optional weather.lightningDeparture wire contract. Raw strings retain
/// forward compatibility; the view only displays numbers for the known range state.
struct LightningDepartureEstimate: Codable, Sendable {
    let status: String
    let reason: String
    let label: String
    let algorithmVersion: String
    let calibration: String
    let issuedAt: Date
    let radarObservedAt: Date?
    let lightningIntervalEndAt: Date?
    let earliestDepartureAt: Date?
    let latestDepartureAt: Date?
    let diagnostics: LightningDepartureDiagnostics
    let frameCount: Int
    let frameTimes: [Date]
    let trackedRadiusMiles: Double
    let watchRadiusMiles: Double?
    let motion: LightningDepartureMotion?
    let source: LightningDepartureSource
    let limitations: String
}

struct LightningDepartureDiagnostics: Codable, Sendable {
    let radarAgeMinutes: Double?
    let lightningAgeMinutes: Double?
    let footprintPixelCounts: [Int]
    let componentCounts: [Int]
    let componentPixelCounts: [[Int]]
    let unknownRadarCells: [Int]
    let unknownLightningCells: Int?
    let pairOverlap: [Double]
    let pairSpeedsMph: [Double]
    let densityIntervalMinutes: Int
    let reflectivityUnits: String
}

struct LightningDepartureMotion: Codable, Sendable {
    let eastMilesPerMinute: Double
    let northMilesPerMinute: Double
    let speedMph: Double
    let bearingDegrees: Double
    let agreement: String
}

struct LightningDepartureSource: Codable, Sendable {
    let radar: String
    let lightning: String
}


/// Protect native consumers of older server payloads before counts, Radar,
/// notifications, planning or Live Activities see them. This changes a local
/// presentation copy only; server forecasts/outcomes are never rewritten.
enum NativeOpeningEligibility {
    private static let reviewedStart = Date(timeIntervalSince1970: 1792296000) // Oct 18 00:00 EDT
    private static let reviewedEnd = Date(timeIntervalSince1970: 1792382400)
    private static let regularOpening = Date(timeIntervalSince1970: 1792328400) // 09:00 EDT
    private static let regularClosing = Date(timeIntervalSince1970: 1792371600)
    private static let regularOnly: Set<Int> = [155, 156, 466]
    private static let earlyRides: Set<Int> = [159, 10916, 158, 160, 16467, 153, 2679, 10914]

    static func applying(to raw: LiveParkSnapshot) -> LiveParkSnapshot {
        guard raw.parkId == 5, raw.fetchedAt >= reviewedStart else { return raw }
        var result = raw
        let now = raw.fetchedAt // Never make a saved response fresh using device time.
        let reviewedDate = now < reviewedEnd
        result.rides = raw.rides.map { original in
            guard original.status == .down else { return original }
            var ride = original
            var opening: Date?
            var closing: Date?
            var scheduled = false
            var label = "Attraction opening hours unverified"
            if reviewedDate && regularOnly.contains(ride.id) {
                opening = regularOpening; closing = regularClosing
                scheduled = now < regularOpening || now >= regularClosing
                label = now < regularOpening ? "Opens at 9:00 AM" : "Closed for the scheduled day"
            } else if let period = original.themeParksWikiStatus?.operatingHours?
                .filter({ $0.type == "OPERATING" && $0.endTime != nil && $0.endTime! > $0.startTime })
                .sorted(by: { $0.startTime < $1.startTime })
                .first(where: { ($0.startTime <= now && now < $0.endTime!) || ($0.startTime > now && $0.startTime.timeIntervalSince(now) <= 36 * 3600) }) {
                opening = period.startTime; closing = period.endTime
                scheduled = now < period.startTime
                let formatter = DateFormatter()
                formatter.timeZone = TimeZone(identifier: "America/New_York")
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "h:mm a"
                label = "Opens at \(formatter.string(from: period.startTime))"
            } else if let hours = raw.parkHours, !hours.stale, let regular = hours.regular,
                      regular.closingTime > regular.openingTime {
                opening = regular.openingTime; closing = regular.closingTime
                if reviewedDate && earlyRides.contains(ride.id), let early = hours.earlyEntry,
                   early.openingTime < regular.openingTime {
                    opening = early.openingTime
                }
                if now < opening! {
                    label = "Early-entry eligibility unverified · awaiting regular opening"
                }
            }
            let source = original.themeParksWikiStatus?.sourceUpdatedAt ?? original.lastUpdated
            let withinSession = opening != nil && closing != nil && now >= opening! && now < closing!
            // An old preopening version does not become downtime just because
            // an API poll ingested it after opening. Do not invent OPEN at 09:00.
            let observedInSession = withinSession && source != nil && source! >= opening!
            if observedInSession && !scheduled {
                // A newer provider version cannot validate an older session's
                // forecast or overnight display timer. Preserve the raw copy.
                if let estimate = ride.estimate,
                   estimate.episodeAnchorAt < opening! || estimate.issuedAt < opening! {
                    ride.estimate = nil
                    ride.estimateReason = "Opening delay · awaiting a forecast for this operating session"
                }
                if let downSince = ride.downSince, downSince < opening! {
                    ride.downSince = nil; ride.elapsedDownMinutes = nil; ride.minimumDownMinutes = nil
                }
                return ride
            }
            if withinSession { label = "Opening status unverified · waiting for an operating-session update" }
            ride.status = scheduled ? .scheduled : .stale
            ride.isOpen = false; ride.waitTime = nil; ride.reopenPending = false
            ride.estimate = nil; ride.estimateReason = label
            ride.downSince = nil; ride.elapsedDownMinutes = nil; ride.minimumDownMinutes = nil
            ride.statusEpisodeAnchorAt = nil
            if scheduled {
                ride.operatingWindow = AttractionOperatingWindow(state: now < opening! ? "BEFORE_OPEN" : "AFTER_CLOSE",
                    openingTime: nil, closingTime: nil, label: label, source: "OFFICIAL_DATED_HOURS", confidence: "HIGH", observedDays: 0)
            }
            return ride
        }
        return result
    }
}

/// Current presentation exclusion, independent of provider status or age.
/// Historical payloads/storage stay intact; only the active local copy changes.
/// TouringPlans confirms August 16, 2026 was the final operating day:
/// https://touringplans.com/universal-studios-florida/attractions/fast-and-furious-supercharged
enum NativeRetiredAttractions {
    static func excludes(parkID: Int, rideID: Int, name: String, entityID: String? = nil) -> Bool {
        guard parkID == FloridaPark.universalStudiosFlorida.rawValue else { return false }
        if rideID == 6038 || entityID == "6a3ffac7-bef4-4a22-8ba6-f2963aac7f70" { return true }
        // A provider rename or remapping must not revive the same retired ride.
        let normalized = name.lowercased().replacingOccurrences(of: "&amp;", with: "and")
            .replacingOccurrences(of: "&", with: "and")
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined()
        return normalized == "fastandfurioussupercharged" || normalized == "fastandfurioussuperchargedsinglerider"
    }

    static func applying(to raw: LiveParkSnapshot) -> LiveParkSnapshot {
        var result = raw
        result.rides = raw.rides.filter {
            !excludes(parkID: raw.parkId, rideID: $0.id, name: $0.name, entityID: $0.themeParksWikiStatus?.entityId)
        }
        guard result.rides.count != raw.rides.count else { return raw }
        let waits = result.rides.filter { $0.status == .open }.compactMap(\.waitTime)
        result.metrics = ParkMetrics(openCount: result.rides.filter { $0.status == .open }.count,
            downCount: result.rides.filter { $0.status == .down }.count,
            scheduledCount: result.rides.filter { $0.status == .scheduled }.count,
            averageWait: waits.isEmpty ? nil : Int((Double(waits.reduce(0, +)) / Double(waits.count)).rounded()),
            reportingCount: result.rides.filter { $0.status != .stale }.count)
        return result
    }
}
