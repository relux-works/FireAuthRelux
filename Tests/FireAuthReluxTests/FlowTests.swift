import FireAuthKit
import FireAuthProvider
import FireAuthRelux
import Foundation
import Relux
import Testing

@Suite
@MainActor
struct FlowTests {
    @Test
    func restorePublishesStoredIdentityBeforeRefreshFailure() async throws {
        let store = FireAuthRelux.InMemorySessionStore(
            session: storedSession(expiresAt: Date(timeIntervalSinceNow: -60))
        )
        let transport = MockTransport([
            .init(statusCode: 500, json: #"{"error":{"message":"INTERNAL"}}"#),
        ])
        let client = FirebaseAuthClient(apiKey: "test-key", transport: transport)
        let service = FireAuthRelux.Business.AuthService(client: client, store: store)
        let logger = CapturingReluxLogger()
        let flow = FireAuthRelux.Business.Flow(
            dispatcher: Relux.Dispatcher(logger: logger),
            state: FireAuthRelux.Business.State(status: .signedOut),
            service: service
        )

        let result = await flow.apply(FireAuthRelux.Business.Effect.restoreSession)

        guard case .failure = result else {
            Issue.record("Expected refresh failure after restored identity was published")
            return
        }
        #expect(await logger.caseNames == [
            "Action.beginRestore",
            "Action.signedInWithKind",
            "Action.failed",
        ])
        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(requests[0].url?.host == "securetoken.googleapis.com")
    }

    private func storedSession(
        expiresAt: Date
    ) -> FireAuthRelux.Business.StoredSession {
        FireAuthRelux.Business.StoredSession(
            idToken: "stored-id-token",
            refreshToken: "stored-refresh-token",
            expiresIn: "0",
            localId: "stored-anonymous-uid",
            email: nil,
            displayName: nil,
            expiresAt: expiresAt,
            kind: .anonymous
        )
    }
}

private final class CapturingReluxLogger: Relux.Logger, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCaseNames: [String] = []

    var caseNames: [String] {
        get async {
            lock.withLock { recordedCaseNames }
        }
    }

    func logAction(
        _ action: any Relux.EnumReflectable,
        result _: Relux.ActionResult?,
        startTimeInMillis _: Int,
        privacy _: Relux.OSLogPrivacy,
        fileID _: String,
        functionName _: String,
        lineNumber _: Int
    ) {
        lock.withLock {
            recordedCaseNames.append(action.caseName.replacingOccurrences(of: "FireAuthRelux.Business.", with: ""))
        }
    }
}
