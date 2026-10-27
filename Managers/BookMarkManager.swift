import Foundation
import Combine

final class BookmarkManager: ObservableObject {

    // Full jobs are stored (newest first) so saved jobs survive new searches
    // and app restarts, not just the list they were saved from.
    @Published private(set) var savedJobs: [Job] = []

    private let key = "saved_jobs_v2"
    private let legacyKey = "saved_jobs" // IDs only; those IDs were random per request

    init() {
        load()
    }

    func isSaved(_ job: Job) -> Bool {
        savedJobs.contains { $0.id == job.id }
    }

    func toggle(_ job: Job) {
        if isSaved(job) {
            savedJobs.removeAll { $0.id == job.id }
        } else {
            savedJobs.insert(job, at: 0)
        }
        persist()
    }

    private func persist() {
        guard let data = try? Job.encoder.encode(savedJobs) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func load() {
        UserDefaults.standard.removeObject(forKey: legacyKey)

        guard let data = UserDefaults.standard.data(forKey: key),
              let jobs = try? Job.decoder.decode([Job].self, from: data) else { return }
        savedJobs = jobs
    }
}
