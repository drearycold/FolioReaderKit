//
//  SpreadLayoutTests.swift
//  FolioReaderKitTests
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import WebKit
import XCTest
@testable import FolioReaderKit

/// The two-page spread (`FolioReaderCSSBuilder.spreadRules`) laid out by WebKit: two half-width
/// columns to a screen in a wide landscape page, `-webkit-paged-x` otherwise.
@MainActor
class SpreadLayoutTests: XCTestCase {
    /// An 11" iPad in landscape and portrait, and an iPhone 17 in landscape.
    static let landscape = CGSize(width: 1194, height: 790)
    static let portrait = CGSize(width: 834, height: 1150)
    static let phoneLandscape = CGSize(width: 874, height: 402)
    static let minimumWidth: CGFloat = 1000

    private func chapter(size: CGSize = SpreadLayoutTests.landscape, margins: Int = 5, extra: String = "") -> WKWebView {
        let paragraphs = (1...160).map { index in
            "<p id=\"p\(index)\">Paragraph \(index): the quick brown fox jumps over the lazy dog, 敏捷的棕色狐狸跳过了懒狗，第\(index)段。</p>"
        }.joined()
        return readerChapter("<h1>Chapter</h1>" + extra + paragraphs, paged: true, size: size, spreadMinimumWidth: Self.minimumWidth, margins: margins)
    }

    private func columns(_ webView: WKWebView) -> Int? {
        evaluate("folioColumnsPerScreen()", in: webView) as? Int
    }

    /// The left edges of the columns `<body>` runs through, in document coordinates.
    private func columnLefts(_ webView: WKWebView) -> [Double] {
        evaluate("Array.from(document.body.getClientRects()).map(r => r.left + scrollX)", in: webView) as? [Double] ?? []
    }

    func testWideLandscapeShowsTwoColumnsAScreen() throws {
        let webView = chapter()
        let width = Self.landscape.width
        XCTAssertEqual(columns(webView), 2)

        let lefts = columnLefts(webView)
        XCTAssertGreaterThan(lefts.count, 4, "The chapter runs through several columns")
        for (index, left) in lefts.enumerated() {
            XCTAssertEqual(left, Double(index) * width / 2, accuracy: 1, "Column \(index) starts half a screen after the one before")
        }
        XCTAssertEqual(webView.scrollView.contentSize.width, CGFloat(lefts.count) * width / 2, accuracy: 1)
        XCTAssertEqual(webView.scrollView.contentSize.height, Self.landscape.height, accuracy: 1, "Nothing to scroll vertically")

        // The next screen starts with the third column.
        scrollNatively(webView, to: CGPoint(x: width, y: 0))
        let firstLeft = try XCTUnwrap(evaluate("""
            Math.min(...Array.from(document.querySelectorAll('p')).flatMap(p => Array.from(p.getClientRects()))
                .filter(r => r.right > 0 && r.left < innerWidth).map(r => r.left))
            """, in: webView) as? Double)
        XCTAssertGreaterThanOrEqual(firstLeft, 0)
        XCTAssertLessThan(firstLeft, width / 10, "Text starts at the left margin of the screen")
    }

    /// The media query follows the viewport, so rotating switches the layout without a reload.
    func testPortraitAndNarrowLandscapeKeepOnePage() {
        let webView = chapter()
        XCTAssertEqual(columns(webView), 2)

        resize(webView, to: Self.portrait, paged: true)
        XCTAssertEqual(columns(webView), 1)
        let portraitLefts = columnLefts(webView)
        XCTAssertEqual(portraitLefts.dropFirst().first ?? 0, Double(Self.portrait.width), accuracy: 1, "Pages are a screen wide")

        resize(webView, to: Self.landscape, paged: true)
        XCTAssertEqual(columns(webView), 2, "Back to two pages")

        resize(webView, to: Self.phoneLandscape, paged: true)
        XCTAssertEqual(columns(webView), 1, "Narrower than the minimum width")
    }

    func testSpreadOffIsOnePage() {
        let webView = readerChapter("<p>Text</p>", paged: true, size: Self.landscape)
        XCTAssertEqual(columns(webView), 1)
    }

