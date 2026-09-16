import Foundation

protocol JournalAPI: AnyObject {
    func openSession() async throws -> SessionResponse
    func records(month: String) async throws -> DiaryResponse
    func save(date: String, outcome: Outcome, note: String) async throws
    func delete(date: String) async throws
    func setParticipation(_ participating: Bool) async throws -> Profile
    func setAlias(_ alias: String) async throws -> Profile
    func deleteAccount() async throws
}

enum APIClientError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidAddress: "服务端地址无效。"
        case .invalidResponse: "服务器返回了无法识别的数据。"
        case .server(let message): message
        }
    }
}

final class APIClient: JournalAPI, @unchecked Sendable {
    static let shared = APIClient()
    private let encoder = JSONEncoder()
    private let session: URLSession
    private let configuredBaseURL: URL?

    private var baseURL: URL? {
        if let configuredBaseURL { return configuredBaseURL }
        let configured = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
        return URL(string: configured ?? "http://127.0.0.1:3000/api")
    }

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = true
        configuration.httpCookieStorage = .shared
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        session = URLSession(configuration: configuration)
        configuredBaseURL = nil
    }

    init(baseURL: URL, session: URLSession) {
        configuredBaseURL = baseURL
        self.session = session
    }

    private func request<Response: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> Response {
        guard let baseURL, let url = URL(string: baseURL.absoluteString + "/" + path) else {
            throw APIClientError.invalidAddress
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-Journal-Request")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        let decoder = JSONDecoder()
        guard 200..<300 ~= http.statusCode else {
            let message = (try? decoder.decode(ErrorResponse.self, from: data).error) ?? "操作失败，请稍后重试。"
            throw APIClientError.server(message)
        }
        guard let decoded = try? decoder.decode(Response.self, from: data) else {
            throw APIClientError.invalidResponse
        }
        return decoded
    }

    func openSession() async throws -> SessionResponse {
        try await request("session", method: "POST", body: try encoder.encode([String: String]()))
    }

    func records(month: String) async throws -> DiaryResponse {
        try await request("records?month=\(month)")
    }

    func save(date: String, outcome: Outcome, note: String = "") async throws {
        struct SaveBody: Encodable { let outcome: Outcome; let note: String }
        let result: EmptyResponse = try await request("records/\(date)", method: "PUT", body: try encoder.encode(SaveBody(outcome: outcome, note: note)))
        guard result.ok else { throw APIClientError.invalidResponse }
    }

    func delete(date: String) async throws {
        let result: EmptyResponse = try await request("records/\(date)", method: "DELETE", body: try encoder.encode([String: String]()))
        guard result.ok else { throw APIClientError.invalidResponse }
    }

    func ranking(metric: Outcome, period: RankingPeriod) async throws -> RankingResponse {
        try await request("leaderboard?metric=\(metric.rawValue)&period=\(period.rawValue)")
    }

    func setParticipation(_ participating: Bool) async throws -> Profile {
        let response: ProfileResponse = try await request("profile", method: "PATCH", body: try encoder.encode(["participating": participating]))
        return response.profile
    }

    func setAlias(_ alias: String) async throws -> Profile {
        let response: ProfileResponse = try await request("profile", method: "PATCH", body: try encoder.encode(["alias": alias]))
        return response.profile
    }

    func deleteAccount() async throws {
        let result: EmptyResponse = try await request("account", method: "DELETE", body: try encoder.encode(["confirmation": "删除"]))
        guard result.ok else { throw APIClientError.invalidResponse }
    }
}
