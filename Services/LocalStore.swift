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
        // A broken store must not stop the app; the server copy is the truth
        let memory = ModelConfiguration("Tracker", schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: memory)
    }()
}
