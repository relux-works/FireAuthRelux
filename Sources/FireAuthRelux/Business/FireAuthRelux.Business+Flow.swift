import FireAuthProvider
import Relux

public extension FireAuthRelux.Business {
    /// Relux workflow coordinator: maps `Effect`s to `AuthService` calls and dispatches `Action`s.
    actor Flow: Relux.Flow {
        public var dispatcher: Relux.Dispatcher {
            get async {
                if let injectedDispatcher {
                    return injectedDispatcher
                }
                return await Self.defaultDispatcher
            }
        }

        private let injectedDispatcher: Relux.Dispatcher?
        private let state: FireAuthRelux.Business.State
        private let service: any FireAuthRelux.Business.AuthServicing

        public init(
            dispatcher: Relux.Dispatcher? = nil,
            state: FireAuthRelux.Business.State,
            service: any FireAuthRelux.Business.AuthServicing
        ) {
            self.injectedDispatcher = dispatcher
            self.state = state
            self.service = service
        }

        @discardableResult
        public func apply(_ effect: any Relux.Effect) async -> Relux.ActionResult {
            guard let effect = effect as? FireAuthRelux.Business.Effect else { return .success }

            switch effect {
            case .restoreSession:
                return await restore()
            case .signInAnonymously:
                return await signIn { try await self.service.signInAnonymously() }
            case let .createEmailUser(email, password):
                return await signIn { try await self.service.createEmailUser(email: email, password: password) }
            case let .signInEmail(email, password):
                return await signIn { try await self.service.signInEmail(email: email, password: password) }
            case let .signInWithCredential(credential):
                return await signIn { try await self.service.signIn(with: credential) }
            case let .upgradeAnonymousWithEmail(email, password):
                return await upgrade { try await self.service.upgradeAnonymousWithEmail(email: email, password: password) }
            case let .upgradeAnonymousWithCredential(credential):
                return await upgrade { try await self.service.upgradeAnonymousWithCredential(credential) }
            case let .linkCurrentUserWithEmail(email, password):
                return await signIn { try await self.service.linkCurrentUserWithEmail(email: email, password: password) }
            case let .linkCurrentUserWithCredential(credential):
                return await signIn { try await self.service.linkCurrentUserWithCredential(credential) }
            case .refreshIfNeeded:
                return await refreshIfNeeded()
            case .forceRefresh:
                return await forceRefresh()
            case let .sendEmailVerification(email):
                return await sendEmailVerification(email: email)
            case .checkEmailVerification:
                return await checkEmailVerification()
            case .signOut:
                return await signOut()
            case .resetLocalAuthState:
                return await resetLocalAuthState()
            }
        }
    }
}

private extension FireAuthRelux.Business.Flow {
    func signIn(
        _ operation: () async throws -> FireAuthRelux.Business.StoredSession
    ) async -> Relux.ActionResult {
        _ = await actions { FireAuthRelux.Business.Action.beginSignIn }
        do {
            let session = try await operation()
            return await actions { FireAuthRelux.Business.Action.signedInWithKind(session.user, session.kind) }
        } catch {
            return await fail(error)
        }
    }

    func upgrade(
        _ operation: () async throws -> FireAuthRelux.Business.AnonymousUpgradeOutcome
    ) async -> Relux.ActionResult {
        _ = await actions { FireAuthRelux.Business.Action.beginSignIn }
        do {
            let outcome = try await operation()
            return await actions { FireAuthRelux.Business.Action.upgraded(outcome.session.user, outcome.mode) }
        } catch {
            return await fail(error)
        }
    }

    func restore() async -> Relux.ActionResult {
        _ = await actions { FireAuthRelux.Business.Action.beginRestore }
        do {
            if let session = try await service.restoreSession() {
                return await actions { FireAuthRelux.Business.Action.signedInWithKind(session.user, session.kind) }
            }
            return await actions { FireAuthRelux.Business.Action.setSignedOut }
        } catch {
            return await fail(error)
        }
    }

    func refreshIfNeeded() async -> Relux.ActionResult {
        do {
            if let session = try await service.refreshIfNeeded() {
                return await actions { FireAuthRelux.Business.Action.refreshed(session.user) }
            }
            return .success
        } catch {
            return await fail(error)
        }
    }

    func forceRefresh() async -> Relux.ActionResult {
        _ = await actions { FireAuthRelux.Business.Action.beginRefresh }
        do {
            let session = try await service.forceRefresh()
            return await actions { FireAuthRelux.Business.Action.refreshed(session.user) }
        } catch {
            return await fail(error)
        }
    }

    func sendEmailVerification(email: String) async -> Relux.ActionResult {
        do {
            try await service.sendEmailVerification(email: email)
            return .success
        } catch {
            return await fail(error)
        }
    }

    func checkEmailVerification() async -> Relux.ActionResult {
        do {
            let verified = try await service.checkEmailVerification()
            return await actions { FireAuthRelux.Business.Action.setEmailVerified(verified) }
        } catch {
            return await fail(error)
        }
    }

    func signOut() async -> Relux.ActionResult {
        _ = await actions { FireAuthRelux.Business.Action.beginSignOut }
        do {
            try await service.signOut()
            return await actions { FireAuthRelux.Business.Action.setSignedOut }
        } catch {
            // Do not surface a signed-out UI while tokens may still be persisted.
            return await fail(error)
        }
    }

    func resetLocalAuthState() async -> Relux.ActionResult {
        do {
            try await service.resetLocalAuthState()
            return await actions { FireAuthRelux.Business.Action.setSignedOut }
        } catch {
            return await fail(error)
        }
    }

    /// Computes a user-facing message in the actor context (capturing only a `Sendable` `String`
    /// into the dispatch closure), then dispatches `.failed` and surfaces the original error.
    func fail(_ error: any Error) async -> Relux.ActionResult {
        let text = (error as? any LocalizedError)?.errorDescription ?? "\(error)"
        _ = await actions { FireAuthRelux.Business.Action.failed(text) }
        return .failure(error)
    }
}
