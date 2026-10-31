import Foundation

// Constant URLs only; nonisolated so repositories off the main actor can read them.
nonisolated enum APIConstants {

    // ✅ Railway Backend Base URL
    static let baseURL = "https://gradhire-backend.onrender.com"
    


    // MARK: - Resume
    static let uploadResume = "\(baseURL)/resume/upload"
    static let resumeAnalysis = "\(baseURL)/resume/analysis"
    static let resumeOptimizeV2 = "\(baseURL)/resume/optimize-v2"
    static let resumeRender = "\(baseURL)/resume/render"

    // MARK: - Account
    static let deleteAccount = "\(baseURL)/account"
    static let ensureJob = "\(baseURL)/jobs/ensure"

    // MARK: - Jobs
    static let jobsFromResume = "\(baseURL)/jobs/from-resume"
    static let jobsForResume = "\(baseURL)/jobs/for-resume"
    static let newGradJobs = "\(baseURL)/jobs/new-grad"
    static let jobsMatch = "\(baseURL)/jobs/match"
}

