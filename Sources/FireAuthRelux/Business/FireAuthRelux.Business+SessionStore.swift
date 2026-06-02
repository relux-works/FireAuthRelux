public extension FireAuthRelux.Business {
    /// Injectable persistence boundary for the auth session.
    ///
    /// The package ships only `FireAuthRelux.InMemorySessionStore`. Apps provide their own
    /// (e.g. a Keychain-backed implementation) without the library depending on any storage SDK.
    protocol SessionStore: Sendable {
        func load() async throws -> FireAuthRelux.Business.StoredSession?
        func save(_ session: FireAuthRelux.Business.StoredSession) async throws
        func clear() async throws
    }
}
