//
//  BridgeScrollPositionTests.swift
//  FolioReaderKitTests
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import WebKit
import XCTest
@testable import FolioReaderKit

/// Scroll mode: recording a position with `getVisibleCFI` and restoring it from somewhere else, as
/// after reopening a book or rotating, the way `FolioReaderPage.handleAnchor` scrolls to it.
@MainActor
class BridgeScrollPositionTests: XCTestCase {
    /// Long enough to take several lines, or several columns in vertical writing.
    static func paragraphs(_ range: ClosedRange<Int>) -> String {
        range.map { index in
            "<p id=\"p\(index)\">第\(index)段：" + String(repeating: "敏捷的棕色狐狸跳过了懒狗，", count: 8) + "这一段到此为止。</p>"
        }.joined()
    }

    private func chapter(verticalWriting: Bool) -> WKWebView {
        readerChapter(Self.paragraphs(1...40), paged: false, verticalWriting: verticalWriting)
    }

    /// The partial CFI `FolioReaderPage.getWebViewScrollPosition` records in scroll mode; vertical
    /// writing passes `horizontal`, since its columns run sideways.
    private func record(_ webView: WKWebView, verticalWriting: Bool, file: StaticString = #filePath, line: UInt = #line) -> String {
        let json = evaluate("getVisibleCFI(\(verticalWriting))", in: webView, file: file, line: line) as? String ?? "{}"
        let cfi = FolioReaderPage.recordedPosition(fromVisibleCFIJSON: json).cfi
        XCTAssertFalse(cfi.isEmpty, "Recorded a position: \(json)", file: file, line: line)
        return cfi
    }

    /// The content offset `handleAnchor` scrolls to in scroll mode, before its retries.
    private func restore(_ cfi: String, in webView: WKWebView, verticalWriting: Bool) -> CGPoint {
        let offset = CGFloat(evaluate("getAnchorOffset(\"epubcfi(/6/2\(cfi))\", false)", in: webView) as? Double ?? .nan)
        if verticalWriting {
            return CGPoint(x: FolioReaderPage.verticalWritingScrollOffset(
                anchorOffset: offset, contentWidth: webView.scrollView.contentSize.width, viewWidth: webView.bounds.width
            ), y: 0)
        }
        return CGPoint(x: 0, y: min(offset, webView.scrollView.contentSize.height - webView.bounds.height))
    }

