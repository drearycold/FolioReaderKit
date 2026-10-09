//
//  BackgroundPaddingSearchTests.swift
//  FolioReaderKitTests
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import XCTest
@testable import FolioReaderKit

/// `updateStyleBackgroundPadding` sizes the body of a vertical-writing chapter in screens (`vw`) and
/// counts the pages again until they match. These tests run its search against a model of WebKit's
/// pagination: the body is at least the chapter's own width, and pages are `pageWidth` wide.
final class BackgroundPaddingSearchTests: XCTestCase {
    typealias Step = BackgroundPaddingSearch.Step

    private let screenWidth = 780.0

    /// The page count FolioReaderPage measures: the content width over the screen width.
    private func pages(after step: Step, chapterWidth: Double, pageWidth: Double) -> Int {
        let bodyWidth = Double(step.screens - (step.shrinking ? 2 : 0)) * screenWidth
        let contentWidth = (max(bodyWidth, chapterWidth) / pageWidth).rounded(.up) * pageWidth
        return Int((contentWidth / screenWidth).rounded(.up))
    }

    /// The steps the search takes from `startingPages`, and the page count after the last one.
    private func search(startingPages: Int, chapterWidth: Double, pageWidth: Double) -> (steps: [Step], pages: Int) {
        var search = BackgroundPaddingSearch()
        var steps = [Step]()
        var pages = startingPages
        var step: Step? = Step(screens: startingPages, shrinking: true)
        while let current = step, steps.count < 1000 {
            steps.append(current)
            pages = self.pages(after: current, chapterWidth: chapterWidth, pageWidth: pageWidth)
            step = search.next(after: current, totalPages: pages)
        }
        return (steps, pages)
    }

    func testScreenWidePagesEndWithTheBodyFillingThePages() {
        let result = search(startingPages: 34, chapterWidth: 32.9 * screenWidth, pageWidth: screenWidth)

        XCTAssertEqual(result.steps, [
            Step(screens: 34, shrinking: true),
            Step(screens: 33, shrinking: true),
            Step(screens: 33, shrinking: false),
        ])
        XCTAssertEqual(result.pages, 33)
    }

    /// A body sized from a stale, larger count shrinks two screens a step down to the chapter.
    func testLongShrinksAreNotCutShort() {
        let result = search(startingPages: 64, chapterWidth: 0.5 * screenWidth, pageWidth: screenWidth)

        XCTAssertEqual(result.steps.last, Step(screens: 1, shrinking: false))
        XCTAssertEqual(result.pages, 1)
    }

    /// The reported case: an iPad Pro 10.5" in landscape laid out 781 px pages on 780 pt screens.
    /// A body of n screens then counts n + 1 pages, so the search went round forever:
    /// (34, shrinking) → (34) → (35, shrinking) → (34, shrinking) → (34) → …
    func testPagesWiderThanTheScreenEndTheSearch() {
        let pageWidth = screenWidth + 1
        let result = search(startingPages: 34, chapterWidth: 32.9 * pageWidth, pageWidth: pageWidth)

        XCTAssertEqual(result.steps, [
            Step(screens: 34, shrinking: true),
            Step(screens: 34, shrinking: false),
            Step(screens: 35, shrinking: true),
        ])
    }
}
