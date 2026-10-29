import Foundation

// MARK: - Errors

enum JobAPIError: LocalizedError {
    case offline
    case timedOut
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .offline:
            return "You're offline. Check your connection and try again."
        case .timedOut:
            return "The server is taking too long to respond. Please try again."
        case .server(let message):
            return message
        case .invalidResponse:
            return "We couldn't read the job results. Please try again."
        }
    }

    static func from(_ error: Error) -> JobAPIError {
        if let apiError = error as? JobAPIError { return apiError }

        switch (error as? URLError)?.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .offline
        case .timedOut:
            return .timedOut
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return .server("Can't reach GradHire's server right now. Please try again in a moment.")
        default:
            return .server("Could not load jobs. Please try again.")
        }
    }
}

// MARK: - Response Models

struct NewGradJobsPage: Decodable {
    let jobs: [Job]
    let page: Int
    let hasMore: Bool
    let total: Int? // older backends don't send it
}

// MARK: - Service

final class JobAPIService {

    static let shared = JobAPIService()
    private init() {}

    // 60s per request / 90s total: the free-tier backend can take about a
    // minute to wake up after being idle.
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 90
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    // MARK: - Fetch Jobs From Resume (Multipart)

    /// `account` (resume id and session token) is sent for signed-in users
    /// whose resume is saved to their account, so the matches are stored.
    func fetchJobsFromResume(
        pdfData fileData: Data,
        country: String = "in",
        account: (resumeId: UUID, accessToken: String)? = nil
    ) async throws -> [Job] {

        guard let url = URL(string: "\(APIConstants.jobsFromResume)?country=\(country)") else {
            throw JobAPIError.invalidResponse
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        guard !fileData.isEmpty else {
            throw JobAPIError.server("Couldn't read your resume file. Please upload it again.")
        }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"resume.pdf\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: application/pdf\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        if let account {
            body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"resume_id\"\r\n\r\n".data(using: .utf8)!)
            body.append(account.resumeId.uuidString.lowercased().data(using: .utf8)!)
            request.setValue("Bearer \(account.accessToken)", forHTTPHeaderField: "Authorization")
        }
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        return try await send(request, as: [Job].self)
    }

    // MARK: - Fetch All New Grad Jobs (Paginated)

    func fetchNewGradJobs(
        country: String = "in",
        page: Int
    ) async throws -> NewGradJobsPage {

        guard let url = URL(string: "\(APIConstants.newGradJobs)?country=\(country)&page=\(page)") else {
            throw JobAPIError.invalidResponse
        }

        return try await send(URLRequest(url: url), as: NewGradJobsPage.self)
    }

    // MARK: - Shared Request Handling

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw JobAPIError.from(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw JobAPIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            // Forward FastAPI's "detail" message when it's a plain string
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = json["detail"] as? String {
                throw JobAPIError.server(detail)
            }
            throw JobAPIError.server("Could not load jobs (error \(http.statusCode)). Please try again.")
        }

        do {
            return try Job.decoder.decode(T.self, from: data)
        } catch {
            throw JobAPIError.invalidResponse
        }
    }
}
