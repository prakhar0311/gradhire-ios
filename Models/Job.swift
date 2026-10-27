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
