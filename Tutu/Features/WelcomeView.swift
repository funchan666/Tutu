import SwiftUI
import AuthenticationServices

struct WelcomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var emailMode = false
    @State private var creating = false
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var accepted = false
    @State private var busy = false
    @State private var error = ""
    @State private var legal: LegalPage?
    var body: some View {
        Group {
            if emailMode || store.returnToLogin { form }
            else {
                GeometryReader { geometry in
                    VStack(spacing: 18) {
                        Spacer(minLength: 200)
                        VStack(spacing: 14) {
                            SignInWithAppleButton(.signIn) { request in
                                request.requestedScopes = [.fullName, .email]
                            } onCompletion: { result in
                                switch result {
                                case .success(let auth):
                                    guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { error = "Apple sign-in is unavailable."; return }
                                    do {
                                        let display = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
                                        try store.acceptAppleIdentity(userID: credential.user, name: display, email: credential.email)
                                    } catch { self.error = error.localizedDescription }
                                case .failure(let failure):
                                    if (failure as? ASAuthorizationError)?.code != .canceled { error = "Apple sign-in couldn't be completed. Please try again." }
                                }
                            }.signInWithAppleButtonStyle(.white).frame(height: 54).clipShape(Capsule())
                            PinkButton(title: "Continue With Email", asset: "button-email") { emailMode = true }
                            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.white).multilineTextAlignment(.center) }
                            legalFooter.foregroundStyle(.white)
                        }.padding(.horizontal, 22).padding(.bottom, 16)
                    }.frame(width: geometry.size.width, height: geometry.size.height)
                }.background(SceneBackground(name: "welcome-background"))
            }
        }.sheet(item: $legal) { LegalWebView(page: $0) }
    }
    var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ArtButton(label: "Back", asset: "nav-back") { emailMode = false; store.returnToLogin = false; error = "" }.disabled(busy)
                Text(creating ? "Create your account" : "Welcome Back").font(.system(size: 30, weight: .bold, design: .rounded)).padding(.top, 28)
                Text(creating ? "Your next connection starts with your style." : "Log in to continue your story.").font(.subheadline).foregroundStyle(Palette.secondary)
                if creating { Field(title: "Your name", text: $name) }
                Field(title: "Email Address", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress)
                Field(title: "Password", text: $password, secure: true).textContentType(creating ? .newPassword : .password)
                if creating { ArtToggle(title: "I am 18 or older and accept the terms", value: $accepted) }
                if !error.isEmpty { Text(error).font(.subheadline).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) }
                PinkButton(title: creating ? "Create Account" : "Log In", asset: creating ? "button-register" : "button-login", busy: busy) {
                    guard !creating || accepted else { error = "Confirm your age and accept the terms to continue."; return }
                    busy = true; error = ""
                    Task {
                        defer { busy = false }
                        do { try await store.authenticate(email: email, password: password, creating: creating, name: name); password = "" }
                        catch { self.error = error.localizedDescription }
                    }
                }.padding(.top, 24)
                Button(creating ? "Already have an account? Log In" : "Don't have an account? Create Account") { creating.toggle(); error = "" }.disabled(busy).font(.subheadline.bold()).foregroundStyle(Palette.pink).frame(maxWidth: .infinity).padding(.vertical, 12)
                legalFooter
            }.padding(20)
        }.scrollDismissesKeyboard(.interactively).background(SceneBackground())
    }
    var legalFooter: some View {
        VStack(spacing: 6) {
            Text("By continuing, you agree to our").font(.caption)
            HStack(spacing: 6) { Button("User Agreement") { legal = .terms }; Text("and"); Button("Privacy Policy") { legal = .privacy } }.font(.caption).buttonStyle(.plain)
        }.frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.vertical, 8)
    }
}
