import FireAuthKit
import FireAuthRelux
import Relux
import Testing

@Suite
struct EffectRedactionTests {
    @Test
    func signInEmailRedactsPassword() {
        let values = FireAuthRelux.Business.Effect
            .signInEmail(email: "a@b.com", password: "hunter2")
            .associatedValues

        #expect(!values.contains { $0.contains("hunter2") })
        #expect(values.contains("password: <redacted>"))
        #expect(values.contains("email: a@b.com"))
    }

    @Test
    func createEmailUserRedactsPassword() {
        let values = FireAuthRelux.Business.Effect
            .createEmailUser(email: "a@b.com", password: "s3cret!")
            .associatedValues

        #expect(!values.contains { $0.contains("s3cret!") })
    }

    @Test
    func upgradeAndLinkEmailRedactPassword() {
        let effects: [FireAuthRelux.Business.Effect] = [
            .upgradeAnonymousWithEmail(email: "a@b.com", password: "topSecret"),
            .linkCurrentUserWithEmail(email: "a@b.com", password: "topSecret"),
        ]
        for effect in effects {
            #expect(!effect.associatedValues.contains { $0.contains("topSecret") })
            #expect(effect.associatedValues.contains("password: <redacted>"))
        }
    }

    @Test
    func upgradeAndLinkCredentialRedacted() {
        let credential = FirebaseIDPCredential.facebook(accessToken: "FB_SECRET")
        let effects: [FireAuthRelux.Business.Effect] = [
            .upgradeAnonymousWithCredential(credential),
            .linkCurrentUserWithCredential(credential),
        ]
        for effect in effects {
            #expect(!effect.associatedValues.contains { $0.contains("FB_SECRET") })
            #expect(effect.associatedValues.contains("credential: <redacted>"))
        }
    }

    @Test
    func credentialIsRedacted() {
        let credential = FirebaseIDPCredential.google(accessToken: "ya29.SECRET_TOKEN")
        let values = FireAuthRelux.Business.Effect
            .signInWithCredential(credential)
            .associatedValues

        #expect(!values.contains { $0.contains("SECRET_TOKEN") })
        #expect(values.contains("credential: <redacted>"))
        #expect(values.contains("providerId: google.com"))
    }

    @Test
    func nonSensitiveEffectExposesNoSecrets() {
        #expect(FireAuthRelux.Business.Effect.signInAnonymously.associatedValues.isEmpty)
        #expect(
            FireAuthRelux.Business.Effect
                .sendEmailVerification(email: "a@b.com")
                .associatedValues == ["email: a@b.com"]
        )
    }
}
