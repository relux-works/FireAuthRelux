/// SDK-neutral, SwiftUI-free Relux wrapper around FireAuthKit.
///
/// `FireAuthRelux` owns the auth state machine (`Business.State`/`Action`/`Effect`/`Flow`),
/// a refresh-policy-owning `Business.AuthService`, and an injectable `Business.SessionStore`.
/// It imports no SwiftUI: an app reads `Business.State`, dispatches `Business.Effect`, and
/// renders its own auth gate.
///
/// Social credential acquisition (OAuth + UI presentation) is intentionally NOT part of this
/// package. The app obtains a `FirebaseIDPCredential` directly via `FireAuthKitSocial` and
/// dispatches `Business.Effect.signInWithCredential` / `.linkCurrentUserWithCredential`.
public enum FireAuthRelux {
    public enum Business {
        public enum Model {}
    }

    public enum Module {}
}