    /// The last character of paragraph `id`, in document coordinates (`scrollX` is 0 at the start
    /// of the chapter, its right end in vertical writing).
    private func lastCharacter(of id: String, in webView: WKWebView) -> CGRect {
        let values = evaluate("""
            (function () {
                const text = document.getElementById('\(id)').lastChild;
                const range = document.createRange();
                range.setStart(text, text.length - 1);
                range.setEnd(text, text.length);
                const r = range.getBoundingClientRect();
                return [r.left + scrollX, r.top + scrollY, r.width, r.height];
            })()
            """, in: webView) as? [Double] ?? [0, 0, 0, 0]
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    /// Vertical writing reads right to left, and the start of the chapter is the right end of the
    /// content. The restore used the distance from there as an offset from the left, so a position
    /// came back mirrored: the start of the chapter restored to its end.
    func testVerticalWritingRestoresWhereItWasRecorded() {
        let webView = chapter(verticalWriting: true)
        let width = webView.bounds.width
        let start = scrollOrigin(webView)
        for screens in [0.0, 0.4, 1.7, 3.2, 6.5] {
            let recorded = CGPoint(x: max(start.x - CGFloat(screens) * width, 0), y: 0)
            scrollNatively(webView, to: recorded)
            let cfi = record(webView, verticalWriting: true)

            scrollNatively(webView, to: screens == 0 ? .zero : start)
            let restored = restore(cfi, in: webView, verticalWriting: true)
            // Within a column: the restore puts the recorded column's right edge at the view's right edge.
            XCTAssertEqual(restored.x, recorded.x, accuracy: 48, "\(screens) screens in: \(cfi)")
        }
    }

    /// After a load or a layout change the body's `min-width` grows to whole screens (over a 0.6 s
    /// transition in the reader). In vertical writing the content grows at the left while the chapter
    /// starts at the right: WebKit keeps the text in place by moving the content offset, and the
    /// restore's retries, which re-applied the offset computed before the growth, moved the text two
    /// columns on the simulator. `FolioReaderPage.scrollVerticalWriting` retries with the distance
    /// from the start, which stays on the same text.
    func testVerticalWritingDistanceFromStartSurvivesTheContentGrowing() {
        let webView = chapter(verticalWriting: true)
        let width = webView.bounds.width
        let distance = 3.4 * width
        let before = webView.scrollView.contentSize.width
        let offset = FolioReaderPage.verticalWritingContentOffset(fromStart: distance, contentWidth: before, viewWidth: width)
        scrollNatively(webView, to: CGPoint(x: offset, y: 0))
        func markerX() -> Double { lastCharacter(of: "p12", in: webView).maxX - (evaluate("scrollX", in: webView) as? Double ?? 0) }
        let marker = markerX()

        // Two columns more, as the min-width rounding added on the simulator.
        evaluate("document.body.style.minWidth = '\(Int(before + 84))px'; true", in: webView)
        waitUntil("content grew") { webView.scrollView.contentSize.width >= before + 84 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let after = webView.scrollView.contentSize.width
        let growth = after - before
        XCTAssertEqual(markerX(), marker, accuracy: 1, "WebKit keeps the text in place")
        XCTAssertEqual(webView.scrollView.contentOffset.x, offset + growth, accuracy: 1, "by moving the content offset")

        scrollNatively(webView, to: CGPoint(x: offset, y: 0))
        XCTAssertEqual(markerX(), marker + growth, accuracy: 1, "Re-applying the old content offset moves the text")

        scrollNatively(webView, to: CGPoint(x: FolioReaderPage.verticalWritingContentOffset(fromStart: distance, contentWidth: after, viewWidth: width), y: 0))
        XCTAssertEqual(markerX(), marker, accuracy: 1, "The same distance from the start shows the same text")
    }

    /// A paragraph whose visible text is inside a child element (`<p>text<span>more text</span></p>`,
    /// as calibre writes for a change of language): only the paragraph's own text nodes were measured,
    /// none of them was on screen, and the position fell back to the whole paragraph, so restoring
    /// went to its top, ten lines back in 1984 ch. 1.
    func testTextInsideAChildElementIsThePosition() {
        let long = String(repeating: "敏捷的棕色狐狸跳过了懒狗，", count: 12)
        let body = Self.paragraphs(1...10) + "<p id=\"mixed\">开头的文字。\(long)<span id=\"inner\">\(long)\(long)结束。</span></p>" + Self.paragraphs(11...30)
        for verticalWriting in [false, true] {
            let webView = readerChapter(body, paged: false, verticalWriting: verticalWriting)
            // The view starts in the middle of the span's text, well after the paragraph's own text.
            let values = evaluate("""
                (function () {
                    const text = document.getElementById('inner').firstChild;
                    const range = document.createRange();
                    range.setStart(text, Math.floor(text.length / 2));
                    range.setEnd(text, Math.floor(text.length / 2) + 1);
                    const r = range.getBoundingClientRect();
                    return [r.right + scrollX, r.top + scrollY];
                })()
                """, in: webView) as? [Double] ?? [0, 0]
            let recorded = verticalWriting
                ? CGPoint(x: scrollOrigin(webView).x + values[0] - webView.bounds.width + 1, y: 0)
                : CGPoint(x: 0, y: values[1] - 1)
            scrollNatively(webView, to: recorded)
            let cfi = record(webView, verticalWriting: verticalWriting)
            XCTAssertTrue(cfi.contains("[inner]/1:"), "\(verticalWriting ? "Vertical" : "Horizontal"): a character in the span, not the paragraph: \(cfi)")

            scrollNatively(webView, to: verticalWriting ? scrollOrigin(webView) : .zero)
            let restored = restore(cfi, in: webView, verticalWriting: verticalWriting)
            if verticalWriting {
                XCTAssertEqual(restored.x, recorded.x, accuracy: 48, "Vertical: back within a column")
            } else {
                XCTAssertEqual(restored.y, recorded.y, accuracy: 48, "Horizontal: back within a line")
            }
        }
    }

    /// When the edge of the view cuts the last line (horizontal) or column (vertical) of a paragraph,
    /// its characters count as hidden and the position is recorded at the end of the paragraph's
    /// text. Looking that up measured one character past the end, which throws, so the restore fell
    /// back to the whole paragraph: its top, or in vertical writing its middle.
    func testEndOfAParagraphRestoresToItsLastLine() {
        for verticalWriting in [false, true] {
            let webView = chapter(verticalWriting: verticalWriting)
            let last = lastCharacter(of: "p12", in: webView)
            let recorded: CGPoint
            if verticalWriting {
                // The view's right edge 5 pt inside the last column.
                recorded = CGPoint(x: scrollOrigin(webView).x + last.maxX - webView.bounds.width - 5, y: 0)
            } else {
                // The view's top 5 pt inside the last line.
                recorded = CGPoint(x: 0, y: last.minY + 5)
            }
            scrollNatively(webView, to: recorded)
            let cfi = record(webView, verticalWriting: verticalWriting)
            let paragraphLength = evaluate("document.getElementById('p12').lastChild.length", in: webView) as? Int ?? -1
            XCTAssertTrue(cfi.hasSuffix("[p12]/1:\(paragraphLength)"), "Recorded the end of p12: \(cfi)")

            scrollNatively(webView, to: verticalWriting ? scrollOrigin(webView) : .zero)
            let restored = restore(cfi, in: webView, verticalWriting: verticalWriting)
            if verticalWriting {
                XCTAssertEqual(restored.x, recorded.x, accuracy: 6, "Vertical: back at the last column of p12")
            } else {
                XCTAssertEqual(restored.y, recorded.y, accuracy: 6, "Horizontal: back at the last line of p12")
            }
        }
    }

    /// Positions are recorded with `<highlight>` blacklisted, which counts the text around a highlight
    /// as one node without the highlighted text. `getAnchorOffset` resolved them without it, so a
    /// position after a highlight landed at the end of the text before it, lines earlier here.
    func testPositionAfterAHighlightRestoresToItsLine() {
        let before = String(repeating: "敏捷的棕色狐狸跳过了懒狗，", count: 4)
        let highlighted = String(repeating: "这一段被标记了。", count: 30)
        let body = Self.paragraphs(1...5) + "<p id=\"hl\">\(before)<highlight id=\"h1\">\(highlighted)</highlight>\(before)</p>" + Self.paragraphs(6...20)
        let webView = readerChapter(body, paged: false)
        let values = evaluate("""
            (function () {
                const text = document.getElementById('hl').lastChild;
                const cfi = window.EPUBcfi.generateCharacterOffsetCFIComponent(text, 5, [], ["highlight"], []);
                const range = document.createRange();
                range.setStart(text, 5);
                range.setEnd(text, 6);
                return [cfi, range.getBoundingClientRect().top + scrollY];
            })()
            """, in: webView) as? [Any] ?? []
        let cfi = values.first as? String ?? ""
        let top = values.last as? Double ?? .nan
        XCTAssertFalse(cfi.isEmpty)
        let restored = evaluate("getAnchorOffset(\"epubcfi(/6/2\(cfi))\", false)", in: webView) as? Double ?? .nan
        XCTAssertEqual(restored, top, accuracy: 1, "The character after the highlight: \(cfi)")
    }
}
