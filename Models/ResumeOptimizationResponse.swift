import Foundation

struct ResumeOptimizationResponse: Codable {
    let missingSkills: [String]
    let improvedBullets: [String]
    let atsKeywords: [String]

    // Optional so an older backend (without re-scoring) still decodes
    let optimizedResumeText: String?

    /// The optimized resume exactly as returned by the backend, sent back
    /// on download so the PDF is the same resume that was scored.
    var optimizedResumeJSON: Data? = nil

    enum CodingKeys: String, CodingKey {
        case missingSkills = "missing_skills"
        case improvedBullets = "improved_bullets"
        case atsKeywords = "ats_keywords"
        case optimizedResumeText = "optimized_resume_text"
    }
}

struct ResumeScoreResponse: Decodable {
    let scores: [Int]
}
