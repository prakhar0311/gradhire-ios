import Foundation

final class JobAPIService {

    static let shared = JobAPIService()
    private init() {}

    // MARK: - Fetch Jobs From Resume (Multipart)
    func fetchJobsFromResume(
        fileURL: URL,
        country: String = "in",
        completion: @escaping (Result<[Job], Error>) -> Void
    ) {

        let urlString = "\(APIConstants.jobsFromResume)?country=\(country)"
        guard let url = URL(string: urlString) else {
            completion(.failure(URLError(.badURL)))
            return
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 60
        )
        request.httpMethod = "POST"

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

        // 🔐 CRITICAL: Security-scoped access (REAL DEVICE FIX)
        let canAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if canAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let fileData = try? Data(contentsOf: fileURL) else {
            completion(.failure(URLError(.fileDoesNotExist)))
            return
        }

        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in

            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.failure(URLError(.badServerResponse)))
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(URLError(.zeroByteResource)))
                }
                return
            }

            if httpResponse.statusCode >= 400 {

                var backendMessage = "Upload failed"

                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detail = json["detail"] as? String {
                    backendMessage = detail
                }

                DispatchQueue.main.async {
                    completion(.failure(NSError(
                        domain: "Backend",
                        code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: backendMessage]
                    )))
                }
                return
            }


            do {
                let jobs = try JSONDecoder().decode([Job].self, from: data)
                DispatchQueue.main.async {
                    completion(.success(jobs))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }

        }.resume()
    }
}

