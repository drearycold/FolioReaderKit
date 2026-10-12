//
//  TieredPagesTests.swift
//  FolioReaderKitTests
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import WebKit
import XCTest
@testable import FolioReaderKit

/// Vertical writing in `.vertical` ("Tiered", `FolioReaderCSSBuilder.tieredRules`) laid out by
/// WebKit: screens that run down, two tiers to a tall portrait screen, one above the other, and one
/// page to a landscape one. As in the reader, the overflow is `scroll` and the scroll view pages.
@MainActor
class TieredPagesTests: XCTestCase {
    /// An iPad mini page in portrait and landscape.
    static let portrait = CGSize(width: 744, height: 1080)
    static let landscape = CGSize(width: 1133, height: 690)

    static let tiersMinimumHeight: CGFloat = 1000

    private func chapter(size: CGSize = TieredPagesTests.portrait, margins: Int = 5, extra: String = "") -> WKWebView {
        let paragraphs = (1...160).map { index in
            "<p id=\"p\(index)\">第\(index)段：敏捷的棕色狐狸跳过了懒狗，吾輩は猫である。名前はまだ無い。</p>"
        }.joined()
        let webView = readerChapter("<h1 id=\"top\">第一章</h1>" + extra + paragraphs, paged: false, verticalWriting: true, size: size, tiersMinimumHeight: Self.tiersMinimumHeight, margins: margins)
        evaluate("""
            function __screenOf(offsetComponent) {
                return Math.floor(getAnchorOffset("epubcfi(/6/2" + offsetComponent + ")", true) / window.innerHeight);
            }
            function __screen() { return Math.round(window.scrollY / window.innerHeight); }
            true
            """, in: webView)
        return webView
    }

    /// The boxes `<body>` is broken into, in document coordinates.
    private func bodyBoxes(_ webView: WKWebView) -> [[Double]] {
        evaluate("Array.from(document.body.getClientRects()).map(r => [r.left + scrollX, r.top + scrollY, r.width, r.height])", in: webView) as? [[Double]] ?? []
    }

    private func show(screen: Int, in webView: WKWebView, file: StaticString = #filePath, line: UInt = #line) {
        scrollNatively(webView, to: CGPoint(x: 0, y: CGFloat(screen) * webView.bounds.height), file: file, line: line)
    }

    private func middle(in webView: WKWebView) throws -> String {
        let json = try XCTUnwrap(evaluate("getVisibleMiddleCFI(true)", in: webView) as? String)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertTrue((object["message"] as? String ?? "").hasPrefix("middle "), "Found the middle, no fallback: \(json)")
        return try XCTUnwrap(object["offsetComponent"] as? String)
    }

    /// Sizes the body to whole screens the way `updateStyleBackgroundPadding` does, starting from the
    /// screens the content needs.
    private func fillWholeScreens(_ webView: WKWebView) -> Int {
        let height = webView.bounds.height
        let screens = { Int(ceil(webView.scrollView.contentSize.height / height)) }
        var search = BackgroundPaddingSearch()
        var step = BackgroundPaddingSearch.Step(screens: screens(), shrinking: false)
        for _ in 0..<10 {
            evaluate(BackgroundPaddingSearch.script(for: step) + "; true", in: webView)
            settle(webView)
            guard let next = search.next(after: step, totalPages: screens()) else { break }
            step = next
        }
        return step.screens
    }

    private func settle(_ webView: WKWebView) {
        let settled = expectation(description: "layout settled")
        WebViewLayoutWaiter.wait(for: webView, timeout: 3, paged: false) { _ in settled.fulfill() }
        wait(for: [settled], timeout: 5)
    }

    // MARK: - Layout

