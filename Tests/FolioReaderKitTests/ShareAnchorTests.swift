//
//  ShareAnchorTests.swift
//  FolioReaderKitTests
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import XCTest
@testable import FolioReaderKit

class ShareAnchorTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 402, height: 874)

    func testPrefersTheSelectionRect() {
        let selection = CGRect(x: 30, y: 140, width: 50, height: 22)
        XCTAssertEqual(WebViewMenuManager.sharePresentationRect(selectionRect: selection, fallback: .zero, in: bounds), selection)
    }

    func testFallsBackToTheLastMenuRect() {
        let menu = CGRect(x: 10, y: 180, width: 300, height: 40)
        XCTAssertEqual(WebViewMenuManager.sharePresentationRect(selectionRect: .zero, fallback: menu, in: bounds), menu)
    }

    /// The zero rect anchored the share chooser under the status bar (YetAnotherEBookReader #48).
    func testNeverAnchorsAtTheZeroRect() {
        let rect = WebViewMenuManager.sharePresentationRect(selectionRect: .zero, fallback: .zero, in: bounds)
        XCTAssertNotEqual(rect, .zero)
        XCTAssertTrue(bounds.contains(rect.origin))
        let offscreen = CGRect(x: 0, y: -500, width: 40, height: 20)
        XCTAssertNotEqual(WebViewMenuManager.sharePresentationRect(selectionRect: offscreen, fallback: .zero, in: bounds), offscreen)
    }
}
