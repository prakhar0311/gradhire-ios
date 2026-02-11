import Foundation

struct Job: Identifiable, Codable {
    let id: UUID
    let title: String
    let company: String
    let location: String
    let description: String
    let matchScore: Int
    let applyURL: String
}


