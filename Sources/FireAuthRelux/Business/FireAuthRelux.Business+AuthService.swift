import FireAuthKit
import Foundation

public extension FireAuthRelux.Business {
    /// Vends a bearer token, applying refresh policy. Implemented by `AuthService`.
    protocol TokenProviding: Sendable {
        func bearerToken() async throws -> String?
    }
}

public extension FireAuthRelux.Business {
    /// Auth orchestration contract: calls `FirebaseAuthClient`, persists via `SessionStore`,
    /// owns refresh policy, and performs anonymous -> real upgrades.
    ///
    /// Provider/email attachment is split by intent so the public API can't silently switch
    /// accounts: plain `signIn*`, anonymous-only `upgradeAnonymous*` (with existing-account
    /// fallback), and strict `linkCurrentUser*` (no fallback).
    protocol AuthServicing: Actor, TokenProviding {
        var currentSession: FireAuthRelux.Business.StoredSession? { get async }

        func restoreSession() async throws -> FireAuthRelux.Business.StoredSession?
        func signInAnonymously() async throws -> FireAuthRelux.Business.StoredSession
        func createEmailUser(email: String, password: String) async throws -> FireAuthRelux.Business.StoredSession
        func signInEmail(email: String, password: String) async throws -> FireAuthRelux.Business.StoredSession
        func signIn(with credential: FirebaseIDPCredential) async throws -> FireAuthRelux.Business.StoredSession

        func upgradeAnonymousWithEmail(email: String, password: String) async throws -> FireAuthRelux.Business.AnonymousUpgradeOutcome
        func upgradeAnonymousWithCredential(_ credential: FirebaseIDPCredential) async throws -> FireAuthRelux.Business.AnonymousUpgradeOutcome

        func linkCurrentUserWithEmail(email: String, password: String) async throws -> FireAuthRelux.Business.StoredSession
        func linkCurrentUserWithCredential(_ credential: FirebaseIDPCredential) async throws -> FireAuthRelux.Business.StoredSession

        func refreshIfNeeded() async throws -> FireAuthRelux.Business.StoredSession?
        func forceRefresh() async throws -> FireAuthRelux.Business.StoredSession
        func sendEmailVerification(email: String) async throws
        func checkEmailVerification() async throws -> Bool
        func signOut() async throws
        func resetLocalAuthState() async throws
    }
}

