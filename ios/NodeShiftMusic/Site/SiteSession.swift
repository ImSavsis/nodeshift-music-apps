import AuthenticationServices
import Foundation
import Observation
import UIKit

private final class AuthPresentation: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.compactMap { $0.keyWindow }.first ?? ASPresentationAnchor()
    }
}

@MainActor
@Observable
final class SiteSession {
    private(set) var user: SiteUser?
    private(set) var isBusy = false
    private(set) var lastError: String?

    @ObservationIgnored private let api = SiteAPI.shared
    @ObservationIgnored private let presentation = AuthPresentation()
    @ObservationIgnored private var webSession: ASWebAuthenticationSession?
    @ObservationIgnored var onSessionChanged: (() -> Void)?
    @ObservationIgnored var onWillLogout: (() -> Void)?
    @ObservationIgnored private var expiryObserver: NSObjectProtocol?

    init() {
        expiryObserver = NotificationCenter.default.addObserver(forName: .nsmSessionExpired, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.user != nil else { return }
                self.user = nil
                self.onSessionChanged?()
            }
        }
    }

    var isLoggedIn: Bool {
        user != nil
    }

    func restore() async {
        let schedule = Backoff.standard
        for attempt in 0..<schedule.attempts {
            guard api.hasSession, user == nil else { return }
            do {
                user = try await api.me()
                onSessionChanged?()
                return
            } catch SiteError.unauthorized {
                user = nil
                return
            } catch {
                guard attempt + 1 < schedule.attempts else { return }
                do {
                    try await Task.sleep(for: .seconds(schedule.delay(afterFailures: attempt + 1)))
                } catch {
                    return
                }
            }
        }
    }

    func login() async -> Bool {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            let url = try await api.loginURL()
            let callback = try await authenticate(url)
            guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
                  let token = components.queryItems?.first(where: { $0.name == "sso_token" })?.value,
                  let state = components.queryItems?.first(where: { $0.name == "state" })?.value else {
                throw SiteError.badCallback
            }
            let pair = try await api.ssoLogin(token: token, state: state)
            api.setTokens(access: pair.accessToken, refresh: pair.refreshToken)
            user = pair.user
            onSessionChanged?()
            return true
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return false
        } catch SiteError.badCallback {
            lastError = "Сайт не вернул данные для входа. Попробуй войти ещё раз."
            return false
        } catch {
            lastError = "Не получилось войти. Проверь интернет и попробуй ещё раз."
            return false
        }
    }

    func logout() {
        onWillLogout?()
        api.clear()
        user = nil
        onSessionChanged?()
    }

    private func authenticate(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "nodeshiftmusic") { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: error ?? SiteError.cancelled)
                }
            }
            session.presentationContextProvider = presentation
            session.prefersEphemeralWebBrowserSession = false
            webSession = session
            if !session.start() {
                continuation.resume(throwing: SiteError.cancelled)
            }
        }
    }
}
