import Foundation
import CoreFoundation

enum NativeHorrorHouseFeed {
    static let parkEntityID = "eb3f4560-2383-4a36-9152-6b3e5ed6bc57"
    static let url = URL(string: "https://api.themeparks.wiki/v1/entity/\(parkEntityID)/live")!

    static func houses(from data: Data, observedAt: Date) throws -> [HorrorHouse] {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["id"] as? String == parkEntityID,
              let rows = payload["liveData"] as? [[String: Any]] else { throw PivotAPIError.invalidResponse }
        var seen = Set<String>()
        var houses: [HorrorHouse] = []
        for row in rows {
            guard row["entityType"] as? String == "ATTRACTION",
                  let externalID = row["externalId"] as? String,
                  externalID.hasPrefix("uor.usf.rides.hhn_"),
                  row["parkId"] == nil || row["parkId"] as? String == parkEntityID,
                  let rawID = row["id"] as? String, let rawName = row["name"] as? String else { continue }
            let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !name.isEmpty else { continue }
            guard seen.insert(id).inserted else { throw PivotAPIError.invalidResponse }
            guard let timestamp = row["lastUpdated"] as? String,
                  let encoded = try? JSONEncoder().encode(timestamp),
                  let sourceAt = try? PivotAPIClient.makeDecoder().decode(Date.self, from: encoded) else { continue }
            let sourceUsable = HorrorNightPresentation.sourceVersionIsUsable(sourceAt, now: observedAt)
            let status: String
            switch sourceUsable ? row["status"] as? String : nil {
            case "OPERATING": status = "OPEN"
            case "DOWN": status = "DOWN"
            case "CLOSED", "REFURBISHMENT": status = "CLOSED"
            default: status = "UNAVAILABLE"
            }
            let queue = row["queue"] as? [String: Any]
            let standby = queue?["STANDBY"] as? [String: Any]
            let paid = queue?["PAID_STANDBY"] as? [String: Any]
            let values = [standby?["waitTime"], paid?["waitTime"], row["waitTime"]]
            let rawWait = values.compactMap { $0 }.first { !($0 is NSNull) }
            var wait: Int?
            if status == "OPEN", let value = rawWait as? NSNumber,
               CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite,
               let minutes = Int(exactly: value.doubleValue), minutes >= 0 { wait = minutes }
            houses.append(HorrorHouse(id: id, name: name, status: status, waitTime: wait, sourceUpdatedAt: sourceAt))
        }
        return houses
    }
}

enum PivotAPIError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case server(status: Int, message: String)
    case wrongPark(expected: Int, received: Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "PIVOT could not create the live-data request."
        case .invalidResponse:
            "PIVOT received an invalid response."
        case .server(_, let message):
            message
        case .wrongPark:
            "A late response from another park was ignored."
        }
    }
}
actor PivotAPIClient {
    static let shared = PivotAPIClient()

    private let baseURL: URL
    private let session: URLSession
    private let horrorHouseURL: URL
    private var horrorHouseObservation: (at: Date, houses: [HorrorHouse])?
    private var horrorHouseAttemptAt: Date?

    init(
        baseURL: URL = URL(string: "https://pivot-reopen-radar.akpotato.chatgpt.site")!,
        session: URLSession = .shared,
        horrorHouseURL: URL = NativeHorrorHouseFeed.url
    ) {
        self.baseURL = baseURL
        self.session = session
        self.horrorHouseURL = horrorHouseURL
    }

    func snapshot(for park: FloridaPark) async throws -> LiveParkSnapshot {
        let endpoint = baseURL.appendingPathComponent("api/live")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PivotAPIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "park", value: String(park.rawValue))]
        guard let url = components.url else { throw PivotAPIError.invalidURL }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("PIVOT-iOS/1.3", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PivotAPIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw PivotAPIError.server(
                status: http.statusCode,
                message: envelope?.error ?? "Live ride data is temporarily unavailable."
            )
        }

        var snapshot = try Self.makeDecoder().decode(LiveParkSnapshot.self, from: data)
        guard snapshot.parkId == park.rawValue else {
            throw PivotAPIError.wrongPark(expected: park.rawValue, received: snapshot.parkId)
        }
        if park == .universalStudiosFlorida, let event = snapshot.halloweenHorrorNights {
            snapshot.halloweenHorrorNights = await refreshingHorrorHouses(event, now: Date())
        }
        return NativeOpeningEligibility.applying(to: NativeRetiredAttractions.applying(to: snapshot))
    }

    private func refreshingHorrorHouses(_ event: HorrorNightSnapshot, now: Date) async -> HorrorNightSnapshot {
        guard HorrorNightPresentation.phase(for: event, at: now) != .hidden,
              now >= event.night.openingTime else { return event }
        let needsObservation = !HorrorNightPresentation.isFresh(event.fetchedAt, now: now, maximumAge: 900) ||
            event.houses.isEmpty || event.houses.contains {
                !HorrorNightPresentation.isFresh($0.sourceUpdatedAt, now: now, maximumAge: 900) ||
                    ($0.status == "OPEN" && $0.waitTime == nil) || $0.status == "UNAVAILABLE"
            }
        guard needsObservation else { return event }
        if let observation = horrorHouseObservation,
           HorrorNightPresentation.isFresh(observation.at, now: now, maximumAge: 60) {
            return HorrorNightSnapshot(night: event.night, scheduleCheckedAt: event.scheduleCheckedAt,
                                       fetchedAt: observation.at, houses: observation.houses)
        }
        // Bound provider requests, including retries, across rapid foreground polls.
        if let attempt = horrorHouseAttemptAt, now.timeIntervalSince(attempt) >= 0,
           now.timeIntervalSince(attempt) < 30 { return event }
        horrorHouseAttemptAt = now
        var request = URLRequest(url: horrorHouseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return event }
            let observedAt = Date()
            let houses = try NativeHorrorHouseFeed.houses(from: data, observedAt: observedAt)
            horrorHouseObservation = (observedAt, houses)
            return HorrorNightSnapshot(night: event.night, scheduleCheckedAt: event.scheduleCheckedAt,
                                       fetchedAt: observedAt, houses: houses)
        } catch {
            // Preserve the server observation's original age and health on failure.
            return event
        }
    }

    func parkHours(for park: FloridaPark) async throws -> ParkHoursSnapshot? {
        let endpoint = baseURL.appendingPathComponent("api/hours")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PivotAPIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "park", value: String(park.rawValue))]
        guard let url = components.url else { throw PivotAPIError.invalidURL }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("PIVOT-iOS/1.3", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PivotAPIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw PivotAPIError.server(
                status: http.statusCode,
                message: envelope?.error ?? "Park hours are temporarily unavailable."
            )
        }

        let envelope = try Self.makeDecoder().decode(ParkHoursEnvelope.self, from: data)
        guard envelope.parkId == park.rawValue else {
            throw PivotAPIError.wrongPark(expected: park.rawValue, received: envelope.parkId)
        }
        return envelope.parkHours
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }

            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) { return date }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported ISO-8601 date: \(value)"
            )
        }
        return decoder
    }
}
