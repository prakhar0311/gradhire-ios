import Foundation

enum APIConstants {

    // ✅ Railway Backend Base URL
    static let baseURL = "https://gradhire-backend.onrender.com"
    


    // MARK: - Resume
    static let uploadResume = "\(baseURL)/resume/upload"
    static let optimizeResume = "\(baseURL)/resume/optimize"
    static let downloadResume = "\(baseURL)/resume/download"
    static let scoreResume = "\(baseURL)/resume/score"

    // MARK: - Jobs
    static let jobsFromResume = "\(baseURL)/jobs/from-resume"
    static let newGradJobs = "\(baseURL)/jobs/new-grad"
    static let jobsMatch = "\(baseURL)/jobs/match"
}

