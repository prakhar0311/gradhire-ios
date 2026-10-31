import Foundation

final class APIService {
    
    static let shared = APIService()
    private init() {}
    
    // MARK: - Shared Session (Production Config)
    
    // 60s per request / 90s total: the free-tier backend can take about a
    // minute to wake up after being idle.
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 90
        return URLSession(configuration: config)
    }()

    // MARK: - Server Warm-up

    /// Fire-and-forget request so a sleeping backend starts waking up while the
    /// user is still picking a file. Failures are ignored.
    func warmUpServer() async {
        guard let url = URL(string: APIConstants.baseURL) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 90
        _ = try? await session.data(for: request)
    }
    
    // MARK: - Resume Analysis (Optimize screen)

    /// Signed-in users pass their saved resume and the job, so the result is
    /// stored and reopening is instant.
    struct AnalysisAccount {
        let resumeId: UUID
        let jobId: UUID
        let accessToken: String
    }

    /// Step 1: the job's keywords, matched vs missing, the original's score,
    /// and the stored full result if this pair was optimized before.
    func analyzeResume(
        resumeText: String,
        jobDescription: String,
        account: AnalysisAccount?
    ) async throws -> AnalysisStart {
        let data = try await postAnalysis(
            to: APIConstants.resumeAnalysis, resumeText: resumeText, jobDescription: jobDescription, account: account
        )
        do {
            var start = try Self.analysisDecoder.decode(AnalysisStart.self, from: data)
            if var result = start.result {
                result.optimizedResumeJSON = Self.optimizedResumeJSON(in: data, path: ["result"])
                start = AnalysisStart(analysis: start.analysis, result: result)
            }
            return start
        } catch {
            throw JobAPIError.invalidResponse
        }
    }

    /// Step 2: rewritten bullets, the optimized resume and its score.
    func optimizeResume(
        resumeText: String,
        jobDescription: String,
        account: AnalysisAccount?
    ) async throws -> OptimizationOutcome {
        let data = try await postAnalysis(
            to: APIConstants.resumeOptimizeV2, resumeText: resumeText, jobDescription: jobDescription, account: account
        )
        do {
            var outcome = try Self.analysisDecoder.decode(OptimizationOutcome.self, from: data)
            outcome.optimizedResumeJSON = Self.optimizedResumeJSON(in: data, path: [])
            return outcome
        } catch {
            throw JobAPIError.invalidResponse
        }
    }

    /// The one-page PDF of the optimized resume. `keywords` decide which
    /// bullets and projects are kept when trimming; `include` is the user's
    /// own choice. Throws ResumeOverflowError when that choice doesn't fit.
    func renderResume(
        resumeJSON: Data,
        keywords: [String],
        include: IncludeChoice?,
        jobDescription: String? = nil
    ) async throws -> RenderedResume {
        guard let url = URL(string: APIConstants.resumeRender),
              let resume = try? JSONSerialization.jsonObject(with: resumeJSON) else {
            throw JobAPIError.invalidResponse
        }

        var body: [String: Any] = ["resume": resume, "keywords": Array(keywords.prefix(40))]
        if let include {
            body["include"] = include.json
            // Re-score exactly the PDF the user chose
            if let jobDescription { body["job_description"] = jobDescription }
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw JobAPIError.from(error)
        }

        guard let http = response as? HTTPURLResponse else { throw JobAPIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let detail = json?["detail"] as? String
            if http.statusCode == 422, json?["overflow_lines"] != nil, let detail {
                throw ResumeOverflowError(message: detail)
            }
            throw JobAPIError.server(detail ?? "Couldn't create the PDF (error \(http.statusCode)). Please try again.")
        }

        guard let header = http.value(forHTTPHeaderField: "X-Resume-Layout"),
              let layout = try? Self.analysisDecoder.decode(ResumeLayout.self, from: Data(header.utf8)),
              data.starts(with: Data("%PDF".utf8)) else {
            throw JobAPIError.invalidResponse
        }
        let score = http.value(forHTTPHeaderField: "X-Resume-Score")
            .flatMap { try? Self.analysisDecoder.decode(AnalysisScore.self, from: Data($0.utf8)) }
        return RenderedResume(pdf: data, layout: layout, score: score)
    }

    private static let analysisDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// The "optimized_resume" object, kept as raw JSON for the PDF.
    private static func optimizedResumeJSON(in data: Data, path: [String]) -> Data? {
        guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        for key in path {
            guard let next = object[key] as? [String: Any] else { return nil }
            object = next
        }
        guard let resume = object["optimized_resume"] as? [String: Any] else { return nil }
        return try? JSONSerialization.data(withJSONObject: resume)
    }

    private func postAnalysis(
        to endpoint: String,
        resumeText: String,
        jobDescription: String,
        account: AnalysisAccount?
    ) async throws -> Data {
        guard let url = URL(string: endpoint) else { throw JobAPIError.invalidResponse }

        var body: [String: Any] = [
            "resume_text": resumeText,
            "job_description": jobDescription
        ]
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let account {
            body["resume_id"] = account.resumeId.uuidString.lowercased()
            body["job_id"] = account.jobId.uuidString.lowercased()
            request.setValue("Bearer \(account.accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw JobAPIError.from(error)
        }

        guard let http = response as? HTTPURLResponse else { throw JobAPIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            // The server's own reason (rate limit, "couldn't rewrite reliably", ...)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = json["detail"] as? String {
                throw JobAPIError.server(detail)
            }
            throw JobAPIError.server("Resume analysis failed (error \(http.statusCode)). Please try again.")
        }
        return data
    }

    // MARK: - Upload Resume
    
    func uploadResume(
        pdfData: Data,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        
        guard let url = URL(string: APIConstants.uploadResume) else {
            completion(.failure(NSError(
                domain: "API",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"]
            )))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60 // allow for a backend cold start
        
        let boundary = UUID().uuidString
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        
        var body = Data()
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"resume.pdf\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: application/pdf\r\n\r\n".data(using: .utf8)!)
        
        body.append(pdfData)
        
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        session.dataTask(with: request) { data, response, error in
            
            DispatchQueue.main.async {
                
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(NSError(
                        domain: "Upload",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid response"]
                    )))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NSError(
                        domain: "Upload",
                        code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "No response"]
                    )))
                    return
                }
                
                // ✅ Forward backend error messages (clean message)
                guard (200...299).contains(http.statusCode) else {
                    
                    var message = "Upload failed"
                    
                    // Try extracting FastAPI error message
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let detail = json["detail"] as? String {
                        message = detail
                    }
                    
                    completion(.failure(NSError(
                        domain: "Server",
                        code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: message]
                    )))
                    return
                }
                
                
                do {
                    let json =
                    try JSONSerialization.jsonObject(with: data)
                    as? [String: Any]
                    
                    guard let text = json?["text"] as? String else {
                        throw NSError(
                            domain: "Upload",
                            code: -4,
                            userInfo: [NSLocalizedDescriptionKey:
                                        "Invalid server response"]
                        )
                    }
                    
                    completion(.success(text))
                    
                } catch {
                    completion(.failure(error))
                }
            }
            
        }.resume()
    }
}
