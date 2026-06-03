# FireAuthRelux

A SwiftUI-free [Relux](https://github.com/relux-works/swift-relux) wrapper around
[FireAuthKit](https://github.com/relux-works/FireAuthKit): an auth state machine, a refresh-policy
service, and an injectable session store — with no UI and no backend bridge.

## Scope

`FireAuthRelux` owns the Relux pieces (`State` / `Action` / `Effect` / `Flow`), an
`AuthService` actor that calls FireAuthKit and applies token refresh policy, and a `SessionStore`
abstraction. The app reads `State`, dispatches `Effect`, and renders its own auth gate.

It imports **no** SwiftUI, no Keychain, no HTTP client, and contains no backend/profile sync. Social
credential acquisition (OAuth + UI) stays in the app via `FireAuthKitSocial`; the app produces a
`FirebaseIDPCredential` and dispatches `signInWithCredential` /
`upgradeAnonymousOrSignInExistingWithCredential` /
`linkCurrentUserWithCredential`.

## Auth semantics (three distinct families)

These are deliberately separated so the public API cannot silently switch accounts:

| Family | Meaning | On conflict (provider/email already taken) |
|---|---|---|
| `signIn*` | Authenticate as that identity | n/a |
| `upgradeAnonymousOrSignInExisting*` | **Only** valid on an anonymous session; links in place | Falls back to signing into the existing account |
| `linkCurrentUser*` | Strict link onto the current user | **Throws** — no fallback (app shows conflict/merge) |

`upgradeAnonymousOrSignInExisting*` returns an `AnonymousUpgradeOutcome`:

- `.linkedAnonymousAccount` — same Firebase uid; guest data still belongs to this user.
- `.signedIntoExistingAccount(previousAnonymousUserID:)` — an account switch; the app decides what
  to do with the previous guest's local state.

This is also surfaced reactively via `State.lastUpgradeMode`.

The older `upgradeAnonymous*` effects and concrete `AuthService` methods are compatibility aliases
for `upgradeAnonymousOrSignInExisting*`. Prefer `linkCurrentUser*` unless the app has an explicit
merge flow for account switches.

## State

```swift
@Observable @MainActor final class State: Relux.HybridState {
    var status: Status            // unconfigured / signedOut / restoring / signingIn /
                                  // signedIn(User) / refreshing(User) / signingOut / failed(String)
    var user: User?
    var isBusy: Bool
    var errorMessage: String?
    var emailVerified: Bool?
    var lastUpgradeMode: AnonymousUpgradeMode?
}
```

## Effects

`restoreSession`, `signInAnonymously`, `createEmailUser`, `signInEmail`, `signInWithCredential`,
`upgradeAnonymousOrSignInExistingWithEmail`,
`upgradeAnonymousOrSignInExistingWithCredential`, `linkCurrentUserWithEmail`,
`linkCurrentUserWithCredential`, `refreshIfNeeded`, `forceRefresh`, `sendEmailVerification`,
`checkEmailVerification`, `signOut`, `resetLocalAuthState`.

Secrets (passwords, OAuth credentials) are redacted from Relux's effect logging.

## Session storage

```swift
public protocol SessionStore: Sendable {
    func load() async throws -> StoredSession?
    func save(_ session: StoredSession) async throws
    func clear() async throws
}
```

The package ships only `FireAuthRelux.InMemorySessionStore`. Apps provide their own (e.g. a
Keychain-backed store) without the library depending on any storage SDK. `StoredSession` carries an
explicit `SessionKind` (`.anonymous` / `.authenticated`), preserved across token refresh.

## Module

```swift
public protocol Interface: Relux.Module {
    @MainActor var state: FireAuthRelux.Business.State { get }
    var tokenProvider: any FireAuthRelux.Business.TokenProviding { get }
}
```

`FireAuthRelux.Module.Impl(configuration:transport:sessionStore:refreshLeeway:dispatcher:)` wires the
state, flow, service, and token provider. `tokenProvider.bearerToken()` applies the refresh policy
(refreshes when the token is within `refreshLeeway` of expiry).

## Relux integration

```text
SwiftUI -> Relux SideEffect -> Relux Flow -> AuthService
    -> FireAuthKit -> Firebase REST
```

The app owns token persistence (the `SessionStore`), state observation, refresh timing, and any
backend sync. The auth gate is app UI, not part of this package.

## Installation

```swift
.package(url: "https://github.com/relux-works/FireAuthRelux.git", .upToNextMajor(from: "1.0.0"))
```

## License

MIT — see [LICENSE](LICENSE).
