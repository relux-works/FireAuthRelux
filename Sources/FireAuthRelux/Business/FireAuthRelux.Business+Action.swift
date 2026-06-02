import Relux

public extension FireAuthRelux.Business {
    /// Reducer actions for deterministic auth state transitions.
    enum Action: Relux.Action {
        case setUnconfigured
        case setSignedOut
        case beginRestore
        case beginSignIn
        case signedIn(User)
        case upgraded(User, AnonymousUpgradeMode)
        case beginRefresh
        case refreshed(User)
        case beginSignOut
        case failed(String)
        case setEmailVerified(Bool?)
        case reset
    }
}
