import Foundation

// MARK: - Sort

enum JobSort: String, CaseIterable, Identifiable {
    case bestMatch
    case newest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bestMatch: return "Best match"
        case .newest:    return "Newest first"
        }
    }
}

extension Array where Element == Job {

    /// Best match keeps the backend's score order. Newest puts undated jobs last;
    /// ties keep their original order.
    func sorted(by sort: JobSort) -> [Job] {
        guard sort == .newest else { return self }

        return enumerated()
            .sorted { lhs, rhs in
                switch (lhs.element.postedAt, rhs.element.postedAt) {
                case let (l?, r?) where l != r: return l > r
                case (_?, nil):                 return true
                case (nil, _?):                 return false
                default:                        return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }
}
