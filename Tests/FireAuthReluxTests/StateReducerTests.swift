import FireAuthProvider
import FireAuthRelux
import Relux
import Testing

@Suite
@MainActor
struct StateReducerTests {
    @Test
    func beginSignInSetsBusy() async {
        let state = FireAuthRelux.Business.State(status: .signedOut)
        await state.reduce(with: FireAuthRelux.Business.Action.beginSignIn)
        #expect(state.status == .signingIn)
        #expect(state.isBusy)
    }

    @Test
    func signedInSetsUserAndClearsBusy() async {
        let state = FireAuthRelux.Business.State(status: .signingIn)
        let user = FireAuthProvider.User(id: "u", email: "a@b.com", displayName: "A")

        await state.reduce(with: FireAuthRelux.Business.Action.signedIn(user))

        #expect(state.user == user)
        #expect(state.status == .signedIn(user))
        #expect(!state.isBusy)
    }

    @Test
    func failedSetsErrorMessage() async {
        let state = FireAuthRelux.Business.State(status: .signingIn)
        await state.reduce(with: FireAuthRelux.Business.Action.failed("boom"))
        #expect(state.status == .failed("boom"))
        #expect(state.errorMessage == "boom")
        #expect(!state.isBusy)
    }

    @Test
    func setSignedOutClearsUser() async {
        let user = FireAuthProvider.User(id: "u", displayName: "A")
        let state = FireAuthRelux.Business.State(status: .signedIn(user))
        await state.reduce(with: FireAuthRelux.Business.Action.setSignedOut)
        #expect(state.status == .signedOut)
        #expect(state.user == nil)
    }

    @Test
    func setEmailVerifiedUpdatesFlag() async {
        let state = FireAuthRelux.Business.State(status: .signedOut)
        await state.reduce(with: FireAuthRelux.Business.Action.setEmailVerified(true))
        #expect(state.emailVerified == true)
    }

    @Test
    func upgradedRecordsAccountSwitchMode() async {
        let state = FireAuthRelux.Business.State(status: .signingIn)
        let user = FireAuthProvider.User(id: "userB", displayName: "B")
        let mode = FireAuthRelux.Business.AnonymousUpgradeMode
            .signedIntoExistingAccount(previousAnonymousUserID: "anon")

        await state.reduce(with: FireAuthRelux.Business.Action.upgraded(user, mode))

        #expect(state.status == .signedIn(user))
        #expect(state.user == user)
        #expect(state.lastUpgradeMode == mode)
    }
}
