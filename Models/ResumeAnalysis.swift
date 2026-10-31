import Foundation

// MARK: - Resume Analysis (Optimize screen)
//
// Everything here comes from the backend's analysis of THIS resume against
// THIS job: keywords taken from the job description, matched vs missing by
// checking the resume text, and one scoring function for both versions.

/// /resume/analysis: the job's keywords and the original resume's score.
struct ResumeAnalysis: Decodable, Equatable {
    let keywords: [AnalysisKeyword]
    let missingSkills: [MissingSkill]
    let scoreBefore: AnalysisScore

    var matchedCount: Int { keywords.filter(\.matched).count }
}

struct AnalysisKeyword: Decodable, Equatable, Hashable, Identifiable {
    let name: String
    let required: Bool
    let matched: Bool
    /// "bullet" (shown in use) or "listed" (skills or elsewhere)
    let `where`: String?

    var id: String { name }
}

struct MissingSkill: Decodable, Equatable, Identifiable {
    let name: String
    let required: Bool
    /// The job description's sentence that asks for it
    let quote: String

    var id: String { name }
}

struct AnalysisScore: Decodable, Equatable {
    let total: Int
    let breakdown: ScoreBreakdown
}

struct ScoreBreakdown: Decodable, Equatable {
    let keywordEvidence: Int
    let keywordsMatched: Int
    let keywordsTotal: Int
    let requiredPresent: Int
    let requiredTotal: Int
    let sectionsPresent: Int
    let sectionsTotal: Int
    let bulletStrength: String
    let relevance: Int
}

/// /resume/optimize-v2: the full result.
struct OptimizationOutcome: Decodable, Equatable {
    let keywords: [AnalysisKeyword]
    let missingSkills: [MissingSkill]
    let scoreBefore: AnalysisScore
    let scoreAfter: AnalysisScore
    let improved: Bool
    /// Honest note: "already covers this job well" / "you'd need: ..."
    let message: String
    let bullets: [BulletRewrite]
    let optimizedResumeText: String
    /// What the rewrite changed (older stored results don't have it)
    let changes: OutcomeChanges?
    /// "Add REST APIs and Unit Testing to reach about 79"
    let potential: ScorePotential?

    /// The optimized resume exactly as returned, sent back on download so
    /// the PDF is the same resume that was scored.
    var optimizedResumeJSON: Data?

    var analysis: ResumeAnalysis {
        ResumeAnalysis(keywords: keywords, missingSkills: missingSkills, scoreBefore: scoreBefore)
    }

    private enum CodingKeys: String, CodingKey {
        case keywords, missingSkills, scoreBefore, scoreAfter, improved, message, bullets, optimizedResumeText, changes
        case potential
    }
}

/// An honest estimate: the same scoring with these skills listed.
struct ScorePotential: Decodable, Equatable {
    let skills: [String]
    let score: Int
}

struct OutcomeChanges: Decodable, Equatable {
    /// Job keywords the user has that are now named in a bullet
    let keywordsInBullets: [String]
    /// Skills added to the Skills list (all from the resume)
    let skillsListed: [String]
    /// Bullets with a [X] placeholder to fill in
    let placeholders: Int
    /// Skills the user confirmed in "Do you have these skills?"
    let confirmedSkills: [String]?
}

// MARK: - Rendered Resume (one-page PDF)

/// The PDF the user previews, downloads and saves, and how it was fitted.
struct RenderedResume: Equatable {
    let pdf: Data
    let layout: ResumeLayout
    /// The detailed score of exactly this PDF (after "Edit what's included")
    var score: AnalysisScore? = nil
}

/// /resume/render's X-Resume-Layout header.
struct ResumeLayout: Decodable, Equatable {
    let fontSize: Double
    let removed: [RemovedItem]
    let sections: [String]
    let included: IncludedItems
    let available: AvailableSections
}

struct RemovedItem: Decodable, Equatable {
    /// "section", "bullets", "project", "experience" or "format"
    let kind: String
    let label: String
    let count: Int?
    /// Left out by the user's own choice (not to fit the page)
    let chosen: Bool?
}

struct IncludedItems: Decodable, Equatable {
    let experience: [Int]
    let projects: [Int]
    let certifications: Bool
    let achievements: Bool
    let coursework: Bool
}

struct AvailableSections: Decodable, Equatable {
    let certifications: Bool
    let achievements: Bool
    let coursework: Bool
}

/// The user's "Edit what's included" choices.
struct IncludeChoice: Equatable {
    var experience: Set<Int>
    var projects: Set<Int>
    var certifications: Bool
    var achievements: Bool
    var coursework: Bool

    init(_ included: IncludedItems) {
        experience = Set(included.experience)
        projects = Set(included.projects)
        certifications = included.certifications
        achievements = included.achievements
        coursework = included.coursework
    }

    var json: [String: Any] {
        [
            "experience": experience.sorted(),
            "projects": projects.sorted(),
            "certifications": certifications,
            "achievements": achievements,
            "coursework": coursework,
        ]
    }
}

/// The jobs and projects in the optimized resume, for the Edit sheet.
struct ResumeOutline: Decodable, Equatable {
    struct Job: Decodable, Equatable {
        let title: String?
        let company: String?
    }
    struct Project: Decodable, Equatable {
        let title: String?
        let tech: String?
    }
    let experience: [Job]
    let projects: [Project]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        experience = (try? container.decode([Job].self, forKey: .experience)) ?? []
        projects = (try? container.decode([Project].self, forKey: .projects)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case experience, projects
    }
}

/// The user's choices don't fit on one page.
struct ResumeOverflowError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

struct BulletRewrite: Decodable, Equatable, Identifiable {
    let section: String
    let heading: String
    let original: String
    let improved: String
    /// Has a [X%]-style placeholder the user should fill in or remove
    let hasPlaceholder: Bool

    var id: String { original }
}

/// /resume/analysis response: the analysis, plus the stored full result
/// when this (resume, job) was optimized before.
struct AnalysisStart: Decodable {
    let analysis: ResumeAnalysis
    let result: OptimizationOutcome?
}
