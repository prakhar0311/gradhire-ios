import Foundation

// MARK: - Date Filter

enum JobDateFilter: String, CaseIterable, Identifiable {
    case anyTime
    case last24Hours
    case last3Days
    case last7Days
    case last30Days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anyTime:     return "Any time"
        case .last24Hours: return "Last 24 hours"
        case .last3Days:   return "Last 3 days"
        case .last7Days:   return "Last 7 days"
        case .last30Days:  return "Last 30 days"
        }
    }

    /// Rolling window in days; nil means no limit. Also sent to the backend as max_days.
    var maxDays: Int? {
        switch self {
        case .anyTime:     return nil
        case .last24Hours: return 1
        case .last3Days:   return 3
        case .last7Days:   return 7
        case .last30Days:  return 30
        }
    }

    /// Jobs without a posting date only appear under "Any time".
    func includes(_ job: Job, now: Date = Date()) -> Bool {
        guard let maxDays else { return true }
        guard let postedAt = job.postedAt else { return false }
        return now.timeIntervalSince(postedAt) <= TimeInterval(maxDays) * 24 * 60 * 60
    }

    var emptyTitle: String {
        switch self {
        case .anyTime:     return "No jobs found"
        case .last24Hours: return "No jobs posted in the last 24 hours"
        case .last3Days:   return "No jobs posted in the last 3 days"
        case .last7Days:   return "No jobs posted in the last 7 days"
        case .last30Days:  return "No jobs posted in the last 30 days"
        }
    }
}

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
