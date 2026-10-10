import Foundation

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

    init(
        baseURL: URL = URL(string: "https://pivot-reopen-radar.akpotato.chatgpt.site")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
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

        let snapshot = try Self.makeDecoder().decode(LiveParkSnapshot.self, from: data)
        guard snapshot.parkId == park.rawValue else {
            throw PivotAPIError.wrongPark(expected: park.rawValue, received: snapshot.parkId)
        }
        return snapshot
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
