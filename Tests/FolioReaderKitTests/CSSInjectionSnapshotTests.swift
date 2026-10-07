//
//  CSSInjectionSnapshotTests.swift
//  FolioReaderKitTests
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import XCTest
@testable import FolioReaderKit

/// Guards the base stylesheet (`folio_bundle_style`) injected into every page.
///
/// `FolioReaderCSSBuilder.levelRules()` is compared against `__Snapshots__/CSSInjectionSnapshotTests/levelStyleRules.css`.
/// To re-record after an intended change, delete that file or run with
/// `TEST_RUNNER_FOLIO_RECORD_SNAPSHOTS=1 xcodebuild test ...`, then review the diff in git.
class CSSInjectionSnapshotTests: XCTestCase {

    func testLevelStyleRulesSnapshot() {
        assertSnapshot(FolioReaderCSSBuilder.levelRules().joined(separator: "\n") + "\n", named: "levelStyleRules.css")
    }

    func testBaseStyleSheetIsStyleCSSFollowedByLevelRules() throws {
        let styleURL = try XCTUnwrap(Bundle.frameworkBundle().url(forResource: "Style", withExtension: "css"))
        let styleCSS = try String(contentsOf: styleURL)

        XCTAssertEqual(FolioReaderCSSBuilder.bundledStyleCSS, styleCSS)
        XCTAssertEqual(
            FolioReaderCSSBuilder.baseStyleSheet(),
            ([styleCSS] + FolioReaderCSSBuilder.levelRules()).joined(separator: "\n")
        )
    }
}
