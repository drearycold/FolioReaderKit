//
//  VerticalPageWidthTests.swift
//  FolioReaderKitTests
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import WebKit
import XCTest
@testable import FolioReaderKit

/// WebKit paginates a paged page as wide as the root's client width, which FolioReaderPage takes to
/// be the web view's width. In vertical writing the reader's viewport is set by the view's height
/// (`height=device-height`), and the width follows it, rounded to a whole pixel: a 780 × 751.5 view
/// paginated 781 px pages, and 1112 × 751.5 1113 px ones (iOS 17.5 and 26.5). A taller view (780 ×
/// 1029.5) rounded back to its width.
@MainActor
final class VerticalPageWidthTests: XCTestCase {

    /// The viewport `updateOverflowStyle` sets for vertical writing.
    private let verticalViewport = "height=device-height, initial-scale=1.0, maximum-scale=1.0, user-scalable=0, viewport-fit=cover"

    /// YAEBR's reader on an iPad Pro 10.5" in landscape, under its 54.5 pt toolbar.
    func testVerticalPagesAreAsWideAsTheWebView() {
        let input = FolioReaderPageFrameInput(
            bounds: CGRect(x: 0, y: 0, width: 1112, height: 751.5),
            writingMode: "vertical-rl",
            scrollDirection: .horizontalWithPagedContent,
            currentMarginTop: 0,
            currentMarginBottom: 0,
            currentMarginLeft: 30,
            currentMarginRight: 30,
            pageWidth: 1112,
            pageHeight: 751.5,
            statusbarHeight: 0,
            pageIndicatorHeight: 0,
            hidePageIndicator: true,
            reserveSafeAreaInsidePageFrame: false,
            reservePageIndicatorInsidePageFrame: false
        )
        let frame = FolioReaderPageFrameCalculator.webViewFrame(input: input)

        let paragraphs = String(repeating: "<p>\(String(repeating: "崔浩與寇謙之", count: 40))</p>", count: 40)
        let webView = readerChapter(paragraphs, paged: true, verticalWriting: true, size: CGSize(width: 300, height: 300))
        evaluate("document.querySelector('meta[name=viewport]').setAttribute('content', '\(verticalViewport)'); true", in: webView)
        webView.frame = frame
        waitUntil("viewport \(frame.size)") {
            (evaluate("window.innerWidth", in: webView) as? Double) == Double(frame.width)
        }
        let settled = expectation(description: "layout settled")
        WebViewLayoutWaiter.wait(for: webView, timeout: 3, paged: true) { _ in settled.fulfill() }
        wait(for: [settled], timeout: 5)

        XCTAssertEqual(evaluate("document.documentElement.clientWidth", in: webView) as? Double, Double(frame.width))
        let contentWidth = webView.scrollView.contentSize.width
        XCTAssertGreaterThan(contentWidth, frame.width, "The chapter takes several pages")
        XCTAssertEqual(contentWidth.truncatingRemainder(dividingBy: frame.width), 0, "The content is whole screens")
    }
}
