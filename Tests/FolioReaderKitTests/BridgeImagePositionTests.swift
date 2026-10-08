//
//  BridgeImagePositionTests.swift
//  FolioReaderKitTests
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import WebKit
import XCTest
@testable import FolioReaderKit

/// Positions on images: recording one where the view holds only an image (an `<img>`, or the
/// SVG-wrapped `<image>` calibre writes for covers and plates) or starts with one, and restoring it
/// from somewhere else, as after reopening a book or rotating.
@MainActor
class BridgeImagePositionTests: XCTestCase {
    enum Layout { case paged, scroll, pagedVertical, scrollVertical }

    /// Escaped, so the markup is also well-formed XHTML.
    static let dataImage = "data:image/svg+xml;utf8,&lt;svg xmlns='http://www.w3.org/2000/svg' width='600' height='800'&gt;&lt;rect width='100%' height='100%' fill='gray'/&gt;&lt;/svg&gt;"

    static func paragraphs(_ range: ClosedRange<Int>) -> String {
        range.map { "<p id=\"p\($0)\">Paragraph \($0): the quick brown fox jumps over the lazy dog, 敏捷的棕色狐狸跳过了懒狗，第\($0)段。</p>" }.joined()
    }
    /// A standalone illustration on a page of its own.
    static func imagePage(_ id: String) -> String {
        "<div style=\"break-before: page; break-after: page; text-align: center\"><img id=\"\(id)\" class=\"folioImg\" src=\"\(dataImage)\" width=\"600\" height=\"800\"/></div>"
    }
    /// calibre's cover and plate markup: an SVG wrapping an `<image>`.
    static func svgPage(_ id: String) -> String {
        "<div style=\"break-before: page; break-after: page\"><svg id=\"\(id)\" xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" version=\"1.1\" width=\"100%\" height=\"100%\" viewBox=\"0 0 600 800\" preserveAspectRatio=\"xMidYMid meet\"><image width=\"600\" height=\"800\" xlink:href=\"\(dataImage)\"/></svg></div>"
    }

    private func chapter(_ body: String, _ layout: Layout, xhtml: Bool) -> WKWebView {
        readerChapter(body, paged: layout == .paged || layout == .pagedVertical, verticalWriting: layout == .pagedVertical || layout == .scrollVertical, xhtml: xhtml)
    }

