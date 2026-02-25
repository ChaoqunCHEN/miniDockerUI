import MiniDockerCore
import XCTest

final class ContainerEventTests: XCTestCase {
    func testClassifyStart() {
        XCTAssertEqual(ContainerEvent.classify("start"), .start)
    }

    func testClassifyStop() {
        XCTAssertEqual(ContainerEvent.classify("stop"), .stop)
    }

    func testClassifyDie() {
        XCTAssertEqual(ContainerEvent.classify("die"), .die)
    }

    func testClassifyCreate() {
        XCTAssertEqual(ContainerEvent.classify("create"), .create)
    }

    func testClassifyDestroy() {
        XCTAssertEqual(ContainerEvent.classify("destroy"), .destroy)
    }

    func testClassifyPause() {
        XCTAssertEqual(ContainerEvent.classify("pause"), .pause)
    }

    func testClassifyUnpause() {
        XCTAssertEqual(ContainerEvent.classify("unpause"), .unpause)
    }

    func testClassifyRename() {
        XCTAssertEqual(ContainerEvent.classify("rename"), .rename)
    }

    func testClassifyHealthStatus() {
        XCTAssertEqual(ContainerEvent.classify("health_status"), .healthStatus)
    }

    func testClassifyUnknownAction() {
        XCTAssertNil(ContainerEvent.classify("exec_start"))
    }

    func testClassifyActionWithColonSuffix() {
        XCTAssertNil(ContainerEvent.classify("exec_start: /bin/sh"))
    }

    func testClassifyEmptyString() {
        XCTAssertNil(ContainerEvent.classify(""))
    }
}
