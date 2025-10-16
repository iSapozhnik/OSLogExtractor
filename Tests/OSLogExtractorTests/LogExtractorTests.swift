import XCTest
@testable import OSLogExtractor

final class LogExtractorTests: XCTestCase {
    func testFilterInitialization() {
        let f = LogFilter(contains: "hello")
        XCTAssertEqual(f.contains, "hello")
    }
}
