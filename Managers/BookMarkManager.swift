import Foundation

// MARK: - Legacy Bookmarks

/// Jobs bookmarked on this device before the tracker existed (stored in
/// UserDefaults). They're imported into the signed-in user's tracker as
/// Saved, once, and then removed from the device.
enum LegacyBookmarks {

    private static let key = "saved_jobs_v2"
    private static let olderKey = "saved_jobs" // IDs only; those IDs were random per request

    static var count: Int { load().count }

    /// Returns the bookmarked jobs and removes them from the device.
    static func take() -> [Job] {
        let jobs = load()
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: olderKey)
        return jobs
    }

    private static func load() -> [Job] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let jobs = try? Job.decoder.decode([Job].self, from: data) else { return [] }
        return jobs
    }
}
