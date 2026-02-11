import Foundation

final class APIService {

    static let shared = APIService()
    private init() {}

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

        // Extended timeout for AI calls
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 45

        let session = URLSession(configuration: config)

        session.dataTask(with: request) { data, _, error in

            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(
                        domain: "API",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey:
                            "No response from server."]
                    )))
                }
                return
            }

            do {
                let decoded = try JSONDecoder().decode(
                    ResumeOptimizationResponse.self,
                    from: data
                )

                DispatchQueue.main.async {
                    completion(.success(decoded))
                }

            } catch {
                print("❌ Decode error:", error)
                print("📦 Raw response:", String(data: data, encoding: .utf8) ?? "")

                DispatchQueue.main.async {
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
            let fileData = try Data(contentsOf: fileURL)
            body.append(fileData)
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
            return
        }

        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, _, error in

            DispatchQueue.main.async {

                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(NSError(
                        domain: "Upload",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No response"]
                    )))
                    return
                }

                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

                    guard let text = json?["text"] as? String else {
                        throw NSError(
                            domain: "Upload",
                            code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid server response"]
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

        guard let url = URL(string: APIConstants.downloadResume) else {
            completion(.failure(NSError(
                domain: "API",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"]
            )))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45

        let boundary = UUID().uuidString
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        var body = Data()

        // PDF file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"resume.pdf\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: application/pdf\r\n\r\n".data(using: .utf8)!)

        do {
            let fileData = try Data(contentsOf: resumeURL)
            body.append(fileData)
        } catch {
            completion(.failure(error))
            return
        }

        body.append("\r\n".data(using: .utf8)!)

        // Job description
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"job_description\"\r\n\r\n"
                .data(using: .utf8)!
        )
        body.append(jobDescription.data(using: .utf8) ?? Data())

        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, _, error in

            DispatchQueue.main.async {

                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(NSError(
                        domain: "Download",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey:
                            "No file received"]
                    )))
                    return
                }

                let tempURL = FileManager.default
                    .temporaryDirectory
                    .appendingPathComponent("optimized_resume.pdf")

                do {
                    try data.write(to: tempURL)
                    completion(.success(tempURL))
                } catch {
                    completion(.failure(error))
                }
            }

        }.resume()
    }
}