    /// `updateStyleBackgroundPadding` sizes the body to whole screens, so the last screen gets both
    /// columns and the scroll view's pages line up with the screens.
    func testBackgroundPaddingFillsWholeScreens() throws {
        let webView = chapter()
        let width = Self.landscape.width
        let screens = { Int(ceil(webView.scrollView.contentSize.width / width)) }
        XCTAssertNotEqual(webView.scrollView.contentSize.width.truncatingRemainder(dividingBy: width), 0, "An odd number of columns to start with")

        var search = BackgroundPaddingSearch()
        var step = BackgroundPaddingSearch.Step(screens: screens(), shrinking: false)
        for _ in 0..<10 {
            evaluate(BackgroundPaddingSearch.script(for: step) + "; true", in: webView)
            settle(webView)
            guard let next = search.next(after: step, totalPages: screens()) else { break }
            step = next
        }
        XCTAssertEqual(screens(), step.screens)
        XCTAssertEqual(webView.scrollView.contentSize.width, CGFloat(step.screens) * width, accuracy: 1)
    }

    /// Each column gets half the margins of a full-width page: the same share of its width.
    func testMarginsAreHalvedInEachColumn() throws {
        // 30 is the iPad default, 15vw a side.
        let spread = chapter(margins: 30)
        let single = readerChapter("<p>Text</p>", paged: true, size: Self.landscape, margins: 30)
        let padding = "parseFloat(getComputedStyle(document.body).paddingLeft)"
        let spreadPadding = try XCTUnwrap(evaluate(padding, in: spread) as? Double)
        let singlePadding = try XCTUnwrap(evaluate(padding, in: single) as? Double)
        XCTAssertEqual(singlePadding, 0.15 * Self.landscape.width, accuracy: 1)
        XCTAssertEqual(spreadPadding, singlePadding / 2, accuracy: 1)
    }

    /// Wide media stay inside their column: an image `Bridge.js` marks as standing alone
    /// (`folioImg`, in a paragraph) and one the settings don't reach.
    func testImagesFitTheirColumn() throws {
        let gif = "data:image/gif;base64,R0lGODlhAQABAAAAACw="
        let images = "<p><img id=\"alone\" class=\"folioImg\" width=\"3000\" height=\"300\" src=\"\(gif)\" /></p>"
            + "<img id=\"bare\" width=\"3000\" height=\"300\" src=\"\(gif)\" />"
        let webView = chapter(margins: 30, extra: images)
        let column = Double(Self.landscape.width / 2)
        for id in ["alone", "bare"] {
            let rect = try XCTUnwrap(evaluate("""
                (function () { const r = document.getElementById('\(id)').getBoundingClientRect(); return [r.left + scrollX, r.right + scrollX]; })()
                """, in: webView) as? [Double])
            XCTAssertGreaterThan(rect[1] - rect[0], column / 2, "\(id) is scaled down, not hidden")
            XCTAssertEqual(floor(rect[0] / column), floor((rect[1] - 1) / column), "\(id) at \(rect) stays in one column")
        }
    }

    /// `getOffsetsOfElementsWithID` gives the content offset of the screen that shows each element:
    /// the spread's, also for an element in the right column.
    func testElementOffsetsPointAtTheirScreen() throws {
        for (size, expectedColumns) in [(Self.landscape, 2), (Self.portrait, 1)] {
            let webView = chapter(size: size)
            XCTAssertEqual(columns(webView), expectedColumns)
            let json = try XCTUnwrap(evaluate("getOffsetsOfElementsWithID(true)", in: webView) as? String)
            let offsets = try JSONDecoder().decode([String: Int].self, from: Data(json.utf8))
            let screens = try XCTUnwrap(evaluate("""
                JSON.stringify(Object.fromEntries(Array.from(document.querySelectorAll('p')).map(p =>
                    [p.id, innerWidth * Math.floor((p.getClientRects()[0].left + scrollX) / innerWidth)])))
                """, in: webView) as? String)
            let expected = try JSONDecoder().decode([String: Int].self, from: Data(screens.utf8))
            XCTAssertEqual(expected.count, 160)
            for (id, offset) in expected {
                XCTAssertEqual(offsets[id], offset, "\(id) at \(size)")
            }
            if expectedColumns == 2 {
                let inRightColumns = evaluate("""
                    Array.from(document.querySelectorAll('p')).filter(p => (p.getClientRects()[0].left + scrollX) % innerWidth >= innerWidth / 2).length
                    """, in: webView) as? Int ?? 0
                XCTAssertGreaterThan(inRightColumns, 10, "Right-hand columns are covered")
            }
        }
    }

    private func settle(_ webView: WKWebView) {
        let settled = expectation(description: "layout settled")
        WebViewLayoutWaiter.wait(for: webView, timeout: 3, paged: true) { _ in settled.fulfill() }
        wait(for: [settled], timeout: 5)
    }
}
