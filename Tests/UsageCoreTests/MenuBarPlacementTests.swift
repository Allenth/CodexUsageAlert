import XCTest
@testable import UsageCore

final class MenuBarPlacementTests: XCTestCase {
    func testRepairsInheritedPositionBeyondEveryConnectedScreen() {
        XCTAssertEqual(MenuBarPlacement.replacementPosition(for: 11227, screenWidths: [1512, 1920]), 240)
    }

    func testPreservesValidUserPosition() {
        XCTAssertNil(MenuBarPlacement.replacementPosition(for: 380, screenWidths: [1512]))
    }

    func testDoesNotOverrideFreshInstallationOrUnknownDisplays() {
        XCTAssertNil(MenuBarPlacement.replacementPosition(for: nil, screenWidths: [1512]))
        XCTAssertNil(MenuBarPlacement.replacementPosition(for: 11227, screenWidths: []))
    }

    func testRepairsNonfiniteAndNegativePositions() {
        XCTAssertEqual(MenuBarPlacement.replacementPosition(for: .nan, screenWidths: [1512]), 240)
        XCTAssertEqual(MenuBarPlacement.replacementPosition(for: -30, screenWidths: [1512]), 240)
    }
}
