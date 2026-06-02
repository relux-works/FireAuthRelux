import FireAuthProvider
import Relux

public extension FireAuthRelux.Business {
    /// Observable, main-actor auth state owned by the module and read by app UI.
    @MainActor
    @Observable
    final class State: Relux.HybridState {
        public private(set) var status: Status
        public private(set) var user: User?
        public private(set) var isBusy: Bool
        public private(set) var errorMessage: String?
        public private(set) var emailVerified: Bool?
        /// How the most recent anonymous upgrade resolved, if any. Lets the UI detect an account
        /// switch (`signedIntoExistingAccount`) vs an in-place link. Cleared on the next auth flow.
        public private(set) var lastUpgradeMode: AnonymousUpgradeMode?
        /// Whether the current session is anonymous or an authenticated account; `nil` when there
        /// is no session (signed out / unconfigured / not yet established). Lets app UI gate flows
        /// that require a real account (e.g. purchases) without inspecting the user model.
        public private(set) var sessionKind: SessionKind?

        /// Convenience: there is a session and it is anonymous.
        public var isAnonymous: Bool { sessionKind == .anonymous }

        public init(status: Status = .signedOut) {
            self.status = status
            self.user = status.user
            self.isBusy = false
            self.errorMessage = nil
            self.emailVerified = nil
            self.lastUpgradeMode = nil
            // Kind is not inferable from `status` alone; the live flow sets it via `.signedIn`.
            self.sessionKind = nil
        }

        public func reduce(with action: any Relux.Action) async {
            guard let action = action as? FireAuthRelux.Business.Action else { return }
            internalReduce(with: action)
        }

        public func cleanup() async {
            internalReduce(with: .reset)
        }
    }
}

private extension FireAuthRelux.Business.State {
    func internalReduce(with action: FireAuthRelux.Business.Action) {
        switch action {
        case .setUnconfigured:
            status = .unconfigured
            user = nil
            isBusy = false
            errorMessage = nil
            emailVerified = nil
            lastUpgradeMode = nil
            sessionKind = nil

        case .setSignedOut:
            status = .signedOut
            user = nil
            isBusy = false
            errorMessage = nil
            emailVerified = nil
            lastUpgradeMode = nil
            sessionKind = nil

        case .beginRestore:
            status = .restoring
            isBusy = true
            errorMessage = nil
            lastUpgradeMode = nil

        case .beginSignIn:
            status = .signingIn
            isBusy = true
            errorMessage = nil
            lastUpgradeMode = nil

        case let .signedIn(user):
            // Deprecated, source-compat path: no SessionKind carried, so preserve pre-1.1.0
            // behavior and leave `sessionKind` unset (isAnonymous stays false). New callers use
            // `.signedInWithKind` to populate the kind.
            status = .signedIn(user)
            self.user = user
            isBusy = false
            errorMessage = nil

        case let .signedInWithKind(user, kind):
            status = .signedIn(user)
            self.user = user
            isBusy = false
            errorMessage = nil
            sessionKind = kind

        case let .upgraded(user, mode):
            status = .signedIn(user)
            self.user = user
            isBusy = false
            errorMessage = nil
            lastUpgradeMode = mode
            // An anonymous upgrade always resolves to an authenticated account.
            sessionKind = .authenticated

        case .beginRefresh:
            if let user {
                status = .refreshing(user)
            }
            isBusy = true
            errorMessage = nil

        case let .refreshed(user):
            status = .signedIn(user)
            self.user = user
            isBusy = false
            errorMessage = nil

        case .beginSignOut:
            status = .signingOut
            isBusy = true
            errorMessage = nil

        case let .failed(message):
            status = .failed(message)
            isBusy = false
            errorMessage = message

        case let .setEmailVerified(value):
            emailVerified = value

        case .reset:
            status = .signedOut
            user = nil
            isBusy = false
            errorMessage = nil
            emailVerified = nil
            lastUpgradeMode = nil
            sessionKind = nil
        }
    }
}
