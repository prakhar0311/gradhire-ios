import Foundation
import Combine

final class BookmarkManager: ObservableObject {

    @Published private(set) var savedJobIDs: Set<UUID> = []

    private let key = "saved_jobs"

    init() {
        load()
    }

    func isSaved(_ job: Job) -> Bool {
        savedJobIDs.contains(job.id)
    }

    func toggle(_ job: Job) {
        if savedJobIDs.contains(job.id) {
            savedJobIDs.remove(job.id)
        } else {
            savedJobIDs.insert(job.id)
        }
        persist()
    }

    private func persist() {
        let ids = savedJobIDs.map { $0.uuidString }
        UserDefaults.standard.set(ids, forKey: key)
    }

    private func load() {
        let ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        savedJobIDs = Set(ids.compactMap { UUID(uuidString: $0) })
    }
}

