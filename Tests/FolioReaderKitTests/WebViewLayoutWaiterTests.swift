//
//  WebViewLayoutWaiterTests.swift
//  FolioReaderKitTests
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import WebKit
import XCTest
@testable import FolioReaderKit

@MainActor
class WebViewLayoutWaiterTests: XCTestCase {

    func testLayoutMatchesScalesDocumentSizeAndAllowsTolerance() {
        let document = CGSize(width: 320, height: 1000)
        XCTAssertTrue(WebViewLayoutWaiter.layoutMatches(contentSize: CGSize(width: 320, height: 1001), documentSize: document, zoomScale: 1))
        XCTAssertTrue(WebViewLayoutWaiter.layoutMatches(contentSize: CGSize(width: 640, height: 2000), documentSize: document, zoomScale: 2))
        XCTAssertFalse(WebViewLayoutWaiter.layoutMatches(contentSize: CGSize(width: 320, height: 480), documentSize: document, zoomScale: 1))
    }

    func testMeasurementRequiresLoadedFonts() {
        XCTAssertEqual(
            WebViewLayoutWaiter.measurement(from: "[320,1000,320,480,true]"),
            .init(document: CGSize(width: 320, height: 1000), viewport: CGSize(width: 320, height: 480))
        )
        XCTAssertNil(WebViewLayoutWaiter.measurement(from: "[320,1000,320,480,false]"), "Wait while web fonts load")
        XCTAssertNil(WebViewLayoutWaiter.measurement(from: nil))
    }

    /// Values recorded from the reader in paged mode: JS reports 402×4201 (unpaginated) while
    /// the scroll view holds 7 pages of 402×662.
    func testPagedModeAcceptsPaginatedContentSize() {
        let measured = WebViewLayoutWaiter.Measurement(document: CGSize(width: 402, height: 4201), viewport: CGSize(width: 402, height: 662))
        let paged = WebViewLayoutWaiter.expectedContentSizes(for: measured, paged: true)
        XCTAssertTrue(paged.contains(CGSize(width: 2814, height: 662)))
        XCTAssertEqual(WebViewLayoutWaiter.expectedContentSizes(for: measured, paged: false), [CGSize(width: 402, height: 4201)])

        let exactMultiple = WebViewLayoutWaiter.Measurement(document: CGSize(width: 402, height: 4634), viewport: CGSize(width: 402, height: 662))
        XCTAssertTrue(WebViewLayoutWaiter.expectedContentSizes(for: exactMultiple, paged: true).contains(CGSize(width: 2814, height: 662)),
                      "An exact multiple of the page height must not add a page")
    }

    /// Before pagination takes effect the scroll view still holds the unpaginated document size, the
    /// same size JS reports, so that size must not count as settled in paged mode.
    func testPagedModeRejectsTheUnpaginatedContentSize() {
        let measured = WebViewLayoutWaiter.Measurement(document: CGSize(width: 402, height: 4201), viewport: CGSize(width: 402, height: 662))
        let expected = WebViewLayoutWaiter.expectedContentSizes(for: measured, paged: true)
        XCTAssertEqual(expected, [CGSize(width: 2814, height: 662)])
        XCTAssertFalse(expected.contains { WebViewLayoutWaiter.layoutMatches(contentSize: CGSize(width: 402, height: 4201), documentSize: $0, zoomScale: 1) })
    }

    /// Some documents report the paginated size to JS already (one page high, all pages wide).
    func testPagedModeKeepsADocumentSizeThatIsAlreadyPaginated() {
        let measured = WebViewLayoutWaiter.Measurement(document: CGSize(width: 11200, height: 480), viewport: CGSize(width: 320, height: 480))
        XCTAssertTrue(WebViewLayoutWaiter.expectedContentSizes(for: measured, paged: true).contains(CGSize(width: 11200, height: 480)))
    }

