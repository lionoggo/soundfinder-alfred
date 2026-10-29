import XCTest
@testable import SoundFinderCore

final class AppActivationTests: XCTestCase {
    func testRequestSuccessIsNotActivationSuccess() {
        XCTAssertFalse(RunningAppActivation.verify(request: { true },
            isFrontmost: { false }, tick: {}, maximumChecks: 3))
    }

    func testWaitsForAsynchronousActivation() {
        var checks = 0
        XCTAssertTrue(RunningAppActivation.verify(request: { true },
            isFrontmost: { checks == 2 }, tick: { checks += 1 }, maximumChecks: 3))
        XCTAssertEqual(checks, 2)
    }

    func testRejectedRequestDoesNotPretendToSucceed() {
        var ticks = 0
        XCTAssertFalse(RunningAppActivation.verify(request: { false },
            isFrontmost: { true }, tick: { ticks += 1 }, maximumChecks: 3))
        XCTAssertEqual(ticks, 0)
    }
}
