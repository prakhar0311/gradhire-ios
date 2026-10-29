import Foundation

struct Job: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let company: String
    let location: String
    let description: String
    let matchScore: Int?      // nil for the "All Jobs" feed (not resume-matched)
    let applyURL: String
    let postedAt: Date?
    let contractTime: String? // Adzuna: "full_time", "part_time" or nil
    // Resume-matched jobs only: skills the job asks for that the resume has / lacks
    var matchedSkills: [String]? = nil
    var missingSkills: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, company, location, description
        case matchScore, applyURL, postedAt, contractTime
        case matchedSkills, missingSkills
    }
}

// MARK: - Lenient Decoding

extension Job {

    // A missing or malformed date must not fail the whole list (or saved
    // bookmarks); the job just shows up as undated.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        company = try container.decode(String.self, forKey: .company)
        location = try container.decode(String.self, forKey: .location)
        description = try container.decode(String.self, forKey: .description)
        matchScore = try container.decodeIfPresent(Int.self, forKey: .matchScore)
        applyURL = try container.decode(String.self, forKey: .applyURL)
        postedAt = try? container.decodeIfPresent(Date.self, forKey: .postedAt)
        contractTime = try? container.decodeIfPresent(String.self, forKey: .contractTime)
        matchedSkills = try? container.decodeIfPresent([String].self, forKey: .matchedSkills)
        missingSkills = try? container.decodeIfPresent([String].self, forKey: .missingSkills)
    }
}

// MARK: - Display Helpers

extension Job {

    var postedAgoText: String? {
        guard let postedAt else { return nil }

        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: postedAt),
            to: Calendar.current.startOfDay(for: Date())
        ).day ?? 0

        switch days {
        case ..<1:    return "Posted today"
        case 1:       return "Posted yesterday"
        case 2..<30:  return "Posted \(days) days ago"
        case 30..<60: return "Posted 1 month ago"
        default:      return "Posted \(days / 30) months ago"
        }
    }

    var contractLabel: String? {
        switch contractTime {
        case "full_time": return "Full-time"
        case "part_time": return "Part-time"
        default:          return nil
        }
    }
}

// MARK: - Coding

extension Job {

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
