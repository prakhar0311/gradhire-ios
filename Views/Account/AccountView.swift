import SwiftUI
import AuthenticationServices
import GoogleSignInSwift

// MARK: - Account Button

/// Toolbar/overlay button that opens the account sheet.
struct AccountButton: View {

    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var resumeManager: ResumeManager
    @State private var showAccount = false

    var body: some View {
        Button {
            showAccount = true
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 34, height: 34)
                Image(systemName: auth.user == nil ? "person.crop.circle" : "person.crop.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(
                        auth.user == nil
                        ? .white.opacity(0.6)
                        : Color(red: 0.0, green: 0.83, blue: 0.67)
                    )
            }
        }
        .accessibilityLabel(auth.user == nil ? "Sign in" : "Account")
        .sheet(isPresented: $showAccount) {
            AccountView()
                .environmentObject(auth)
                .environmentObject(resumeManager)
        }
    }
}

// MARK: - Account View

struct AccountView: View {

    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var resumeManager: ResumeManager
    @Environment(\.dismiss) private var dismiss

    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.06)
                    .ignoresSafeArea()

                RadialGradient(
                    colors: [Color(red: 0.39, green: 0.22, blue: 1.0).opacity(0.25), Color.clear],
                    center: .init(x: 0.2, y: 0.05),
                    startRadius: 0,
                    endRadius: 320
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        switch auth.state {
                        case .loading:
                            ProgressView()
                                .tint(Color(red: 0.55, green: 0.43, blue: 1.0))
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
            .toolbarBackground(Color(red: 0.04, green: 0.04, blue: 0.06), for: .navigationBar)
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
                        .foregroundColor(Color(red: 0.65, green: 0.55, blue: 0.98))
                }
            }
        }
        .preferredColorScheme(.dark)
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
        .alert("Save this resume to your account?", isPresented: $auth.offerResumeSave) {
            Button("Save") {
                guard let url = resumeManager.resumeURL else { return }
                Task { await auth.saveGuestResume(fileURL: url, text: resumeManager.resumeText) }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Your resume will be stored privately in your GradHire account so it's there next time. If you choose Not now, it isn't stored.")
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
                            colors: [Color(red: 0.39, green: 0.22, blue: 1.0), Color(red: 0.0, green: 0.83, blue: 0.67)],
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
                Text("Sign in to GradHire")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Keep your resume and saved jobs with your account. You can keep using GradHire as a guest.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if auth.isConfigured {
                VStack(spacing: 12) {
                    SignInWithAppleButton(.signIn) { request in
                        auth.prepareAppleRequest(request)
                    } onCompletion: { result in
                        Task {
                            await auth.completeAppleSignIn(result, hasResumeToOffer: resumeManager.resumeURL != nil)
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    GoogleSignInButton(scheme: .dark, style: .wide, state: auth.isWorking ? .disabled : .normal) {
                        Task { await auth.signInWithGoogle(hasResumeToOffer: resumeManager.resumeURL != nil) }
                    }
                    .frame(height: 50)
                }
                .disabled(auth.isWorking)
                .overlay {
                    if auth.isWorking {
                        ProgressView().tint(.white)
                    }
                }
                .padding(.top, 6)
            } else {
                notice("Sign-in isn't available right now.")
            }

            Button("Continue as guest") { dismiss() }
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
                                    colors: [Color(red: 0.39, green: 0.22, blue: 1.0), Color(red: 0.0, green: 0.83, blue: 0.67)],
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
                            .foregroundColor(Color(red: 0.0, green: 0.83, blue: 0.67))
                            .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
            }

            resumeStatus

            Button {
                Task { await auth.signOut() }
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
                    .background(Color(red: 1.0, green: 0.48, blue: 0.45).opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 1.0, green: 0.48, blue: 0.45).opacity(0.25), lineWidth: 0.5))
                    .foregroundColor(Color(red: 1.0, green: 0.48, blue: 0.45))
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
        switch auth.resumeSaveStatus {
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
                ProgressView().tint(Color(red: 0.55, green: 0.43, blue: 1.0))
            } else {
                Image(systemName: icon)
                    .foregroundColor(Color(red: 0.65, green: 0.55, blue: 0.98))
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