    /// After a script grows the document, the waiter must not finish until the native content size
    /// has caught up, and it must finish well before the timeout.
    func testWaitSettlesOnceContentSizeCatchesUpWithLayout() {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let loader = PageLoadWaiter(expectation(description: "page loaded"))
        webView.navigationDelegate = loader
        webView.loadHTMLString("<html><head><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"></head><body style=\"margin:0\"><p>x</p></body></html>", baseURL: nil)
        wait(for: [loader.loaded], timeout: 10)

        let grown = expectation(description: "document grown")
        webView.evaluateJavaScript("document.body.style.height = '5000px'; true") { _, _ in grown.fulfill() }
        wait(for: [grown], timeout: 5)

        let settled = expectation(description: "layout settled")
        let start = Date()
        var didSettle = false
        WebViewLayoutWaiter.wait(for: webView, timeout: 3) { result in
            didSettle = result
            settled.fulfill()
        }
        wait(for: [settled], timeout: 5)

        XCTAssertTrue(didSettle, "Expected the layout to settle before the timeout")
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0)
        XCTAssertEqual(webView.scrollView.contentSize.height, 5000 * webView.scrollView.zoomScale, accuracy: 2)
    }

    /// Switching a long chapter, styled like the reader's, from scrolling to `-webkit-paged-x`: the
    /// wait must end on the paginated layout, before the timeout.
    func testPagedWaitSettlesOnThePaginatedLayout() {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(
            FolioReaderCSSInjector.userScript(id: FolioReaderCSSInjector.StyleID.bundle, css: FolioReaderCSSBuilder.baseStyleSheet())
        )
        let paragraph = "<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.</p>"
        let webView = loadedWebView(html: """
            <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
            <body>\(String(repeating: paragraph, count: 120))</body></html>
            """, configuration: configuration)
        XCTAssertGreaterThan(evaluate("document.documentElement.scrollHeight", in: webView) as? Double ?? 0, 2 * Double(webView.bounds.height), "Starts as a long scrolling document")

        let css = FolioReaderCSSBuilder.overflowCSS(overflow: "-webkit-paged-x", verticalWritingMode: false)
        evaluate("var s = document.createElement('style'); s.textContent = \(String(reflecting: css)); document.head.appendChild(s); true", in: webView)

        let settled = expectation(description: "layout settled")
        var didSettle = false
        var contentSizeAtSettle = CGSize.zero
        WebViewLayoutWaiter.wait(for: webView, timeout: 3, paged: true) { result in
            didSettle = result
            contentSizeAtSettle = webView.scrollView.contentSize
            settled.fulfill()
        }
        wait(for: [settled], timeout: 5)

        XCTAssertTrue(didSettle, "Expected the paged layout to settle before the timeout")
        XCTAssertEqual(contentSizeAtSettle.height, webView.bounds.height * webView.scrollView.zoomScale, accuracy: 2, "Settled on a paginated content size")
        XCTAssertGreaterThan(contentSizeAtSettle.width, webView.bounds.width)
    }

    /// The scheduled polls must not keep the web view alive until the timeout.
    func testWaitEndsWhenTheWebViewGoesAway() {
        let ended = expectation(description: "wait ended")
        var didSettle: Bool?
        weak var released: WKWebView?
        let start = Date()
        // The pool releases the test's own autoreleased references before the wait goes on.
        autoreleasepool {
            let webView = loadedWebView(html: "<p>x</p>")
            released = webView
            WebViewLayoutWaiter.wait(for: webView, timeout: 10) { result in
                didSettle = result
                ended.fulfill()
            }
        }

        wait(for: [ended], timeout: 5)
        XCTAssertNil(released)
        XCTAssertEqual(didSettle, false)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
}

@MainActor
private final class PageLoadWaiter: NSObject, WKNavigationDelegate {
    let loaded: XCTestExpectation

    init(_ loaded: XCTestExpectation) {
        self.loaded = loaded
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded.fulfill()
    }
}
