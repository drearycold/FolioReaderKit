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
    /// An 11" iPad: one page in portrait, a two-page spread in landscape.
    static let tabletPortrait = CGSize(width: 834, height: 1150)
    static let tabletLandscape = CGSize(width: 1194, height: 790)
    static let spreadMinimumWidth: CGFloat = 1000

    /// The page `handleAnchor` shows for a recorded partial CFI in horizontal paged mode.
    static let helpers = """
        function __pageOf(offsetComponent) {
            return Math.floor(getAnchorOffset("epubcfi(/6/2" + offsetComponent + ")", true) / window.innerWidth);
        }
        function __page() { return Math.round(Math.abs(window.scrollX) / window.innerWidth); }
        true
        """

    private func pagedChapter(verticalWriting: Bool = false, size: CGSize = BridgePositionTests.portrait, spreadMinimumWidth: CGFloat? = nil) -> WKWebView {
        let paragraphs = (1...160).map { index in
            "<p>Paragraph \(index): the quick brown fox jumps over the lazy dog, 敏捷的棕色狐狸跳过了懒狗，第\(index)段。</p>"
        }.joined()
        let webView = readerChapter("<h1>Chapter</h1>" + paragraphs, paged: true, verticalWriting: verticalWriting, size: size, spreadMinimumWidth: spreadMinimumWidth)
        XCTAssertGreaterThan(evaluate("document.body.getClientRects().length", in: webView) as? Int ?? 0, 10, "The chapter is paginated")
        evaluate(Self.helpers, in: webView)
        return webView
    }

    private func show(_ page: Int, in webView: WKWebView, file: StaticString = #filePath, line: UInt = #line) {
        scrollNatively(webView, to: CGPoint(x: CGFloat(page) * webView.bounds.width, y: 0), file: file, line: line)
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
            resize(webView, to: size, paged: true)
            let page = try XCTUnwrap(evaluate("__pageOf('\(position)')", in: webView) as? Int)
            show(page, in: webView)
            position = try record("getVisibleMiddleCFI", in: webView)
        }
        let endPage = try XCTUnwrap(evaluate("__page()", in: webView) as? Int)
        XCTAssertLessThanOrEqual(abs(endPage - startPage), 1, "Back in portrait on page \(endPage), started on \(startPage)")
    }

    /// In a two-page spread the middle of the visible text is at the foot of the left column or the
    /// head of the right one; restoring it shows the same spread.
    func testSpreadMiddleIsOnTheCurrentSpread() throws {
        let webView = pagedChapter(size: Self.tabletLandscape, spreadMinimumWidth: Self.spreadMinimumWidth)
        XCTAssertEqual(evaluate("folioColumnsPerScreen()", in: webView) as? Int, 2)
        for spread in [1, 3, 6] {
            show(spread, in: webView)
            let middle = try record("getVisibleMiddleCFI", in: webView)
            XCTAssertEqual(evaluate("__pageOf('\(middle)')", in: webView) as? Int, spread, "Restoring the middle shows spread \(spread)")
        }
    }

    /// Rotating an iPad switches between one page in portrait and a spread in landscape; going back
    /// and forth must keep the reader on the page.
    func testRepeatedRotationsBetweenPageAndSpreadKeepThePage() throws {
        let webView = pagedChapter(size: Self.tabletPortrait, spreadMinimumWidth: Self.spreadMinimumWidth)
        let startPage = 8
        show(startPage, in: webView)
        var position = try record("getVisibleMiddleCFI", in: webView)
        for size in Array(repeating: [Self.tabletLandscape, Self.tabletPortrait], count: 4).joined() {
            resize(webView, to: size, paged: true)
            XCTAssertEqual(evaluate("folioColumnsPerScreen()", in: webView) as? Int, size == Self.tabletLandscape ? 2 : 1)
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
            scrollNatively(webView, to: CGPoint(x: webView.scrollView.contentSize.width - CGFloat(page + 1) * width, y: 0))
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

    /// The snippet is cut at 64 UTF-16 code units. Cutting an emoji in half left a lone surrogate,
    /// which JSON.stringify escapes alone and JSONSerialization rejects: the page recorded nothing.
    func testSnippetNeverEndsInHalfAnEmoji() throws {
        let paragraphs = (1...40).map { "<p>Paragraph \($0): the quick brown fox jumps over the lazy dog.</p>" }.joined()
        let webView = readerChapter("<p>" + String(repeating: "a", count: 63) + "😀 and more text.</p>" + paragraphs, paged: true, size: Self.portrait)
        let json = try XCTUnwrap(evaluate("getVisibleMiddleCFI(true)", in: webView) as? String)
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(json.utf8)), json)
        XCTAssertFalse(FolioReaderPage.recordedPosition(fromVisibleCFIJSON: json).cfi.isEmpty, json)
    }
}
