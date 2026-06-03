import FireAuthKit
import Relux

public extension FireAuthRelux.Business {
    /// Workflow intents handled by the auth Relux flow.
    ///
    /// Three distinct semantics for attaching a provider/email — do not conflate them:
    /// - `signIn*`: authenticate as that identity (no current session needed).
    /// - `upgradeAnonymousOrSignInExisting*`: only valid on an anonymous session; links in place,
    ///   and if the provider/email already belongs to another user, falls back to signing into
    ///   that account (see `AnonymousUpgradeMode`).
    /// - `linkCurrentUser*`: strict link onto the current user; NEVER falls back. If the
    ///   provider/email is already taken, it fails so the app can show a conflict/merge flow
    ///   instead of silently switching accounts.
    enum Effect: Relux.Effect {
        case restoreSession
        case signInAnonymously
        case createEmailUser(email: String, password: String)
        case signInEmail(email: String, password: String)
        case signInWithCredential(FirebaseIDPCredential)
        @available(
            *,
            deprecated,
            renamed: "upgradeAnonymousOrSignInExistingWithEmail(email:password:)",
            message: "This effect may switch Firebase uid. Use linkCurrentUserWithEmail unless your app has an explicit merge flow."
        )
        case upgradeAnonymousWithEmail(email: String, password: String)
        @available(
            *,
            deprecated,
            renamed: "upgradeAnonymousOrSignInExistingWithCredential(_:)",
            message: "This effect may switch Firebase uid. Use linkCurrentUserWithCredential unless your app has an explicit merge flow."
        )
        case upgradeAnonymousWithCredential(FirebaseIDPCredential)
        case upgradeAnonymousOrSignInExistingWithEmail(email: String, password: String)
        case upgradeAnonymousOrSignInExistingWithCredential(FirebaseIDPCredential)
        case linkCurrentUserWithEmail(email: String, password: String)
        case linkCurrentUserWithCredential(FirebaseIDPCredential)
        case refreshIfNeeded
        case forceRefresh
        case sendEmailVerification(email: String)
        case checkEmailVerification
        case signOut
        case resetLocalAuthState
    }
}

public extension FireAuthRelux.Business.Effect {
    /// Redacts secrets from Relux effect logging. Relux's default reflection mirrors associated
    /// values via `String(describing:)`; without this override, passwords and OAuth credentials
    /// would be written to the log when a logger is attached.
    var associatedValues: [String] {
        switch self {
        case .restoreSession,
             .signInAnonymously,
             .refreshIfNeeded,
             .forceRefresh,
             .checkEmailVerification,
             .signOut,
             .resetLocalAuthState:
            return []

        case let .createEmailUser(email, _),
             let .signInEmail(email, _),
             let .upgradeAnonymousWithEmail(email, _),
             let .upgradeAnonymousOrSignInExistingWithEmail(email, _),
             let .linkCurrentUserWithEmail(email, _):
            return ["email: \(email)", "password: <redacted>"]

        case let .signInWithCredential(credential),
             let .upgradeAnonymousWithCredential(credential),
             let .upgradeAnonymousOrSignInExistingWithCredential(credential),
             let .linkCurrentUserWithCredential(credential):
            return ["providerId: \(credential.providerId)", "credential: <redacted>"]

        case let .sendEmailVerification(email):
            return ["email: \(email)"]
        }
    }
}
