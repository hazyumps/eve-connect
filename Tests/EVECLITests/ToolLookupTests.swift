import XCTest
@testable import EVECLI

final class ToolLookupTests: XCTestCase {
    func testPathValuesAreUsedOnlyWhenExecutable() {
        XCTAssertEqual(ToolLookup.resolve("/usr/bin/ghostty", searchPath: "", exists: { _ in true }), "/usr/bin/ghostty")
        XCTAssertNil(ToolLookup.resolve("/usr/bin/ghostty", searchPath: "", exists: { _ in false }))
    }

    func testBareNamesSearchPathInOrder() {
        let resolved = ToolLookup.resolve("ghostty", searchPath: "/first:/second", exists: { $0 == "/second/ghostty" })
        XCTAssertEqual(resolved, "/second/ghostty")
    }

    func testEmptyPathFallsBackToStandardDirectories() {
        XCTAssertEqual(ToolLookup.resolve("ghostty", searchPath: "", exists: { $0 == "/usr/bin/ghostty" }),
                       "/usr/bin/ghostty")
    }

    func testTildeIsExpandedBeforeLooking() {
        let resolved = ToolLookup.resolve("~/bin/eve", searchPath: "",
                                          exists: { $0.hasSuffix("/bin/eve") && !$0.hasPrefix("~") })
        XCTAssertNotNil(resolved)
        XCTAssertFalse(resolved!.hasPrefix("~"))
    }

    func testMissingProgramResolvesToNil() {
        XCTAssertNil(ToolLookup.resolve("eve-connect-not-installed-xyz", searchPath: "", exists: { _ in false }))
    }
}
