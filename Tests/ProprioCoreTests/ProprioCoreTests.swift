import XCTest
@testable import ProprioCore

final class ProprioCoreTests: XCTestCase {
    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        let analyzer = MotionAnalyzer()
        XCTAssertNotNil(analyzer, "MotionAnalyzer should be initialized")
    }
}
