import Foundation
import Combine

// MARK: - Models

enum ResumeVersion: String, CaseIterable, Identifiable {
    case original = "Original"
    case optimized = "Optimized"

    var id: String { rawValue }
}

enum ResumeScoreState: Equatable {
    case loading
    case loaded(before: Int, after: Int)
    case failed
}

/// One optimization run. Its score lives on the result itself, so a score can
/// never be shown next to a different resume than the one it was computed for.
struct OptimizationResult: Identifiable {
    let id = UUID()
    let response: ResumeOptimizationResponse
    let originalResumeText: String
    var score: ResumeScoreState
}

// MARK: - Optimize Resume View Model

final class OptimizeResumeViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case optimizing
        case done
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var result: OptimizationResult?
    @Published var selectedVersion: ResumeVersion = .optimized

    let job: Job

    private var optimizeTask: Task<Void, Never>?
    private var scoreTask: Task<Void, Never>?

    init(job: Job) {
        self.job = job
    }

    // MARK: Lifecycle

    /// Starts work only if nothing is running, so reappearing never duplicates requests.
    func onAppear(resumeText: String?, isConnected: Bool) {
        if phase == .idle {
            optimize(resumeText: resumeText, isConnected: isConnected)
        } else if let result, result.score == .loading, scoreTask == nil {
            rescore(resultID: result.id)
        }
    }

    /// Leaving the screen cancels in-flight requests; onAppear resumes them.
    func onDisappear() {
        optimizeTask?.cancel()
        optimizeTask = nil
        scoreTask?.cancel()
        scoreTask = nil
        if phase == .optimizing { phase = .idle }
    }

    // MARK: Optimize

    func optimize(resumeText: String?, isConnected: Bool) {
        guard isConnected else { phase = .failed("No internet connection"); return }
        guard let resumeText, !resumeText.isEmpty else { phase = .failed("Resume not found"); return }

        optimizeTask?.cancel()
        scoreTask?.cancel()
        scoreTask = nil
        result = nil
        selectedVersion = .optimized
        phase = .optimizing

        let job = job
        optimizeTask = Task {
            do {
                let response = try await APIService.shared.optimizeResume(
                    resumeText: resumeText,
                    jobTitle: job.title,
                    jobDescription: job.description
                )
                guard !Task.isCancelled else { return }
                optimizeTask = nil

                guard !response.improvedBullets.isEmpty || !response.missingSkills.isEmpty else {
                    phase = .failed("AI returned empty results")
                    return
                }

                let newResult = OptimizationResult(
                    response: response,
                    originalResumeText: resumeText,
                    score: .loading
                )
                result = newResult
                phase = .done
                rescore(resultID: newResult.id)

            } catch {
                guard !Task.isCancelled else { return }
                optimizeTask = nil
                phase = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Score

    func retryScore() {
        guard let result else { return }
        rescore(resultID: result.id)
    }

    private func rescore(resultID: UUID) {
        guard let current = result, current.id == resultID else { return }

        guard let optimizedText = current.response.optimizedResumeText,
              !optimizedText.isEmpty else {
            result?.score = .failed
            return
        }

        scoreTask?.cancel()
        result?.score = .loading

        let jobDescription = job.description
        scoreTask = Task {
            do {
                // Both versions scored in one call by the same backend function
                let scores = try await APIService.shared.scoreResumes(
                    jobDescription: jobDescription,
                    resumeTexts: [current.originalResumeText, optimizedText]
                )
                // Drop the response if a newer optimization replaced this result
                guard !Task.isCancelled, result?.id == resultID else { return }
                scoreTask = nil
                result?.score = .loaded(before: scores[0], after: scores[1])

            } catch {
                guard !Task.isCancelled, result?.id == resultID else { return }
                scoreTask = nil
                result?.score = .failed
            }
        }
    }
}
