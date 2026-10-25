import XCTest
@testable import UCCore
final class ModelTests: XCTestCase {
    func testTypedModifiersAreIndependent() {
        XCTAssertTrue(Modifiers.shift.union(.option).contains(.shift))
        XCTAssertFalse(Modifiers.shift.contains(.command))
    }
}
