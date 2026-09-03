//
//  AuthManagerSendTests.swift
//  PlannrTests
//
//  send(_:) is the one network choke point — every backend call routes through
//  it so a 401 anywhere triggers the session-expired sign-out.
//

import XCTest
@testable import Plannr

private final class SpyAuthManager: AuthManager {
    var sessionExpiredCount = 0
    override func handleSessionExpired() { sessionExpiredCount += 1 }
}

final class AuthManagerSendTests: XCTestCase {

    private let url = URL(string: "https://plannr-api.onrender.com/calendar/sync")!

    private func http(_ code: Int) -> URLResponse {
        HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
    }

    func test401TriggersSessionExpiredAndStillReturnsTheResponse() async throws {
        let auth = SpyAuthManager()
        auth.httpDataProvider = { _ in (Data(#"{"error":"nope"}"#.utf8), self.http(401)) }

        let (data, response) = try await auth.send(URLRequest(url: url))

        XCTAssertEqual(auth.sessionExpiredCount, 1)
        XCTAssertEqual(response.statusCode, 401)
        XCTAssertFalse(data.isEmpty, "the caller still gets the body to inspect")
    }

    func testNon401DoesNotTriggerSessionExpired() async throws {
        let auth = SpyAuthManager()
        auth.retrySleep = { _ in }
        auth.httpDataProvider = { _ in (Data("{}".utf8), self.http(200)) }

        _ = try await auth.send(URLRequest(url: url))
        auth.httpDataProvider = { _ in (Data("boom".utf8), self.http(500)) }
        _ = try await auth.send(URLRequest(url: url))

        XCTAssertEqual(auth.sessionExpiredCount, 0)
    }

    // MARK: - Retry with backoff

    func testRetriesTransientServerErrorThenSucceeds() async throws {
        let auth = SpyAuthManager()
        auth.retrySleep = { _ in }
        var calls = 0
        auth.httpDataProvider = { _ in
            calls += 1
            return calls < 3
                ? (Data("try later".utf8), self.http(503))
                : (Data("{}".utf8), self.http(200))
        }

        let (_, response) = try await auth.send(URLRequest(url: url))

        XCTAssertEqual(calls, 3, "two retries after the initial attempt")
        XCTAssertEqual(response.statusCode, 200)
    }

    func testGivesUpAfterMaxAttemptsAndReturnsTheLastResponse() async throws {
        let auth = SpyAuthManager()
        auth.retrySleep = { _ in }
        var calls = 0
        auth.httpDataProvider = { _ in
            calls += 1
            return (Data("still down".utf8), self.http(502))
        }

        let (_, response) = try await auth.send(URLRequest(url: url))

        XCTAssertEqual(calls, auth.maxSendAttempts)
        XCTAssertEqual(response.statusCode, 502, "the caller still gets the failure to show")
    }

    func testDoesNotRetryAClientError() async throws {
        let auth = SpyAuthManager()
        auth.retrySleep = { _ in }
        var calls = 0
        auth.httpDataProvider = { _ in
            calls += 1
            return (Data(#"{"error":"bad"}"#.utf8), self.http(400))
        }

        let (_, response) = try await auth.send(URLRequest(url: url))

        XCTAssertEqual(calls, 1)
        XCTAssertEqual(response.statusCode, 400)
    }

    func testDoesNotRetry401() async throws {
        let auth = SpyAuthManager()
        auth.retrySleep = { _ in }
        var calls = 0
        auth.httpDataProvider = { _ in
            calls += 1
            return (Data(), self.http(401))
        }

        _ = try await auth.send(URLRequest(url: url))

        XCTAssertEqual(calls, 1, "a 401 is terminal — no retry")
        XCTAssertEqual(auth.sessionExpiredCount, 1)
    }

    func testRetriesARetryableTransportErrorThenSucceeds() async throws {
        let auth = SpyAuthManager()
        auth.retrySleep = { _ in }
        var calls = 0
        auth.httpDataProvider = { _ in
            calls += 1
            if calls == 1 { throw URLError(.timedOut) }
            return (Data("{}".utf8), self.http(200))
        }

        let (_, response) = try await auth.send(URLRequest(url: url))

        XCTAssertEqual(calls, 2)
        XCTAssertEqual(response.statusCode, 200)
    }

    func testDoesNotRetryANonURLErrorThrow() async {
        struct Boom: Error {}
        let auth = SpyAuthManager()
        auth.retrySleep = { _ in }
        var calls = 0
        auth.httpDataProvider = { _ in calls += 1; throw Boom() }

        do {
            _ = try await auth.send(URLRequest(url: url))
            XCTFail("expected the error to propagate")
        } catch is Boom {
            XCTAssertEqual(calls, 1)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testBackoffHonoursRetryAfterHeaderClampedToTheCap() {
        XCTAssertEqual(AuthManager.backoffDelay(attempt: 1, retryAfter: "2"), 2)
        XCTAssertEqual(AuthManager.backoffDelay(attempt: 5, retryAfter: "999"), 8, "clamped")
        // No header → exponential (0.6 * 2^(n-1)) plus <=0.4s jitter, capped at 8.
        XCTAssertGreaterThanOrEqual(AuthManager.backoffDelay(attempt: 1, retryAfter: nil), 0.6)
        XCTAssertLessThanOrEqual(AuthManager.backoffDelay(attempt: 10, retryAfter: nil), 8.4)
    }

    func testNonHTTPResponseThrows() async {
        let auth = SpyAuthManager()
        auth.httpDataProvider = { _ in
            (Data(), URLResponse(url: self.url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
        }

        do {
            _ = try await auth.send(URLRequest(url: url))
            XCTFail("expected a thrown error for a non-HTTP response")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .badServerResponse)
        }
        XCTAssertEqual(auth.sessionExpiredCount, 0)
    }

    func testTransportErrorPropagates() async {
        struct Boom: Error {}
        let auth = SpyAuthManager()
        auth.httpDataProvider = { _ in throw Boom() }

        do {
            _ = try await auth.send(URLRequest(url: url))
            XCTFail("expected the transport error to propagate")
        } catch is Boom {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
