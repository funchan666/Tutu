import SwiftUI
import AuthenticationServices
import UIKit

struct WelcomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var emailMode = false
    @State private var creating = false
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var accepted = false
    @EnvironmentObject private var gateway: AtelierGateway
    @Environment(\.scenePhase) private var scene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var busy: Bool { gateway.busy }
    @State private var error = ""
    @State private var legal: LegalPage?
    @State private var showingConsentPrompt = false
    @AccessibilityFocusState private var consentFocused: Bool
    @AccessibilityFocusState private var promptFocused: Bool
    var body: some View {
        Group {
            if gateway.mode == .standard && (emailMode || store.returnToLogin) { form }
            else {
                GeometryReader { geometry in
                    VStack(spacing: 18) {
                        Spacer(minLength: 200)
                        VStack(spacing: 14) {
                            if gateway.checking { arrivalFeedback }
                            else if gateway.mode == .guestOnly {
                                PinkButton(title: "Continue as Guest", busy: busy) { guard requireConsent() else { return }; gateway.guest() }
                            } else {
                            EnglishAppleSignInButton {
                                guard requireConsent() else { return false }
                                return gateway.reserve()
                            } onCompletion: { result in
                                guard requireConsent() else { gateway.appleCancelled(); return }
                                switch result {
                                case .success(let auth):
                                    guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { gateway.appleCancelled(); return }
                                    let display = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
                                    gateway.apple(user: credential.user, token: credential.identityToken, code: credential.authorizationCode, name: display, email: credential.email)
                                case .failure(let failure):
                                    gateway.appleCancelled()
                                    if (failure as? ASAuthorizationError)?.code != .canceled { error = "Apple sign-in couldn't be completed. Please try again." }
                                }
                            }.disabled(busy).frame(maxWidth: .infinity).frame(height: 54).clipShape(Capsule())
                                .allowsHitTesting(accepted && !busy)
                                .accessibilityHidden(!accepted || busy)
                                .overlay {
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
                                guard !busy else { return }
                                guard requireConsent() else { return }
                                error = ""
                                emailMode = true
                            }
                            }
                            if busy { arrivalFeedback }
                            if !gateway.error.isEmpty { Text(gateway.error).font(.tutuCaption).foregroundStyle(.white).multilineTextAlignment(.center) }
                            if gateway.route == .webFailure, gateway.web != nil { PinkButton(title: "Try again") { gateway.retryWeb() } }
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
        .onChange(of: gateway.mode) { _, mode in
            accepted = mode == .guestOnly; emailMode = false; store.returnToLogin = false
        }
        .sheet(item: $legal) { LegalWebView(page: $0) }
    }
    private var arrivalFeedback: some View {
        HStack(spacing: 10) {
            TimelineView(.animation(minimumInterval: 0.3, paused: scene != .active || reduceMotion)) { context in
                Artwork(name: "tab-party-active").frame(width: 16, height: 16)
                    .opacity(reduceMotion ? 1 : 0.55 + 0.45 * abs(sin(context.date.timeIntervalSinceReferenceDate * 2)))
            }
            Text(busy ? "Preparing your visit…" : "Finding your entrance…")
        }
            .font(.tutuSubheadline).foregroundStyle(.white).padding(16).frame(maxWidth: .infinity)
            .background(.white.opacity(0.12), in: Capsule()).accessibilityAddTraits(.updatesFrequently)
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
                if !gateway.error.isEmpty { Text(gateway.error).font(.tutuCaption).foregroundStyle(Palette.pink) }
                if gateway.route == .webFailure, gateway.web != nil { PinkButton(title: "Try again") { gateway.retryWeb() } }
                if !error.isEmpty { Text(ui: error).font(.tutuSubheadline).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) }
                PinkButton(title: creating ? "Create Account" : "Log In", asset: creating ? "button-register" : "button-login", busy: busy) {
                    guard requireConsent() else { return }
                    error = ""
                    gateway.email(email, password: password, creating: creating, name: name)

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

/// A fixed English entry label with Apple's unmodified logo artwork.
/// Authentication still uses the system authorization controller and sheet.
private struct EnglishAppleSignInButton: UIViewRepresentable {
    var onRequest: () -> Bool
    var onCompletion: (Result<ASAuthorization, Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .custom)
        button.backgroundColor = .white
        button.accessibilityLabel = "Sign in with Apple"
        button.accessibilityLanguage = "en-US"
        button.semanticContentAttribute = .forceLeftToRight
        let logo = UIImageView(image: UIImage(named: "apple-signin-mark"))
        logo.contentMode = .scaleAspectFit
        let title = UILabel()
        // Do not localize: this entry must remain English in every app/device language.
        title.text = "Sign in with Apple"
        title.font = .systemFont(ofSize: 54 * 0.43, weight: .medium)
        title.textColor = .black
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.8
        let content = UIStackView(arrangedSubviews: [logo, title])
        content.axis = .horizontal
        content.alignment = .center
        content.spacing = 0 // Apple's PDF already includes the required logo padding.
        content.semanticContentAttribute = .forceLeftToRight
        content.isUserInteractionEnabled = false
        content.accessibilityElementsHidden = true
        content.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(content)
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            content.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            content.widthAnchor.constraint(lessThanOrEqualTo: button.widthAnchor, multiplier: 0.84),
            logo.heightAnchor.constraint(equalTo: button.heightAnchor),
            logo.widthAnchor.constraint(equalTo: logo.heightAnchor, multiplier: 31.0 / 44.0)
        ])
        button.addTarget(context.coordinator, action: #selector(Coordinator.signIn(_:)), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.parent = self
        button.isEnabled = context.environment.isEnabled
        button.alpha = button.isEnabled ? 1 : 0.6
    }

    @MainActor
    final class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        var parent: EnglishAppleSignInButton
        private var controller: ASAuthorizationController?
        private var anchor: UIWindow?

        init(parent: EnglishAppleSignInButton) { self.parent = parent }

        @objc func signIn(_ button: UIButton) {
            guard controller == nil, let window = button.window, parent.onRequest() else { return }
            anchor = window
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            self.controller = controller
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            // Stored from the tapped button before performRequests; retained until completion.
            guard let anchor else { preconditionFailure("Apple authorization requires its presenting window") }
            return anchor
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            complete(.success(authorization))
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            complete(.failure(error))
        }

        private func complete(_ result: Result<ASAuthorization, Error>) {
            controller = nil
            anchor = nil
            parent.onCompletion(result)
        }
    }
}
