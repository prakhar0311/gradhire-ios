import SwiftUI
import AuthenticationServices
import GoogleSignInSwift

// MARK: - Account Button

/// Toolbar button: opens the account sheet when signed in. Guests see a
/// small "Guest" chip that opens the shared sign-in sheet.
struct AccountButton: View {

    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var resumeManager: ResumeManager
    @EnvironmentObject private var tracker: TrackerStore
    @State private var showAccount = false

    var body: some View {
        Button {
            if session.isGuest {
                session.requireAccount(.general)
            } else {
                showAccount = true
            }
        } label: {
            HStack(spacing: 6) {
                if session.isGuest {
                    Text("Guest")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.leading, 10)
                }
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 34, height: 34)
                    Image(systemName: auth.user == nil ? "person.crop.circle" : "person.crop.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(auth.user == nil ? .white.opacity(0.6) : AppTheme.teal)
                }
            }
            .background {
                if session.isGuest {
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                }
            }
        }
        .accessibilityLabel(session.isGuest ? "Guest. Sign in to save your progress" : "Account")
        .sheet(isPresented: $showAccount) {
            AccountView()
                .environmentObject(auth)
                .environmentObject(session)
                .environmentObject(resumeManager)
                .environmentObject(tracker)
        }
    }
}

// MARK: - Account View

struct AccountView: View {

    /// Why sign-in was asked for (e.g. a guest tapped bookmark)
    var reason: String? = nil
    var detail: String? = nil
    /// Close the sheet once signed in, so the user is back where they were
    var dismissOnSignIn = false

    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var resumeManager: ResumeManager
    @EnvironmentObject private var tracker: TrackerStore
    @Environment(\.dismiss) private var dismiss

    @State private var confirmDelete = false
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        switch auth.state {
                        case .loading:
                            ProgressView()
                                .tint(AppTheme.violet)
                                .padding(.top, 80)
                        case .signedOut:
                            signInContent
                        case .signedIn(let user):
                            accountContent(user)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.base, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("ACCOUNT")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.35))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppTheme.lavender)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: auth.user?.id) { _, id in
            if dismissOnSignIn, id != nil { dismiss() }
        }
        .alert("Sign out with unsynced changes?", isPresented: $confirmSignOut) {
            Button("Sign Out", role: .destructive) {
                Task { await auth.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(tracker.pendingCount) tracker change\(tracker.pendingCount == 1 ? "" : "s") haven't synced yet and will be lost. Connect to the internet first to keep them.")
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
        .alert("Delete your account?", isPresented: $confirmDelete) {
            Button("Delete Account", role: .destructive) {
                Task {
                    if await auth.deleteAccount() { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                auth.user?.provider == "apple"
                ? "This permanently deletes your account and everything saved to it, including resumes. You'll confirm with Apple first. This can't be undone."
                : "This permanently deletes your account and everything saved to it, including resumes. This can't be undone."
            )
        }
    }

    // MARK: Signed Out

    private var signInContent: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.purple, AppTheme.teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.top, 12)

            VStack(spacing: 6) {
                Text(reason ?? "Sign in to GradHire")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail ?? "Save jobs, track your applications and keep your resume with your account. You can keep using GradHire as a guest.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SignInButtons()
                .padding(.top, 6)

            Button("Not now") { dismiss() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 4)
        }
    }

    // MARK: Signed In

    private func accountContent(_ user: AuthUser) -> some View {
        VStack(spacing: 14) {
            glassCard {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.purple, AppTheme.teal],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 52, height: 52)
                        Text(initials(for: user))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.name ?? "GradHire member")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        if let email = user.email {
                            Text(email)
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.45))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Text(providerLabel(user.provider))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppTheme.teal)
                            .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
            }

            resumeStatus

            Button {
                Task { await signOut() }
            } label: {
                Text("Sign Out")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                    .foregroundColor(.white.opacity(0.85))
                    .cornerRadius(14)
            }
            .disabled(auth.isWorking)

            Button {
                confirmDelete = true
            } label: {
                Text("Delete Account")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.coral.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.coral.opacity(0.25), lineWidth: 0.5))
                    .foregroundColor(AppTheme.coral)
                    .cornerRadius(14)
            }
            .disabled(auth.isWorking)
            .overlay {
                if auth.isWorking {
                    ProgressView().tint(.white)
                }
            }

            Text("Deleting your account removes your profile, saved resumes and everything else stored with it.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var resumeStatus: some View {
        switch resumeManager.saveStatus {
        case .idle:
            EmptyView()
        case .saving:
            notice("Saving your resume…", showsProgress: true)
        case .saved:
            notice("Your resume is saved to your account.", icon: "checkmark.circle.fill")
        case .failed(let message):
            notice("Couldn't save your resume. \(message)", icon: "exclamationmark.circle.fill")
        }
    }

    // MARK: Helpers

    /// Tries to sync tracker changes first; asks before losing any.
    private func signOut() async {
        if tracker.pendingCount > 0 {
            await tracker.sync()
            if tracker.pendingCount > 0 {
                confirmSignOut = true
                return
            }
        }
        await auth.signOut()
    }

    private func initials(for user: AuthUser) -> String {
        let source = user.name ?? user.email ?? "G"
        let parts = source.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "G" : letters.joined()
    }

    private func providerLabel(_ provider: String?) -> String {
        switch provider {
        case "apple":  return "Signed in with Apple"
        case "google": return "Signed in with Google"
        default:       return "Signed in"
        }
    }

    private func notice(_ text: String, icon: String = "info.circle.fill", showsProgress: Bool = false) -> some View {
        HStack(spacing: 10) {
            if showsProgress {
                ProgressView().tint(AppTheme.violet)
            } else {
                Image(systemName: icon)
                    .foregroundColor(AppTheme.lavender)
            }
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.09), lineWidth: 0.5))
        .cornerRadius(14)
    }

    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 0.5))
            .cornerRadius(20)
    }
}

// MARK: - Sign-in Buttons

/// The official Sign in with Apple and Google buttons, shared by the Welcome
/// screen and the sign-in sheet.
struct SignInButtons: View {

    @EnvironmentObject private var auth: AuthViewModel

    var body: some View {
        if auth.isConfigured {
            VStack(spacing: 12) {
                SignInWithAppleButton(.signIn) { request in
                    auth.prepareAppleRequest(request)
                } onCompletion: { result in
                    Task { await auth.completeAppleSignIn(result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                GoogleSignInButton(scheme: .dark, style: .wide, state: auth.isWorking ? .disabled : .normal) {
                    Task { await auth.signInWithGoogle() }
                }
                .frame(height: 50)
            }
            .disabled(auth.isWorking)
            .overlay {
                if auth.isWorking {
                    ProgressView().tint(.white)
                }
            }
        } else {
            Text("Sign-in isn't available right now.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}