    func testTwoTiersAScreenRunningDown() throws {
        let webView = chapter()
        let size = Self.portrait
        XCTAssertEqual(evaluate("folioPagesDown()", in: webView) as? Bool, true)

        let boxes = bodyBoxes(webView)
        XCTAssertGreaterThan(boxes.count, 6, "The chapter runs through several tiers")
        for (index, box) in boxes.enumerated() {
            XCTAssertEqual(box[1], Double(index) * size.height / 2, accuracy: 1, "Tier \(index) starts half a screen below the one before")
            // The last tier is only as wide as the text left for it.
            if index < boxes.count - 1 {
                XCTAssertEqual(box[0], 0, accuracy: 1, "Tier \(index) spans the width")
                XCTAssertEqual(box[2], size.width, accuracy: 1)
            }
        }
        XCTAssertEqual(webView.scrollView.contentSize.width, size.width, accuracy: 1, "Nothing to scroll sideways")

        // The second screen starts with the third tier.
        show(screen: 1, in: webView)
        let tops = try XCTUnwrap(evaluate("""
            Array.from(document.querySelectorAll('p')).flatMap(p => Array.from(p.getClientRects()))
                .filter(r => r.bottom > 0 && r.top < innerHeight).map(r => r.top)
            """, in: webView) as? [Double])
        let firstTop = try XCTUnwrap(tops.min())
        XCTAssertGreaterThanOrEqual(firstTop, 0)
        XCTAssertLessThan(firstTop, size.height / 10, "Text starts at the top of the screen")
    }

    /// A landscape page (or one shorter than the minimum height) shows one page a screen, running down.
    func testLandscapeShowsOnePageAScreenRunningDown() {
        let webView = chapter(size: Self.landscape)
        let size = Self.landscape
        XCTAssertEqual(evaluate("folioPagesDown()", in: webView) as? Bool, true)
        XCTAssertEqual(evaluate("folioColumnsPerScreen()", in: webView) as? Int, 1)
        let boxes = bodyBoxes(webView)
        XCTAssertGreaterThan(boxes.count, 3)
        for (index, box) in boxes.enumerated() {
            XCTAssertEqual(box[1], Double(index) * size.height, accuracy: 1, "Page \(index) starts a screen below the one before")
        }
        XCTAssertEqual(webView.scrollView.contentSize.width, size.width, accuracy: 1, "Nothing to scroll sideways")
        let screens = fillWholeScreens(webView)
        XCTAssertEqual(webView.scrollView.contentSize.height, CGFloat(screens) * size.height, accuracy: 1)

        resize(webView, to: Self.portrait, paged: false)
        XCTAssertEqual(evaluate("folioColumnsPerScreen()", in: webView) as? Int, 2, "Two tiers again in portrait")
    }

    /// `updateStyleBackgroundPadding` fills the last screen, both tiers, so pages line up with screens.
    func testBackgroundPaddingFillsWholeScreens() {
        let webView = chapter()
        let height = Self.portrait.height
        // Start from a chapter that ends part way down a screen.
        for _ in 0..<20 where webView.scrollView.contentSize.height.truncatingRemainder(dividingBy: height) == 0 {
            evaluate("document.body.insertAdjacentHTML('beforeend', '<p>追加の段落：吾輩は猫である。</p>'); true", in: webView)
            settle(webView)
        }
        XCTAssertNotEqual(webView.scrollView.contentSize.height.truncatingRemainder(dividingBy: height), 0, "An odd number of tiers to start with")
        let screens = fillWholeScreens(webView)
        XCTAssertEqual(webView.scrollView.contentSize.height, CGFloat(screens) * height, accuracy: 1)
        XCTAssertEqual(Int(ceil(webView.scrollView.contentSize.height / height)), screens)
    }

    /// Each tier gets half the top and bottom margins of a full-height page.
    func testMarginsAreHalvedInEachTier() throws {
        let tiered = chapter(margins: 20)
        let single = readerChapter("<p>縦書き</p>", paged: true, verticalWriting: true, size: Self.portrait, margins: 20)
        let padding = "parseFloat(getComputedStyle(document.body).paddingTop)"
        let tieredPadding = try XCTUnwrap(evaluate(padding, in: tiered) as? Double)
        let singlePadding = try XCTUnwrap(evaluate(padding, in: single) as? Double)
        XCTAssertEqual(singlePadding, 0.1 * Self.portrait.height, accuracy: 1)
        XCTAssertEqual(tieredPadding, singlePadding / 2, accuracy: 1)
    }

