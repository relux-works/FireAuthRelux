import FireAuthKit
import FireAuthRelux
import Foundation

/// Queue-based `FirebaseAuthTransport` for deterministic auth tests. Records requests and
/// returns stubbed JSON responses in order.
actor MockTransport: FirebaseAuthTransport {
    struct Stub: Sendable {
        let statusCode: Int
        let json: String

        init(statusCode: Int = 200, json: String) {
            self.statusCode = statusCode
            self.json = json
        }
    }

    private(set) var requests: [URLRequest] = []
    private var stubs: [Stub]

    init(_ stubs: [Stub]) {
        self.stubs = stubs
    }

    func data(for request: URLRequest) async throws -> FirebaseAuthTransportResponse {
        requests.append(request)
        let stub = stubs.isEmpty ? Stub(json: "{}") : stubs.removeFirst()
        return FirebaseAuthTransportResponse(data: Data(stub.json.utf8), statusCode: stub.statusCode)
    }
}

func jsonBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

enum Fixtures {
    static let anonymous = """
    {"idToken": "id", "refreshToken": "refresh", "expiresIn": "3600", "localId": "anon"}
    """

    static let anonymousExpired = """
    {"idToken": "id", "refreshToken": "refresh", "expiresIn": "0", "localId": "anon"}
    """

    static let refreshed = """
    {"access_token": "a", "expires_in": "3600", "token_type": "Bearer",
     "refresh_token": "refresh2", "id_token": "id2", "user_id": "anon"}
    """

    static let linkedEmail = """
    {"idToken": "id2", "refreshToken": "refresh2", "expiresIn": "3600",
     "localId": "anon", "email": "a@b.com"}
    """

    /// `signInWithIdp` with `returnIdpCredential: true` returns this as HTTP 200 + errorMessage
    /// when the provider already belongs to another Firebase user.
    static let federatedConflict = """
    {"errorMessage": "FEDERATED_USER_ID_ALREADY_LINKED",
     "federatedId": "google.com:123", "providerId": "google.com"}
    """

    /// A different Firebase user (distinct localId) — the account a fallback sign-in lands on.
    static let existingAccount = """
    {"idToken": "idB", "refreshToken": "refreshB", "expiresIn": "3600",
     "localId": "userB", "email": "b@b.com"}
    """
}

struct StoreError: Error {}

/// `SessionStore` that can fail on `clear()`, to exercise the sign-out error path.
actor ThrowingSessionStore: FireAuthRelux.Business.SessionStore {
    private var session: FireAuthRelux.Business.StoredSession?
    private let throwOnClear: Bool

    init(session: FireAuthRelux.Business.StoredSession? = nil, throwOnClear: Bool = true) {
        self.session = session
        self.throwOnClear = throwOnClear
    }

    func load() async throws -> FireAuthRelux.Business.StoredSession? { session }
    func save(_ session: FireAuthRelux.Business.StoredSession) async throws { self.session = session }
    func clear() async throws {
        if throwOnClear { throw StoreError() }
        session = nil
    }
}

import Testing
