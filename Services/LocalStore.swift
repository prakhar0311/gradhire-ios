import Foundation
import SwiftData

// MARK: - Local Store

/// The app's one SwiftData container: the tracker and dashboard caches.
/// Everything in it belongs to the signed-in user and is cleared on sign-out.
enum LocalStore {

    static let container: ModelContainer = {
        let schema = Schema([TrackedJob.self, DashboardCache.self])
        let configuration = ModelConfiguration("Tracker", schema: schema)
        if let container = try? ModelContainer(for: schema, configurations: configuration) {
            return container
        }
        // A store that can't be opened (e.g. damaged) is only a cache of the
        // server copy: start a fresh one on disk, so offline edits made from
        // now on survive a relaunch
        let store = configuration.url
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: store.path + suffix))
        }
        if let container = try? ModelContainer(for: schema, configurations: configuration) {
            return container
        }
        // Last resort: the app must still start
        let memory = ModelConfiguration("Tracker", schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: memory)
    }()
}
