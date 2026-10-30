import SwiftUI

// MARK: - App Root

/// Shows what AppSession decides: splash, Welcome, or the tabs. Also hosts
/// the app's one sign-in sheet and its toast.
struct AppRootView: View {

    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var resumeManager: ResumeManager
    @EnvironmentObject private var tracker: TrackerStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ZStack {
            switch session.phase {
            case .launching:
                SplashView()
                    .transition(.opacity)
            case .welcome:
                WelcomeView()
                    .transition(.opacity)
            case .guest, .signedIn:
                RootTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: session.phase)
        .preferredColorScheme(.dark)
        .sheet(item: $session.signInRequest, onDismiss: session.signInSheetDismissed) { reason in
            AccountView(reason: reason.title, detail: reason.detail(hasResume: resumeManager.hasResume), dismissOnSignIn: true)
                .environmentObject(auth)
                .environmentObject(session)
                .environmentObject(resumeManager)
                .environmentObject(tracker)
        }
        // Saving one more resume than the account allows
        .sheet(item: $session.resumeLimitPrompt) { prompt in
            ResumeLimitSheet(prompt: prompt)
                .environmentObject(session)
                .environmentObject(resumeManager)
                .presentationDetents([.height(380)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $session.showsSavedResumes) {
            NavigationStack {
                SavedResumesListView(isSheet: true)
            }
            .environmentObject(resumeManager)
            .environmentObject(router)
        }
        .overlay(alignment: .top) { NoticeToast() }
    }
}

extension AppSession.SignInReason {

    /// Every account-only feature uses the same headline.
    var title: String { "Sign in to save your progress" }

    func detail(hasResume: Bool) -> String {
        let feature: String
        switch self {
        case .saveJob:   feature = "Save this job and track it from Saved to Offer."
        case .tracker:   feature = "Track every job you save and apply to."
        case .dashboard: feature = "See your pipeline, weekly progress and follow-ups."
        case .general:   feature = "Save jobs, track applications and keep your resume."
        }
        return hasResume
            ? "\(feature) Your resume and progress will be saved to your account."
            : feature
    }
}

// MARK: - Notice Toast

private struct NoticeToast: View {

    @EnvironmentObject private var session: AppSession

    var body: some View {
        Group {
            if let notice = session.notice {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppTheme.teal)
                    Text(notice)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: notice) {
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    withAnimation { session.notice = nil }
                }
                .onTapGesture { withAnimation { session.notice = nil } }
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: session.notice)
    }
}

// MARK: - Splash

/// Shown for the moment the stored session is read (and refreshed if it
/// expired), so the Welcome screen never flashes for a signed-in user.
private struct SplashView: View {

    var body: some View {
        ZStack {
            AppBackground(animated: false)
            AppLogo(size: 72)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("GradHire is loading")
    }
}

// MARK: - Logo

struct AppLogo: View {

    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(AppTheme.brandGradientDiagonal)
                .frame(width: size, height: size)
                .shadow(color: AppTheme.purple.opacity(0.45), radius: size * 0.3, x: 0, y: size * 0.1)
            Image(systemName: "graduationcap.fill")
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundColor(.white)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Welcome

/// First screen while signed out: one screen, no carousel.
struct WelcomeView: View {

    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var auth: AuthViewModel

    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var messageSize: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 60)

                    VStack(spacing: 18) {
                        AppLogo(size: 76)

                        Text("GradHire")
                            .font(.system(size: titleSize, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .accessibilityAddTraits(.isHeader)

                        Text("Find fresher jobs that match your resume")
                            .font(.system(size: messageSize, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 14) {
                            point("doc.text.magnifyingglass", "Match")
                            point("wand.and.stars", "Improve")
                            point("checklist", "Track")
                        }
                        .padding(.top, 6)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : 14)

                    Spacer(minLength: 48)

                    VStack(spacing: 14) {
                        if let message = session.welcomeMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(AppTheme.amber)
                                Text(message)
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.8))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        if !session.legacyBookmarks.isEmpty {
                            let count = session.legacyBookmarks.count
                            Text("You have \(count) saved job\(count == 1 ? "" : "s") from the previous version. Sign in to keep \(count == 1 ? "it" : "them").")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.teal)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        SignInButtons()

                        Button {
                            session.continueAsGuest()
                        } label: {
                            Text("Continue as guest")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white.opacity(0.65))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                        }
                        .disabled(auth.isWorking)

                        Text("As a guest, nothing is saved after you close the app.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.35))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.black.opacity(0.25))
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: 440)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { auth.errorMessage != nil },
                set: { if !$0 { auth.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { auth.errorMessage = nil }
        } message: {
            Text(auth.errorMessage ?? "")
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.8)) { appeared = true }
        }
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.teal)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}
