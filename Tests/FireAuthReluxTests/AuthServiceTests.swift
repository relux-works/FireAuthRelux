import FireAuthKit
import FireAuthRelux
import Foundation
import Testing

@Suite
struct AuthServiceTests {
    private func makeService(
        _ stubs: [MockTransport.Stub],
        store: any FireAuthRelux.Business.SessionStore = FireAuthRelux.InMemorySessionStore(),
        refreshLeeway: TimeInterval = 60
    ) -> (FireAuthRelux.Business.AuthService, MockTransport) {
        let transport = MockTransport(stubs)
        let client = FirebaseAuthClient(apiKey: "test-key", transport: transport)
        let service = FireAuthRelux.Business.AuthService(
            client: client,
            store: store,
            refreshLeeway: refreshLeeway
        )
        return (service, transport)
    }

    @Test
    func anonymousSignInPersistsSession() async throws {
        let store = FireAuthRelux.InMemorySessionStore()
        let (service, _) = makeService([.init(json: Fixtures.anonymous)], store: store)

        let session = try await service.signInAnonymously()

        #expect(session.localId == "anon")
        #expect(session.idToken == "id")
        let current = await service.currentSession
        #expect(current?.idToken == "id")
        let stored = try await store.load()
        #expect(stored?.idToken == "id")
    }

    @Test
    func bearerTokenReturnsFreshTokenWithoutRefresh() async throws {
        let (service, transport) = makeService([.init(json: Fixtures.anonymous)])

        _ = try await service.signInAnonymously()
        let token = try await service.bearerToken()

        #expect(token == "id")
        let count = await transport.requests.count
        #expect(count == 1)
    }

    @Test
    func bearerTokenRefreshesExpiredToken() async throws {
        let (service, transport) = makeService([
            .init(json: Fixtures.anonymousExpired),
            .init(json: Fixtures.refreshed),
        ])

        _ = try await service.signInAnonymously()
        let token = try await service.bearerToken()

        #expect(token == "id2")
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.last?.url?.host == "securetoken.googleapis.com")
    }

    @Test
    func upgradeAnonymousOrSignInExistingWithEmailLinksInPlace() async throws {
        let (service, transport) = makeService([
            .init(json: Fixtures.anonymous),
            .init(json: Fixtures.linkedEmail),
        ])

        _ = try await service.signInAnonymously()
        let outcome = try await service.upgradeAnonymousOrSignInExistingWithEmail(
            email: "a@b.com",
            password: "Password1!"
        )

        #expect(outcome.mode == .linkedAnonymousAccount)
        #expect(outcome.session.email == "a@b.com")
        #expect(outcome.session.kind == .authenticated)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[1].url?.path == "/v1/accounts:signUp")
        let body = try jsonBody(requests[1])
        #expect(body["idToken"] as? String == "id")
    }

    @Test
    func signOutClearsSession() async throws {
        let store = FireAuthRelux.InMemorySessionStore()
        let (service, _) = makeService([.init(json: Fixtures.anonymous)], store: store)

        _ = try await service.signInAnonymously()
        try await service.signOut()

        let current = await service.currentSession
        #expect(current == nil)
        let stored = try await store.load()
        #expect(stored == nil)
    }

    @Test
    func unconfiguredServiceDoesNotRestoreOrVendToken() async throws {
        let store = FireAuthRelux.InMemorySessionStore(session: storedSession())
        let transport = MockTransport([])
        let client = FirebaseAuthClient(config: nil, transport: transport)
        let service = FireAuthRelux.Business.AuthService(
            client: client,
            store: store,
            isConfigured: false
        )

        let restored = try await service.restoreSession()
        let token = try await service.bearerToken()
        let requestCount = await transport.requests.count

        #expect(restored == nil)
        #expect(token == nil)
        #expect(requestCount == 0)
    }

    @Test
    func restoreSessionReturnsExpiredStoredSessionWithoutRefresh() async throws {
        let store = FireAuthRelux.InMemorySessionStore(
            session: storedSession(expiresAt: Date(timeIntervalSinceNow: -60))
        )
        let (service, transport) = makeService([.init(json: Fixtures.refreshed)], store: store)

        let restored = try await service.restoreSession()

        #expect(restored?.localId == "u")
        #expect(restored?.idToken == "id")
        let requestCount = await transport.requests.count
        #expect(requestCount == 0)
    }

    @Test
    func signOutPropagatesStoreClearErrorAndKeepsSession() async throws {
        let store = ThrowingSessionStore(throwOnClear: true)
        let (service, _) = makeService([.init(json: Fixtures.anonymous)], store: store)
        _ = try await service.signInAnonymously()

        var thrown = false
        do {
            try await service.signOut()
        } catch {
            thrown = true
        }

        #expect(thrown)
        let current = await service.currentSession
        #expect(current != nil)
    }

    @Test
    func upgradeAnonymousOrSignInExistingWithCredentialFallsBackToExistingAccount() async throws {
        let (service, transport) = makeService([
            .init(json: Fixtures.anonymous),
            .init(json: Fixtures.federatedConflict),
            .init(json: Fixtures.existingAccount),
        ])

        _ = try await service.signInAnonymously()
        let outcome = try await service.upgradeAnonymousOrSignInExistingWithCredential(.google(accessToken: "tok"))

        #expect(outcome.session.localId == "userB")
        #expect(outcome.mode == .signedIntoExistingAccount(previousAnonymousUserID: "anon"))
        let count = await transport.requests.count
        #expect(count == 3)
    }

    @Test
    func upgradeAnonymousOnNonAnonymousThrowsAndSkipsNetwork() async throws {
        let (service, transport) = makeService([.init(json: Fixtures.existingAccount)])
        _ = try await service.signIn(with: .google(accessToken: "tok"))

        var isRequiresAnonymous = false
        do {
            _ = try await service.upgradeAnonymousOrSignInExistingWithCredential(.facebook(accessToken: "tok2"))
        } catch FireAuthRelux.Business.AuthService.ServiceError.requiresAnonymousSession {
            isRequiresAnonymous = true
        } catch {}

        #expect(isRequiresAnonymous)
        let count = await transport.requests.count
        #expect(count == 1)
    }

    @Test
    func linkCurrentUserWithCredentialDoesNotFallBackOnConflict() async throws {
        let (service, transport) = makeService([
            .init(json: Fixtures.anonymous),
            .init(json: Fixtures.federatedConflict),
        ])
        _ = try await service.signInAnonymously()

        var thrown = false
        do {
            _ = try await service.linkCurrentUserWithCredential(.google(accessToken: "tok"))
        } catch {
            thrown = true
        }

        #expect(thrown)
        let count = await transport.requests.count
        #expect(count == 2)
    }

    private func storedSession(
        expiresAt: Date = Date(timeIntervalSinceNow: 3600)
    ) -> FireAuthRelux.Business.StoredSession {
        FireAuthRelux.Business.StoredSession(
            idToken: "id",
            refreshToken: "refresh",
            expiresIn: "3600",
            localId: "u",
            email: nil,
            displayName: nil,
            expiresAt: expiresAt,
            kind: .authenticated
        )
    }
}
