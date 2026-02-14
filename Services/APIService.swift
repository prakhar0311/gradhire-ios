import Foundation

final class APIService {

static let shared = APIService()
private init() {}

// MARK: - Shared Session (Production Config)

private lazy var session: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 45
    config.timeoutIntervalForResource = 45
    return URLSession(configuration: config)
}()

// MARK: - Optimize Resume

func optimizeResume(
    resumeText: String,
    jobTitle: String,
    jobDescription: String,
    completion: @escaping (Result<ResumeOptimizationResponse, Error>) -> Void
) {

    guard let url = URL(string: APIConstants.optimizeResume) else {
        completion(.failure(NSError(
            domain: "API",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"]
        )))
        return
    }

    let body: [String: Any] = [
        "resume_text": resumeText,
        "job_title": jobTitle,
        "job_description": jobDescription
    ]

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
    } catch {
        completion(.failure(error))
        return
    }

    session.dataTask(with: request) { data, response, error in

        DispatchQueue.main.async {

            if let error = error {
                completion(.failure(error))
                return
            }

            guard let http = response as? HTTPURLResponse else {
                completion(.failure(NSError(
                    domain: "API",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid response"]
                )))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(
                    domain: "API",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "No response from server"]
                )))
                return
            }

            // ✅ Handle server errors properly
            guard (200...299).contains(http.statusCode) else {

                let serverMessage =
                    String(data: data, encoding: .utf8)
                    ?? "Server error \(http.statusCode)"

                completion(.failure(NSError(
                    domain: "Server",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: serverMessage]
                )))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(
                    ResumeOptimizationResponse.self,
                    from: data
                )

                completion(.success(decoded))

            } catch {
                print("❌ Decode error:", error)
                print("📦 Raw response:",
                      String(data: data, encoding: .utf8) ?? "")

                completion(.failure(NSError(
                    domain: "Decode",
                    code: -4,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Optimization failed — please try again."]
                )))
            }
        }

    }.resume()
}

// MARK: - Upload Resume

func uploadResume(
    fileURL: URL,
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
    request.timeoutInterval = 20

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

    do {
        body.append(try Data(contentsOf: fileURL))
    } catch {
        completion(.failure(error))
        return
    }

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

// MARK: - Download Optimized Resume

func downloadOptimizedResume(
    resumeURL: URL,
    jobDescription: String,
    completion: @escaping (Result<URL, Error>) -> Void
) {

    if jobDescription
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty {

        completion(.failure(NSError(
            domain: "Download",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey:
                "Job description is empty"]
        )))
        return
    }

    guard let url = URL(string: APIConstants.downloadResume) else {
        completion(.failure(NSError(
            domain: "API",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey:
                "Invalid server URL"]
        )))
        return
    }

    var request = URLRequest(url: url)
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

    do {
        body.append(try Data(contentsOf: resumeURL))
    } catch {
        completion(.failure(error))
        return
    }

    body.append("\r\n".data(using: .utf8)!)

    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append(
        "Content-Disposition: form-data; name=\"job_description\"\r\n\r\n"
            .data(using: .utf8)!
    )
    body.append(jobDescription.data(using: .utf8) ?? Data())
    body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

    request.httpBody = body

    session.downloadTask(with: request) {
        tempURL, response, error in

        DispatchQueue.main.async {

            if let error = error {
                completion(.failure(error))
                return
            }

            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {

                completion(.failure(NSError(
                    domain: "Download",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Server download failed"]
                )))
                return
            }

            guard let tempURL = tempURL else {
                completion(.failure(NSError(
                    domain: "Download",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey:
                        "No file received"]
                )))
                return
            }

            let finalURL = FileManager.default
                .temporaryDirectory
                .appendingPathComponent("Optimized_Resume.pdf")

            try? FileManager.default.removeItem(at: finalURL)

            do {
                try FileManager.default.copyItem(
                    at: tempURL,
                    to: finalURL
                )
                completion(.success(finalURL))
            } catch {
                completion(.failure(error))
            }
        }

    }.resume()
}

}