    /// The partial CFI `FolioReaderPage.getWebViewScrollPosition` records, parsed as it parses it.
    private func recordedCFI(_ webView: WKWebView, _ layout: Layout, file: StaticString = #filePath, line: UInt = #line) -> String {
        let script = layout == .paged || layout == .pagedVertical ? "getVisibleMiddleCFI(true)" : "getVisibleCFI(\(layout == .scrollVertical))"
        let json = evaluate(script, in: webView, file: file, line: line) as? String ?? "{}"
        let cfi = FolioReaderPage.recordedPosition(fromVisibleCFIJSON: json).cfi
        XCTAssertFalse(cfi.isEmpty, "Recorded a position: \(json)", file: file, line: line)
        let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]) ?? [:]
        XCTAssertNotNil(object["snippet"] as? String, "The JSON keeps a snippet: \(json)", file: file, line: line)
        return cfi
    }

    /// The content offset `FolioReaderPage.handleAnchor` scrolls to for `target`.
    private func restorePoint(_ target: String, _ layout: Layout, in webView: WKWebView) -> CGPoint {
        let paged = layout == .paged || layout == .pagedVertical
        let offset = CGFloat(evaluate("getAnchorOffset(\"\(target)\", \(paged))", in: webView) as? Double ?? .nan)
        let width = webView.bounds.width
        switch layout {
        case .paged:
            return CGPoint(x: (offset / width).rounded(.down) * width, y: 0)
        case .scroll:
            return CGPoint(x: 0, y: min(offset, webView.scrollView.contentSize.height - webView.bounds.height))
        case .pagedVertical:
            return CGPoint(x: webView.scrollView.contentSize.width - ((offset / width).rounded(.up) + 1) * width, y: 0)
        case .scrollVertical:
            return CGPoint(x: FolioReaderPage.verticalWritingScrollOffset(anchorOffset: offset, contentWidth: webView.scrollView.contentSize.width, viewWidth: width), y: 0)
        }
    }

    private func rect(of id: String, in webView: WKWebView) -> CGRect {
        let values = evaluate("(function () { const r = document.getElementById('\(id)').getBoundingClientRect(); return [r.left, r.top, r.width, r.height]; })()", in: webView) as? [Double] ?? [0, 0, 0, 0]
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    private func isCentered(_ id: String, in webView: WKWebView) -> Bool {
        let r = rect(of: id, in: webView)
        return webView.bounds.contains(CGPoint(x: r.midX, y: r.minY + min(r.height, webView.bounds.height) / 2))
    }

    /// Scrolls through the pages until `id` is on screen; returns that content offset.
    private func showPage(holding id: String, in webView: WKWebView, _ layout: Layout) -> CGPoint? {
        let width = webView.bounds.width
        let pages = Int((webView.scrollView.contentSize.width / width).rounded())
        for page in 0..<pages {
            let x = layout == .pagedVertical ? webView.scrollView.contentSize.width - CGFloat(page + 1) * width : CGFloat(page) * width
            scrollNatively(webView, to: CGPoint(x: x, y: 0))
            if isCentered(id, in: webView) { return CGPoint(x: x, y: 0) }
        }
        XCTFail("\(id) is on no page")
        return nil
    }

    // MARK: - Paged

    func testImagePagesRestoreInPagedMode() throws {
        for xhtml in [false, true] {
            for layout in [Layout.paged, .pagedVertical] {
                let webView = chapter(Self.paragraphs(1...20) + Self.imagePage("img") + Self.paragraphs(21...60) + Self.svgPage("svg") + Self.paragraphs(61...80), layout, xhtml: xhtml)
                for id in ["img", "svg"] {
                    let page = try XCTUnwrap(showPage(holding: id, in: webView, layout))
                    let cfi = recordedCFI(webView, layout)
                    // Restore from the first page, as when the book is opened again.
                    scrollNatively(webView, to: layout == .pagedVertical ? CGPoint(x: webView.scrollView.contentSize.width - webView.bounds.width, y: 0) : .zero)
                    XCTAssertEqual(restorePoint("epubcfi(/6/2\(cfi))", layout, in: webView), page, "\(xhtml ? "XHTML" : "HTML") \(layout) \(id): \(cfi)")
                }
            }
        }
    }

    // MARK: - Scroll

    /// An image whose top has scrolled out of view restores to its top: back by the hidden part, the
    /// same position every time.
    func testImageAtTheTopRestoresToItsTopInScrollMode() {
        for xhtml in [false, true] {
            let webView = chapter(Self.paragraphs(1...20) + Self.imagePage("img") + Self.paragraphs(21...40), .scroll, xhtml: xhtml)
            let imageTop = rect(of: "img", in: webView).minY
            scrollNatively(webView, to: CGPoint(x: 0, y: imageTop + 200))
            let cfi = recordedCFI(webView, .scroll)

            scrollNatively(webView, to: .zero)
            let restored = restorePoint("epubcfi(/6/2\(cfi))", .scroll, in: webView)
            XCTAssertEqual(restored.y, imageTop, accuracy: 2, "\(xhtml ? "XHTML" : "HTML") \(cfi)")

            scrollNatively(webView, to: restored)
            XCTAssertEqual(recordedCFI(webView, .scroll), cfi, "Recording again at the restored position gives the same position")
        }
    }

    /// The SVG at the top of the view is the position, not the paragraph after it.
    func testSVGAtTheTopIsTheScrollPosition() {
        for xhtml in [false, true] {
            let webView = chapter(Self.paragraphs(1...20) + Self.svgPage("svg") + Self.paragraphs(21...40), .scroll, xhtml: xhtml)
            let svgTop = rect(of: "svg", in: webView).minY
            scrollNatively(webView, to: CGPoint(x: 0, y: svgTop + 100))
            let cfi = recordedCFI(webView, .scroll)

            scrollNatively(webView, to: .zero)
            XCTAssertEqual(restorePoint("epubcfi(/6/2\(cfi))", .scroll, in: webView).y, svgTop, accuracy: 2, "\(xhtml ? "XHTML" : "HTML") \(cfi)")
        }
    }

    // MARK: - Chapters that are only an image

    func testImageOnlyChaptersRecordAPosition() {
        for xhtml in [false, true] {
            for layout in [Layout.scroll, .paged] {
                for body in [Self.imagePage("only"), Self.svgPage("only")] {
                    let webView = chapter(body, layout, xhtml: xhtml)
                    let cfi = recordedCFI(webView, layout)
                    XCTAssertEqual(restorePoint("epubcfi(/6/2\(cfi))", layout, in: webView), .zero, "\(xhtml ? "XHTML" : "HTML") \(layout) \(cfi)")
                }
            }
        }
    }

    // MARK: - Element anchors

    /// Table-of-contents links restore to an element by id, through the same element lookup.
    func testElementAnchorsRestore() throws {
        for layout in [Layout.paged, .pagedVertical, .scroll, .scrollVertical] {
            let webView = chapter(Self.paragraphs(1...80), layout, xhtml: false)
            for id in ["p25", "p70"] {
                scrollNatively(webView, to: scrollOrigin(webView))
                scrollNatively(webView, to: restorePoint(id, layout, in: webView))
                let r = rect(of: id, in: webView)
                XCTAssertTrue(webView.bounds.intersects(r), "\(layout) \(id) is on screen at \(r)")
            }
        }
    }
}

/// `FolioReaderPage.recordedPosition(fromVisibleCFIJSON:)`, the reader's reading of that JSON.
class VisibleCFIJSONTests: XCTestCase {
    func testPrefersTheCharacterOffset() {
        let json = #"{"cfi":"/4/2","snippet":"a","offsetComponent":"/4/2/1:5","offsetSnippet":"b","message":"m"}"#
        XCTAssertEqual(FolioReaderPage.recordedPosition(fromVisibleCFIJSON: json).cfi, "/4/2/1:5")
    }

    func testKeepsAnElementPositionWithoutASnippet() {
        let json = #"{"cfi":"/4/2/2[svg]","offsetComponent":"","offsetSnippet":"","message":"first"}"#
        let position = FolioReaderPage.recordedPosition(fromVisibleCFIJSON: json)
        XCTAssertEqual(position.cfi, "/4/2/2[svg]")
        XCTAssertEqual(position.snippet, "")
    }

    func testNothingFromUnreadableJSON() {
        XCTAssertEqual(FolioReaderPage.recordedPosition(fromVisibleCFIJSON: nil).message, "json fail")
        XCTAssertEqual(FolioReaderPage.recordedPosition(fromVisibleCFIJSON: "{").cfi, "")
    }
}
