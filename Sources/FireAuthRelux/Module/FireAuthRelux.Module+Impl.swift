import FireAuthKit
import FireAuthProvider
import Foundation
import Relux

public extension FireAuthRelux.Module {
    /// Concrete module that wires state, the Relux flow, the auth service, and token provider.
    struct Impl: FireAuthRelux.Module.Interface {
        public let state: FireAuthRelux.Business.State
        public let states: [any Relux.AnyState]
        public let sagas: [any Relux.Saga]
        public let tokenProvider: any FireAuthRelux.Business.TokenProviding

        @MainActor
        public init(
            configuration: FireAuthProvider.Configuration,
            transport: any FirebaseAuthTransport = URLSessionFirebaseAuthTransport(),
            sessionStore: any FireAuthRelux.Business.SessionStore = FireAuthRelux.InMemorySessionStore(),
            refreshLeeway: TimeInterval = 60,
            dispatcher: Relux.Dispatcher? = nil
        ) {
            let initialStatus: FireAuthRelux.Business.Status
            let client: FirebaseAuthClient
            let isConfigured: Bool

            switch configuration.status {
            case let .configured(resolved):
                client = FirebaseAuthClient(apiKey: resolved.firebaseAPIKey, transport: transport)
                initialStatus = .signedOut
                isConfigured = true
            case .missing:
                client = FirebaseAuthClient(config: nil, transport: transport)
                initialStatus = .unconfigured
                isConfigured = false
            }

            let state = FireAuthRelux.Business.State(status: initialStatus)
            let service = FireAuthRelux.Business.AuthService(
                client: client,
                store: sessionStore,
                refreshLeeway: refreshLeeway,
                isConfigured: isConfigured
            )
            let flow = FireAuthRelux.Business.Flow(
                dispatcher: dispatcher,
                state: state,
                service: service
            )

            self.state = state
            self.states = [state]
            self.sagas = [flow]
            self.tokenProvider = service
        }
    }
}
