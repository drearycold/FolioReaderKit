//
//  BridgePositionTests.swift
//  FolioReaderKitTests
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import WebKit
import XCTest
@testable import FolioReaderKit

/// Runs `Bridge.js`'s position recording (`getVisibleMiddleCFI`) and restore lookup
/// (`getAnchorOffset`) with the real CFI library on a paginated, reader-styled chapter.
@MainActor
class BridgePositionTests: XCTestCase {
    static let portrait = CGSize(width: 402, height: 662)
    static let landscape = CGSize(width: 874, height: 270)

    /// The page `handleAnchor` shows for a recorded partial CFI in horizontal paged mode.
    static let helpers = """
        function __pageOf(offsetComponent) {
            return Math.floor(getAnchorOffset("epubcfi(/6/2" + offsetComponent + ")", true) / window.innerWidth);
        }
        function __page() { return Math.round(Math.abs(window.scrollX) / window.innerWidth); }
        true
        """

    private func pagedChapter(verticalWriting: Bool = false) -> WKWebView {
        let paragraphs = (1...160).map { index in
            "<p>Paragraph \(index): the quick brown fox jumps over the lazy dog, 敏捷的棕色狐狸跳过了懒狗，第\(index)段。</p>"
        }.joined()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(FolioReaderScript.readiumCFIJS)
        configuration.userContentController.addUserScript(FolioReaderScript.bridgeJS)
        configuration.userContentController.addUserScript(
            FolioReaderCSSInjector.userScript(id: FolioReaderCSSInjector.StyleID.bundle, css: FolioReaderCSSBuilder.baseStyleSheet()
                + "\nhtml, body { -webkit-transition: none !important; transition: none !important; }")
        )
        configuration.userContentController.add(MockScriptMessageHandler(), name: "FolioReaderPage")
        let webView = loadedWebView(html: """
            <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
            <body><h1>Chapter</h1>\(paragraphs)</body></html>
            """, configuration: configuration)

        let state = FolioReaderStyleState(styleOverride: .PNode, font: "", fontSize: "20px", fontWeight: "400", letterSpacing: 0, lineHeight: 2, textIndent: 2, marginTop: 5, marginBottom: 5, marginLeft: 5, marginRight: 5, isVerticalWritingMode: verticalWriting)
        let mode = verticalWriting ? "vertical-rl" : "horizontal-tb"
        evaluate("writingMode = '\(mode)'; document.documentElement.style.writingMode = writingMode; "
            + FolioReaderCSSInjector.runtimeStyleSource(themeMode: 0, styleState: state, runtimeSheets: [], includeDebugDump: false) + "; true", in: webView)
        let overflow = FolioReaderCSSBuilder.overflowCSS(overflow: "-webkit-paged-x", verticalWritingMode: verticalWriting)
        evaluate("var s = document.createElement('style'); s.textContent = \(String(reflecting: overflow)); document.head.appendChild(s); true", in: webView)
        evaluate(Self.helpers, in: webView)
        // Resize after styling: WebKit doesn't always paginate when -webkit-paged-x arrives with no
        // viewport change after it.
        resize(webView, to: Self.portrait)
        XCTAssertGreaterThan(evaluate("document.body.getClientRects().length", in: webView) as? Int ?? 0, 10, "The chapter is paginated")
        return webView
    }

    /// Pagination and the scroll range settle after the styles or the viewport change, as in the reader.
    private func waitForLayout(_ webView: WKWebView) {
        let settled = expectation(description: "layout settled")
        WebViewLayoutWaiter.wait(for: webView, timeout: 3, paged: true) { _ in settled.fulfill() }
        wait(for: [settled], timeout: 5)
    }

    private func resize(_ webView: WKWebView, to size: CGSize) {
        webView.frame = CGRect(origin: .zero, size: size)
        waitUntil("viewport \(size)") {
            (evaluate("[window.innerWidth, window.innerHeight]", in: webView) as? [Double]) == [Double(size.width), Double(size.height)]
        }
        waitForLayout(webView)
    }

    /// Shows `page` the way the reader does, by scrolling the native scroll view, and waits until the
    /// page sees the new offset. A JS `scrollTo` updates `scrollX` before the character boxes follow.
    private func show(_ page: Int, in webView: WKWebView, file: StaticString = #filePath, line: UInt = #line) {
        let x = CGFloat(page) * webView.bounds.width
        waitUntil("page \(page)", file: file, line: line) {
            // Retried, because the content size can lag a relayout and clamp the offset.
            webView.scrollView.setContentOffset(CGPoint(x: x, y: 0), animated: false)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            return evaluate("window.scrollX", in: webView) as? Double == Double(x)
        }
    }

