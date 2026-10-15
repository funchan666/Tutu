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
    @State private var showingConsentPrompt = false
    @AccessibilityFocusState private var consentFocused: Bool
    @AccessibilityFocusState private var promptFocused: Bool
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
                                guard requireConsent() else { return }
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
                                .allowsHitTesting(accepted)
                                .accessibilityHidden(!accepted)
                                .overlay {
                                    // Gate the tap before the genuine Apple authorization button receives it.
                                    if !accepted {
                                        Button { _ = requireConsent() } label: {
                                            Color.clear.contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Sign in with Apple")
                                        .accessibilityHint("Requires agreement to the User Agreement and Privacy Policy")
                                    }
                                }
                            PinkButton(title: "Continue With Email", asset: "button-email") {
                                guard requireConsent() else { return }
                                error = ""
                                emailMode = true
                            }
                            if !error.isEmpty { Text(ui: error).font(.tutuCaption).foregroundStyle(.white).multilineTextAlignment(.center) }
                            legalFooter(onPhoto: true)
                        }.padding(.horizontal, 22).padding(.bottom, 16)
                    }.frame(width: geometry.size.width, height: geometry.size.height)
                }.background(SceneBackground(name: "welcome-background"))
            }
        }
        .allowsHitTesting(!showingConsentPrompt)
        .accessibilityHidden(showingConsentPrompt)
        .overlay {
            if showingConsentPrompt { consentPrompt }
        }
        .sheet(item: $legal) { LegalWebView(page: $0) }
    }
    var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ArtButton(label: "Back", asset: "nav-back") {
                    error = ""
                    if creating { creating = false }
                    else { emailMode = false; store.returnToLogin = false }
                }.disabled(busy)
                Text(ui: creating ? "Create your account" : "Welcome Back").font(.outfit(size: 30, weight: .bold, design: .rounded)).padding(.top, 28)
                Text(ui: creating ? "Your next connection starts with your style." : "Log in to continue your story.").font(.tutuSubheadline).foregroundStyle(Palette.secondary)
                if creating { Field(title: "Your name", text: $name) }
                Field(title: "Email Address", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress)
                Field(title: "Password", text: $password, secure: true).textContentType(creating ? .newPassword : .password)
                legalFooter(onPhoto: false)
                if !error.isEmpty { Text(ui: error).font(.tutuSubheadline).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) }
                PinkButton(title: creating ? "Create Account" : "Log In", asset: creating ? "button-register" : "button-login", busy: busy) {
                    guard requireConsent() else { return }
                    busy = true; error = ""
                    Task {
                        defer { busy = false }
                        do { try await store.authenticate(email: email, password: password, creating: creating, name: name); password = "" }
                        catch { self.error = error.localizedDescription }
                    }
                }.padding(.top, 24)
                Button(LocalizedStringKey(creating ? "Already have an account? Log In" : "Don't have an account? Create Account")) { creating.toggle(); error = "" }.disabled(busy).font(.tutuSubheadline.bold()).foregroundStyle(Palette.pink).frame(maxWidth: .infinity).padding(.vertical, 12)
            }.padding(20)
        }.scrollDismissesKeyboard(.interactively).background(SceneBackground())
    }
    private func requireConsent() -> Bool {
        guard accepted else {
            error = ""
            showingConsentPrompt = true
            return false
        }
        return true
    }

    private func legalFooter(onPhoto: Bool) -> some View {
        HStack(spacing: 2) {
            Button {
                accepted.toggle()
                error = ""
            } label: {
                ZStack {
                    // Input chrome only; the checkmark is the supplied original artwork.
                    RoundedRectangle(cornerRadius: 5)
                        .fill(onPhoto ? Color.white.opacity(0.12) : Color.white)
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(onPhoto ? Color.white.opacity(0.9) : Palette.pink, lineWidth: 1.5)
                    if accepted { Artwork(name: "control-check") }
                }
                .frame(width: 19, height: 19)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("I agree to the User Agreement and Privacy Policy")
            .accessibilityValue(accepted ? "Checked" : "Unchecked")
            .accessibilityHint("Double tap to change your selection")
            .accessibilityAddTraits(accepted ? [.isSelected] : [])
            .accessibilityFocused($consentFocused)

            VStack(alignment: .leading, spacing: 4) {
                Text("I agree to the")
                    .font(.tutuCaption)
                    .foregroundStyle(onPhoto ? Color.white.opacity(0.9) : Palette.secondary)
                Text(consentLinks(color: onPhoto ? .white : Palette.pink))
                    .font(.tutuCaption)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.openURL, OpenURLAction { url in
                        if url == LegalPage.terms.url { legal = .terms }
                        else if url == LegalPage.privacy.url { legal = .privacy }
                        return .handled
                    })
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .tint(onPhoto ? .white : Palette.pink)
        .disabled(busy)
    }

    private func consentLinks(color: Color) -> AttributedString {
        var terms = AttributedString(store.appLanguage.text("User Agreement"))
        terms.link = LegalPage.terms.url
        terms.underlineStyle = .single
        terms.font = Font.outfit(size: 12, weight: .medium, relativeTo: .caption)
        var privacy = AttributedString(store.appLanguage.text("Privacy Policy"))
        privacy.link = LegalPage.privacy.url
        privacy.underlineStyle = .single
        privacy.font = Font.outfit(size: 12, weight: .medium, relativeTo: .caption)
        var links = terms + AttributedString("  &  ") + privacy
        links.foregroundColor = color
        return links
    }

    private func policyLinks(color: Color) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                policyLink(.terms)
                Text("&").font(.tutuCaption)
                policyLink(.privacy)
            }
            VStack(alignment: .leading, spacing: 0) {
                policyLink(.terms)
                policyLink(.privacy)
            }
        }
        .foregroundStyle(color)
    }

    private func policyLink(_ page: LegalPage) -> some View {
        Button {
            showingConsentPrompt = false
            legal = page
        } label: {
            Text(ui: page.title)
                .font(.outfit(size: 12, weight: .semibold, relativeTo: .caption))
                .underline()
                .fixedSize()
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the full document")
    }

    private var consentPrompt: some View {
        ZStack {
            Color.black.opacity(0.48).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Artwork(name: "brand-mascot")
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                    Text("Your style. Your choice.")
                        .font(.tutuTitle2)
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($promptFocused)
                    Text("Please read the User Agreement and Privacy Policy, then tick the box to agree and continue.")
                        .font(.tutuSubheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    policyLinks(color: Palette.pink)
                    PinkButton(title: "Back to the checkbox") {
                        showingConsentPrompt = false
                        consentFocused = true
                    }
                    Text("The choice is always yours.")
                        .font(.tutuCaption)
                        .foregroundStyle(Palette.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(24)
                .frame(maxWidth: 380)
                .background(Palette.blush, in: RoundedRectangle(cornerRadius: 28))
                .shadow(color: Palette.ink.opacity(0.2), radius: 28, y: 12)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityAddTraits(.isModal)
        .onAppear { promptFocused = true }
    }
}