public extension FireAuthRelux.Business {
    /// Concrete auth service over `FireAuthKit`, with injectable session storage and clock.
    actor AuthService: AuthServicing {
        public enum ServiceError: Error, Sendable, Equatable {
            case noSession
            /// `upgradeAnonymous*` was called while the current session is not anonymous.
            case requiresAnonymousSession
        }

        private let client: FirebaseAuthClient
        private let store: any FireAuthRelux.Business.SessionStore
        private let refreshLeeway: TimeInterval
        private let now: @Sendable () -> Date
        private let isConfigured: Bool
        private var session: FireAuthRelux.Business.StoredSession?

        public init(
            client: FirebaseAuthClient,
            store: any FireAuthRelux.Business.SessionStore,
            refreshLeeway: TimeInterval = 60,
            isConfigured: Bool = true,
            now: @escaping @Sendable () -> Date = { Date() }
        ) {
            self.client = client
            self.store = store
            self.refreshLeeway = refreshLeeway
            self.isConfigured = isConfigured
            self.now = now
        }

        public var currentSession: FireAuthRelux.Business.StoredSession? {
            get async { session }
        }

        // MARK: - TokenProviding

        public func bearerToken() async throws -> String? {
            guard let current = try await loadedSessionIfAvailable() else { return nil }
            if isExpiring(current) {
                return try await forceRefresh().idToken
            }
            return current.idToken
        }

        // MARK: - Session lifecycle

        public func restoreSession() async throws -> FireAuthRelux.Business.StoredSession? {
            guard isConfigured else {
                session = nil
                return nil
            }
            guard let stored = try await store.load() else {
                session = nil
                return nil
            }
            session = stored
            if isExpiring(stored) {
                return try await forceRefresh()
            }
            return stored
        }

        public func signInAnonymously() async throws -> FireAuthRelux.Business.StoredSession {
            let response = try await client.signInAnonymously()
            return try await persist(response, kind: .anonymous)
        }

        public func createEmailUser(email: String, password: String) async throws -> FireAuthRelux.Business.StoredSession {
            let response = try await client.createUserWithEmailPassword(email: email, password: password)
            return try await persist(response, kind: .authenticated)
        }

        public func signInEmail(email: String, password: String) async throws -> FireAuthRelux.Business.StoredSession {
            let response = try await client.signInWithEmailPassword(email: email, password: password)
            return try await persist(response, kind: .authenticated)
        }

        public func signIn(with credential: FirebaseIDPCredential) async throws -> FireAuthRelux.Business.StoredSession {
            let response = try await client.signInWithIdp(credential)
            return try await persist(response, kind: .authenticated)
        }

        // MARK: - Anonymous upgrade (may fall back to an existing account)

        public func upgradeAnonymousWithEmail(
            email: String,
            password: String
        ) async throws -> FireAuthRelux.Business.AnonymousUpgradeOutcome {
            let current = try await requireAnonymousSession()
            let response = try await client.signInWithEmailFromAnonymous(
                anonymousIdToken: current.idToken,
                email: email,
                password: password
            )
            return try await finishUpgrade(response, previousAnonymous: current)
        }

        public func upgradeAnonymousWithCredential(
            _ credential: FirebaseIDPCredential
        ) async throws -> FireAuthRelux.Business.AnonymousUpgradeOutcome {
            let current = try await requireAnonymousSession()
            let response = try await client.signInWithIdpFromAnonymous(
                anonymousIdToken: current.idToken,
                credential: credential
            )
            return try await finishUpgrade(response, previousAnonymous: current)
        }

        // MARK: - Strict link onto the current user (never falls back)

        public func linkCurrentUserWithEmail(
            email: String,
            password: String
        ) async throws -> FireAuthRelux.Business.StoredSession {
            let current = try await requireSession()
            let response = try await client.linkWithEmailPassword(
                anonymousIdToken: current.idToken,
                email: email,
                password: password
            )
            return try await persist(response, previous: current, kind: .authenticated)
        }

        public func linkCurrentUserWithCredential(
            _ credential: FirebaseIDPCredential
        ) async throws -> FireAuthRelux.Business.StoredSession {
            let current = try await requireSession()
            let response = try await client.linkWithIdp(idToken: current.idToken, credential: credential)
            return try await persist(response, previous: current, kind: .authenticated)
        }

        // MARK: - Tokens & verification

        public func refreshIfNeeded() async throws -> FireAuthRelux.Business.StoredSession? {
            guard let current = try await loadedSessionIfAvailable() else { return nil }
            guard isExpiring(current) else { return current }
            return try await forceRefresh()
        }

        public func forceRefresh() async throws -> FireAuthRelux.Business.StoredSession {
            let current = try await requireSession()
            let response = try await client.refreshIdToken(refreshToken: current.refreshToken)
            return try await persist(response, previous: current, kind: current.kind)
        }

        public func sendEmailVerification(email: String) async throws {
            let current = try await requireSession()
            try await client.sendEmailVerification(idToken: current.idToken, email: email)
        }

        public func checkEmailVerification() async throws -> Bool {
            let current = try await requireSession()
            return try await client.checkEmailVerificationStatus(idToken: current.idToken)
        }

        public func signOut() async throws {
            try await store.clear()
            session = nil
        }

        public func resetLocalAuthState() async throws {
            try await store.clear()
            session = nil
        }

        // MARK: - Internals

        private func finishUpgrade(
            _ response: FirebaseTokenResponse,
            previousAnonymous: FireAuthRelux.Business.StoredSession
        ) async throws -> FireAuthRelux.Business.AnonymousUpgradeOutcome {
            let switchedAccount = !response.localId.isEmpty && response.localId != previousAnonymous.localId
            let mode: FireAuthRelux.Business.AnonymousUpgradeMode = switchedAccount
                ? .signedIntoExistingAccount(previousAnonymousUserID: previousAnonymous.localId)
                : .linkedAnonymousAccount
            let stored = try await persist(response, previous: previousAnonymous, kind: .authenticated)
            return FireAuthRelux.Business.AnonymousUpgradeOutcome(session: stored, mode: mode)
        }

        private func loadedSessionIfAvailable() async throws -> FireAuthRelux.Business.StoredSession? {
            guard isConfigured else { return nil }
            if let session {
                return session
            }
            let stored = try await store.load()
            session = stored
            return stored
        }

        private func requireSession() async throws -> FireAuthRelux.Business.StoredSession {
            guard let current = try await loadedSessionIfAvailable() else {
                throw ServiceError.noSession
            }
            return current
        }

        private func requireAnonymousSession() async throws -> FireAuthRelux.Business.StoredSession {
            let current = try await requireSession()
            guard current.kind == .anonymous else {
                throw ServiceError.requiresAnonymousSession
            }
            return current
        }

        private func isExpiring(_ session: FireAuthRelux.Business.StoredSession) -> Bool {
            now() >= session.expiresAt.addingTimeInterval(-refreshLeeway)
        }

        @discardableResult
        private func persist(
            _ response: FirebaseTokenResponse,
            previous: FireAuthRelux.Business.StoredSession? = nil,
            kind: FireAuthRelux.Business.SessionKind
        ) async throws -> FireAuthRelux.Business.StoredSession {
            let stored = makeSession(from: response, previous: previous, kind: kind)
            try await store.save(stored)
            session = stored
            return stored
        }

        private func makeSession(
            from response: FirebaseTokenResponse,
            previous: FireAuthRelux.Business.StoredSession?,
            kind: FireAuthRelux.Business.SessionKind
        ) -> FireAuthRelux.Business.StoredSession {
            let seconds = TimeInterval(response.expiresIn) ?? 3600
            let refreshToken = response.refreshToken.isEmpty
                ? (previous?.refreshToken ?? response.refreshToken)
                : response.refreshToken
            let localId = response.localId.isEmpty
                ? (previous?.localId ?? response.localId)
                : response.localId

            return FireAuthRelux.Business.StoredSession(
                idToken: response.idToken,
                refreshToken: refreshToken,
                expiresIn: response.expiresIn,
                localId: localId,
                email: response.email ?? previous?.email,
                displayName: response.displayName ?? previous?.displayName,
                expiresAt: now().addingTimeInterval(seconds),
                kind: kind
            )
        }
    }
}
