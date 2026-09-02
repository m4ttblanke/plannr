//
//  AuthManagerDeleteAccountTests.swift
//  PlannrTests
//
//  deleteAccount() — the retry + existence-probe that recovers a deletion whose
//  success response was lost to a timeout.
//

import XCTest
@testable import Plannr

final class AuthManagerDeleteAccountTests: XCTestCase {

    private struct Timeout: Error {}

    private func makeAuth() -> AuthManager {
        // Clean UserDefaults so init() doesn't restore a session / fire a real
        // profile refresh; set the identity by hand afterwards.
        UserDefaults.standard.removeObject(forKey: "userEmail")
        let auth = AuthManager()
        auth.isGuest = false
        auth.userEmail = "user@example.com"
        return auth
    }

    private func response(_ code: Int) -> URLResponse {
        HTTPURLResponse(url: URL(string: "https://plannr-api.onrender.com/")!,
                        statusCode: code, httpVersion: nil, headerFields: nil)!
    }

    // MARK: - Happy path

    func testSuccessOnFirstDeleteMakesNoExtraCalls() async {
        let auth = makeAuth()
        var methods: [String] = []
        auth.httpDataProvider = { req in
            methods.append(req.httpMethod ?? "GET")
            return (Data("{}".utf8), self.response(200))
        }

        let ok = await auth.deleteAccount()
        XCTAssertTrue(ok)
        XCTAssertNil(auth.errorMessage)
        XCTAssertEqual(methods, ["DELETE"], "no retry, no probe when the first call succeeds")
    }

    func testGuestDeletesLocallyWithoutTouchingTheNetwork() async {
        let auth = makeAuth()
        auth.isGuest = true
        var called = false
        auth.httpDataProvider = { _ in called = true; return (Data(), self.response(200)) }

        let ok = await auth.deleteAccount()
        XCTAssertTrue(ok)
        XCTAssertFalse(called)
    }

    // MARK: - Definite server failure — reported, not retried

    func testServerErrorIsReportedWithoutRetrying() async {
        let auth = makeAuth()
        var count = 0
        auth.httpDataProvider = { _ in
            count += 1
            return (Data(#"{"error":"DB down"}"#.utf8), self.response(500))
        }

        let ok = await auth.deleteAccount()
        XCTAssertFalse(ok)
        XCTAssertEqual(auth.errorMessage, "DB down")
        XCTAssertEqual(count, 1, "a definite non-2xx answer is not retried")
    }

    // MARK: - Slow success recovery

    func testRetrySucceedsAfterFirstDeleteTimesOut() async {
        let auth = makeAuth()
        var n = 0
        auth.httpDataProvider = { _ in
            n += 1
            if n == 1 { throw Timeout() }
            return (Data("{}".utf8), self.response(200))
        }

        let ok = await auth.deleteAccount()
        XCTAssertTrue(ok)
        XCTAssertEqual(n, 2, "one retry, no probe needed")
    }

    func testBothDeletesTimeOutButProbeConfirmsAccountGone() async {
        let auth = makeAuth()
        var trail: [(method: String, isMe: Bool)] = []
        auth.httpDataProvider = { req in
            trail.append((req.httpMethod ?? "GET", req.url?.path.hasSuffix("/me") ?? false))
            if req.httpMethod == "DELETE" { throw Timeout() }
            return (Data(#"{"error":"User not authenticated."}"#.utf8), self.response(401))
        }

        let ok = await auth.deleteAccount()
        XCTAssertTrue(ok, "a lost DELETE response + a 401 from /me means the account is really gone")
        XCTAssertEqual(trail.map(\.method), ["DELETE", "DELETE", "GET"])
        XCTAssertTrue(trail.last?.isMe ?? false)
    }

    func testProbeSaysAccountStillExistsIsAFailure() async {
        let auth = makeAuth()
        auth.httpDataProvider = { req in
            if req.httpMethod == "DELETE" { throw Timeout() }
            return (Data(#"{"email":"user@example.com","name":"U","picture":""}"#.utf8), self.response(200))
        }

        let ok = await auth.deleteAccount()
        XCTAssertFalse(ok)
        XCTAssertNotNil(auth.errorMessage)
    }

    func testFullyOfflineIsAFailure() async {
        let auth = makeAuth()
        auth.httpDataProvider = { _ in throw Timeout() }

        let ok = await auth.deleteAccount()
        XCTAssertFalse(ok)
        XCTAssertEqual(auth.errorMessage,
                       "Couldn't reach the server to delete your account. Check your connection and try again.")
    }
}
