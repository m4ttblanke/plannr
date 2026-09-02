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
        auth.httpDataProvider = { _ in (Data("{}".utf8), self.http(200)) }

        _ = try await auth.send(URLRequest(url: url))
        auth.httpDataProvider = { _ in (Data("boom".utf8), self.http(500)) }
        _ = try await auth.send(URLRequest(url: url))

        XCTAssertEqual(auth.sessionExpiredCount, 0)
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
