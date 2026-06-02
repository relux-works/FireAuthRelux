public extension FireAuthRelux {
    /// Default, non-persistent `SessionStore`. Holds the session for the process lifetime only.
    actor InMemorySessionStore: FireAuthRelux.Business.SessionStore {
        private var session: FireAuthRelux.Business.StoredSession?

        public init(session: FireAuthRelux.Business.StoredSession? = nil) {
            self.session = session
        }

        public func load() async throws -> FireAuthRelux.Business.StoredSession? {
            session
        }

        public func save(_ session: FireAuthRelux.Business.StoredSession) async throws {
            self.session = session
        }

        public func clear() async throws {
            session = nil
        }
    }
}