    private func record(_ function: String, in webView: WKWebView) throws -> String {
        let json = try XCTUnwrap(evaluate("\(function)(true)", in: webView) as? String)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let offsetComponent = try XCTUnwrap(object["offsetComponent"] as? String)
        XCTAssertFalse(offsetComponent.isEmpty, json)
        if function == "getVisibleMiddleCFI" {
            XCTAssertTrue((object["message"] as? String ?? "").hasPrefix("middle "), "Found the middle, no fallback: \(json)")
        }
        return offsetComponent
    }

    private func waitUntil(_ description: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for \(description)", file: file, line: line)
                return
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
    }

    func testMiddleIsOnTheCurrentPageAfterItsStart() throws {
        let webView = pagedChapter()
        for page in [1, 4, 9] {
            show(page, in: webView)
            let middle = try record("getVisibleMiddleCFI", in: webView)
            let start = try record("getVisibleCFI", in: webView)
            XCTAssertEqual(evaluate("__pageOf('\(middle)')", in: webView) as? Int, page, "Restoring the middle shows page \(page)")
            XCTAssertNotEqual(middle, start, "Page \(page) records its middle, not its first text")
            // The snippet titles bookmarks, so it comes from the start of the page, not the middle.
            let snippet = evaluate("JSON.parse(getVisibleMiddleCFI(true)).snippet", in: webView) as? String ?? ""
            let textAtMiddle = evaluate("""
                (function () {
                    const info = window.EPUBcfi.getTextTerminusInfoWithPartialCFI(encodeURI("epubcfi(\(middle))"), document, [], [], []);
                    return info.textNode.textContent.substr(info.textOffset, 64);
                })()
                """, in: webView) as? String ?? ""
            XCTAssertFalse(snippet.isEmpty)
            XCTAssertNotEqual(snippet, textAtMiddle, "Page \(page)")
        }
    }

    /// Rotating back and forth must not walk the reader away from the page: the first visible
    /// character drifted back about a page per round trip.
    func testRepeatedRelayoutsKeepThePage() throws {
        let webView = pagedChapter()
        let startPage = 8
        show(startPage, in: webView)
        var position = try record("getVisibleMiddleCFI", in: webView)
        for size in Array(repeating: [Self.landscape, Self.portrait], count: 4).joined() {
            resize(webView, to: size)
            let page = try XCTUnwrap(evaluate("__pageOf('\(position)')", in: webView) as? Int)
            show(page, in: webView)
            position = try record("getVisibleMiddleCFI", in: webView)
        }
        let endPage = try XCTUnwrap(evaluate("__page()", in: webView) as? Int)
        XCTAssertLessThanOrEqual(abs(endPage - startPage), 1, "Back in portrait on page \(endPage), started on \(startPage)")
    }

    /// Vertical writing pages run right to left; the reader shows page p at
    /// `contentSize.width - (p + 1) * width` (`handleAnchor`).
    func testVerticalWritingMiddleIsOnTheCurrentPage() throws {
        let webView = pagedChapter(verticalWriting: true)
        let width = webView.bounds.width
        var middles = Set<String>()
        for page in [0, 2, 5] {
            let x = webView.scrollView.contentSize.width - CGFloat(page + 1) * width
            webView.scrollView.setContentOffset(CGPoint(x: x, y: 0), animated: false)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            let middle = try record("getVisibleMiddleCFI", in: webView)
            middles.insert(middle)
            let centerX = evaluate("""
                (function () {
                    const info = window.EPUBcfi.getTextTerminusInfoWithPartialCFI(encodeURI("epubcfi(\(middle))"), document, [], [], []);
                    const range = document.createRange();
                    range.setStart(info.textNode, info.textOffset);
                    range.setEnd(info.textNode, info.textOffset + 1);
                    const rect = range.getBoundingClientRect();
                    return rect.left + rect.width / 2;
                })()
                """, in: webView) as? Double ?? -1
            XCTAssertTrue((0..<Double(width)).contains(centerX), "Page \(page): middle at x=\(centerX)")
        }
        XCTAssertEqual(middles.count, 3, "Each page records its own middle")
    }
}