    func testImagesFitTheirTier() throws {
        let gif = "data:image/gif;base64,R0lGODlhAQABAAAAACw="
        let images = "<p><img id=\"alone\" class=\"folioImg\" width=\"300\" height=\"3000\" src=\"\(gif)\" /></p>"
            + "<img id=\"bare\" width=\"300\" height=\"3000\" src=\"\(gif)\" />"
        let webView = chapter(margins: 20, extra: images)
        let tier = Double(Self.portrait.height / 2)
        for id in ["alone", "bare"] {
            let rect = try XCTUnwrap(evaluate("""
                (function () { const r = document.getElementById('\(id)').getBoundingClientRect(); return [r.top + scrollY, r.bottom + scrollY]; })()
                """, in: webView) as? [Double])
            XCTAssertGreaterThan(rect[1] - rect[0], tier / 2, "\(id) is scaled down, not hidden")
            XCTAssertEqual(floor(rect[0] / tier), floor((rect[1] - 1) / tier), "\(id) at \(rect) stays in one tier")
        }
    }

    /// `getOffsetsOfElementsWithID` gives the content offset (in y) of the screen that shows each
    /// element: scrolled there, the element starts on screen.
    func testElementOffsetsPointAtTheirScreen() throws {
        let webView = chapter()
        let height = Int(Self.portrait.height)
        let json = try XCTUnwrap(evaluate("getOffsetsOfElementsWithID(false)", in: webView) as? String)
        let offsets = try JSONDecoder().decode([String: Int].self, from: Data(json.utf8))
        XCTAssertEqual(offsets.filter { $0.key.hasPrefix("p") }.count, 160)
        XCTAssertGreaterThan(Set(offsets.values).count, 3)
        for index in stride(from: 1, through: 160, by: 23) {
            let id = "p\(index)"
            let offset = try XCTUnwrap(offsets[id], id)
            XCTAssertEqual(offset % height, 0, "\(id) at \(offset) is a screen's offset")
            scrollNatively(webView, to: CGPoint(x: 0, y: offset))
            let top = try XCTUnwrap(evaluate("document.getElementById('\(id)').getClientRects()[0].top", in: webView) as? Double)
            XCTAssertGreaterThanOrEqual(top, 0, "\(id) starts on the screen at \(offset)")
            XCTAssertLessThan(top, Double(height), "\(id) starts on the screen at \(offset)")
        }
    }

    // MARK: - Positions

    /// The middle of a screen's text restores to that screen.
    func testMiddleIsOnTheCurrentScreen() throws {
        let webView = chapter()
        var middles = Set<String>()
        for screen in [1, 3, 5] {
            show(screen: screen, in: webView)
            let position = try middle(in: webView)
            middles.insert(position)
            // Measured from another screen: a measurement that returned the current offset would pass otherwise.
            show(screen: 0, in: webView)
            XCTAssertEqual(evaluate("__screenOf('\(position)')", in: webView) as? Int, screen, "Restoring the middle shows screen \(screen)")
        }
        XCTAssertEqual(middles.count, 3)
    }

    /// Rotating switches between two tiers in portrait and one page in landscape, both running down;
    /// going back and forth must keep the reader on the screen. Two round trips: off-screen web views
    /// in the test runner stall more the longer a test runs (the WebContent process gets suspended),
    /// and the drift this guards against showed within two.
    func testRepeatedRotationsKeepTheScreen() throws {
        let webView = chapter()
        let startScreen = 6
        show(screen: startScreen, in: webView)
        var position = try middle(in: webView)
        for size in Array(repeating: [Self.landscape, Self.portrait], count: 2).joined() {
            resize(webView, to: size, paged: false)
            let screen = try XCTUnwrap(evaluate("__screenOf('\(position)')", in: webView) as? Int)
            show(screen: screen, in: webView)
            position = try middle(in: webView)
        }
        let endScreen = try XCTUnwrap(evaluate("__screen()", in: webView) as? Int)
        XCTAssertLessThanOrEqual(abs(endScreen - startScreen), 1, "Back in portrait on screen \(endScreen), started on \(startScreen)")
    }
}
