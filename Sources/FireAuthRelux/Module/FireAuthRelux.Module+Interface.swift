import Relux

public extension FireAuthRelux.Module {
    /// Relux module contract for the SwiftUI-free Firebase auth wrapper.
    protocol Interface: Relux.Module {
        /// Observable auth state owned by the module.
        @MainActor var state: FireAuthRelux.Business.State { get }
        /// Bearer-token provider with refresh policy, for app networking layers.
        var tokenProvider: any FireAuthRelux.Business.TokenProviding { get }
    }
}
