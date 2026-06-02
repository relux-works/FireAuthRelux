import FireAuthProvider
import Foundation

public extension FireAuthRelux.Business {
    /// SDK-neutral user identity, reused from `FireAuthProvider`.
    typealias User = FireAuthProvider.User

    /// Whether the active session belongs to an anonymous or a real (authenticated) user.
    /// Tracked explicitly because it cannot be reliably inferred (a social user may have no email,
    /// and a token refresh response does not say which flow produced it).
    enum SessionKind: String, Sendable, Codable, Hashable {
        case anonymous
        case authenticated
    }

    /// Authentication status surfaced to the UI.
    enum Status: Sendable, Equatable {
        case unconfigured
        case signedOut
        case restoring
        case signingIn
        case signedIn(User)
        case refreshing(User)
        case signingOut
        case failed(String)

        /// The signed-in user carried by the status, if any.
        public var user: User? {
            switch self {
            case let .signedIn(user), let .refreshing(user):
                return user
            default:
                return nil
            }
        }
    }

    /// Result of an anonymous-account upgrade.
    ///
    /// - `linkedAnonymousAccount`: the provider/email was attached to the SAME Firebase user
    ///   (the anonymous uid is preserved). App-local guest data still belongs to this user.
    /// - `signedIntoExistingAccount`: the provider/email already belonged to another Firebase user,
    ///   so the session switched to that account. This is an account switch — the app must decide
    ///   what to do with the previous guest's local state.
    enum AnonymousUpgradeMode: Sendable, Hashable {
        case linkedAnonymousAccount
        case signedIntoExistingAccount(previousAnonymousUserID: String)
    }

    /// The new session plus how the upgrade resolved.
    struct AnonymousUpgradeOutcome: Sendable, Hashable {
        public let session: StoredSession
        public let mode: AnonymousUpgradeMode

        public init(session: StoredSession, mode: AnonymousUpgradeMode) {
            self.session = session
            self.mode = mode
        }
    }

    /// Persisted authentication session. Token-only — no profile or backend data.
    struct StoredSession: Codable, Sendable, Hashable {
        public let idToken: String
        public let refreshToken: String
        public let expiresIn: String
        public let localId: String
        public let email: String?
        public let displayName: String?
        /// Absolute expiry, computed at acquisition time from `expiresIn`.
        public let expiresAt: Date
        public let kind: SessionKind

        public init(
            idToken: String,
            refreshToken: String,
            expiresIn: String,
            localId: String,
            email: String?,
            displayName: String?,
            expiresAt: Date,
            kind: SessionKind
        ) {
            self.idToken = idToken
            self.refreshToken = refreshToken
            self.expiresIn = expiresIn
            self.localId = localId
            self.email = email
            self.displayName = displayName
            self.expiresAt = expiresAt
            self.kind = kind
        }

        public var isAnonymous: Bool {
            kind == .anonymous
        }

        public var user: FireAuthRelux.Business.User {
            FireAuthProvider.User(
                id: localId,
                email: email,
                displayName: displayName ?? email ?? localId
            )
        }
    }
}
