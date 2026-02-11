import Foundation

struct ResumeOptimizationResponse: Codable {
    let missingSkills: [String]
    let improvedBullets: [String]
    let atsKeywords: [String]

    enum CodingKeys: String, CodingKey {
        case missingSkills = "missing_skills"
        case improvedBullets = "improved_bullets"
        case atsKeywords = "ats_keywords"
    }
}

