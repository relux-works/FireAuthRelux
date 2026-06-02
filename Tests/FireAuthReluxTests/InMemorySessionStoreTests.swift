import FireAuthRelux
import Foundation
import Testing

@Suite
struct InMemorySessionStoreTests {
    private func sampleSession() -> FireAuthRelux.Business.StoredSession {
        FireAuthRelux.Business.StoredSession(
            idToken: "id",
            refreshToken: "refresh",
            expiresIn: "3600",
            localId: "u",
            email: "a@b.com",
            displayName: "A",
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            kind: .authenticated
        )
    }

    @Test
    func saveThenLoadReturnsSession() async throws {
        let store = FireAuthRelux.InMemorySessionStore()
        try await store.save(sampleSession())
        let loaded = try await store.load()
        #expect(loaded?.idToken == "id")
        #expect(loaded?.email == "a@b.com")
    }

    @Test
    func clearRemovesSession() async throws {
        let store = FireAuthRelux.InMemorySessionStore(session: sampleSession())
        try await store.clear()
        let loaded = try await store.load()
        #expect(loaded == nil)
    }
}
