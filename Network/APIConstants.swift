import Foundation

enum APIConstants {

    // ✅ Railway Backend Base URL
    static let baseURL = "https://web-production-0b80c.up.railway.app"
    


    // MARK: - Resume
    static let uploadResume = "\(baseURL)/resume/upload"
    static let optimizeResume = "\(baseURL)/resume/optimize"
    static let downloadResume = "\(baseURL)/resume/download"

    // MARK: - Jobs
    static let jobsFromResume = "\(baseURL)/jobs/from-resume"
    static let jobsMatch = "\(baseURL)/jobs/match"
}

