//
//  WebViewTestSupport.swift
//  FolioReaderKitTests
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import WebKit
import XCTest
@testable import FolioReaderKit

/// How long a page load or a script may take. Locally both take milliseconds; on a CI runner the
/// first WebKit tests ran while the simulator was still busy after booting, and loads took over 10 s.
let webKitTimeout: TimeInterval = 30

@MainActor
extension XCTestCase {
    /// A chapter laid out as the reader lays out pages: `Bridge.js` and the CFI library, the bundled
    /// CSS, the runtime style, and the overflow style for paged or scroll mode.
    /// `xhtml` loads it as `application/xhtml+xml`, as the reader serves `.xhtml` chapters, where
    /// element names are lowercase; `body` must then be well-formed XML.
    func readerChapter(_ body: String, paged: Bool, verticalWriting: Bool = false, xhtml: Bool = false, size: CGSize = CGSize(width: 402, height: 662)) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(FolioReaderScript.readiumCFIJS)
        configuration.userContentController.addUserScript(FolioReaderScript.bridgeJS)
        configuration.userContentController.addUserScript(
            FolioReaderCSSInjector.userScript(id: FolioReaderCSSInjector.StyleID.bundle, css: FolioReaderCSSBuilder.baseStyleSheet()
                + "\nhtml, body { -webkit-transition: none !important; transition: none !important; }")
        )
        configuration.userContentController.add(MockScriptMessageHandler(), name: "FolioReaderPage")
        let webView = xhtml
            ? loadedWebView(html: """
                <?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><meta name="viewport" content="width=device-width, initial-scale=1"/></head>
                <body>\(body)</body></html>
                """, mimeType: "application/xhtml+xml", configuration: configuration)
            : loadedWebView(html: """
                <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
                <body>\(body)</body></html>
                """, configuration: configuration)

        let state = FolioReaderStyleState(styleOverride: .PNode, font: "", fontSize: "20px", fontWeight: "400", letterSpacing: 0, lineHeight: 2, textIndent: 2, marginTop: 5, marginBottom: 5, marginLeft: 5, marginRight: 5, isVerticalWritingMode: verticalWriting)
        let mode = verticalWriting ? "vertical-rl" : "horizontal-tb"
        evaluate("writingMode = '\(mode)'; document.documentElement.style.writingMode = writingMode; "
            + FolioReaderCSSInjector.runtimeStyleSource(themeMode: 0, styleState: state, runtimeSheets: [], includeDebugDump: false) + "; true", in: webView)
        let overflow = FolioReaderCSSBuilder.overflowCSS(overflow: paged ? "-webkit-paged-x" : "scroll", verticalWritingMode: verticalWriting)
        evaluate("var s = document.createElement('style'); s.textContent = \(String(reflecting: overflow)); document.head.appendChild(s); true", in: webView)
        // Resize after styling: WebKit doesn't always paginate when -webkit-paged-x arrives with no
        // viewport change after it.
        resize(webView, to: size, paged: paged)
        return webView
    }

    /// Resizes the web view and waits until the page has the new viewport and a settled layout.
    func resize(_ webView: WKWebView, to size: CGSize, paged: Bool) {
        webView.frame = CGRect(origin: .zero, size: size)
        waitUntil("viewport \(size)") {
            (evaluate("[window.innerWidth, window.innerHeight]", in: webView) as? [Double]) == [Double(size.width), Double(size.height)]
        }
        let settled = expectation(description: "layout settled")
        WebViewLayoutWaiter.wait(for: webView, timeout: 3, paged: paged) { _ in settled.fulfill() }
        wait(for: [settled], timeout: 5)
    }

    /// Scrolls the native scroll view, as the reader does, and waits until the page sees the offset;
    /// a JS `scrollTo` updates `scrollX` before the boxes follow. Retried, because the content size
    /// can lag a relayout and clamp the offset.
    func scrollNatively(_ webView: WKWebView, to point: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        let origin = scrollOrigin(webView)
        let expected = [Double(point.x - origin.x), Double(point.y - origin.y)]
        waitUntil("scrolled to \(point)", file: file, line: line) {
            webView.scrollView.setContentOffset(point, animated: false)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            guard let scroll = evaluate("[scrollX, scrollY]", in: webView) as? [Double] else { return false }
            return abs(scroll[0] - expected[0]) < 1 && abs(scroll[1] - expected[1]) < 1
        }
    }

    /// The content offset WebKit maps to `scrollX == 0`: the right end for right-to-left (vertical-rl) content.
    func scrollOrigin(_ webView: WKWebView) -> CGPoint {
        let rightToLeft = evaluate("getComputedStyle(document.documentElement).writingMode == 'vertical-rl'", in: webView) as? Bool ?? false
        return rightToLeft ? CGPoint(x: max(webView.scrollView.contentSize.width - webView.bounds.width, 0), y: 0) : .zero
    }

    func waitUntil(_ description: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for \(description)", file: file, line: line)
                return
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
    }

    /// A 320×480 web view that has finished loading `html`, parsed as `mimeType` if given.
    func loadedWebView(html: String, mimeType: String? = nil, configuration: WKWebViewConfiguration = WKWebViewConfiguration()) -> WKWebView {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), configuration: configuration)
        let loader = NavigationWaiter(expectation(description: "page loaded"))
        webView.navigationDelegate = loader
        if let mimeType = mimeType {
            webView.load(Data(html.utf8), mimeType: mimeType, characterEncodingName: "utf-8", baseURL: URL(string: "about:blank")!)
        } else {
            webView.loadHTMLString(html, baseURL: nil)
        }
        wait(for: [loader.loaded], timeout: webKitTimeout)
        return webView
    }

    /// Evaluates `script` and returns its result; a JS error fails the test.
    @discardableResult
    func evaluate(_ script: String, in webView: WKWebView, file: StaticString = #filePath, line: UInt = #line) -> Any? {
        let done = expectation(description: "evaluate")
        var output: Any?
        webView.evaluateJavaScript(script) { result, error in
            XCTAssertNil(error, "\(script) failed: \(String(describing: error))", file: file, line: line)
            output = result
            done.fulfill()
        }
        wait(for: [done], timeout: webKitTimeout)
        return output
    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    let loaded: XCTestExpectation

    init(_ loaded: XCTestExpectation) {
        self.loaded = loaded
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded.fulfill()
    }
}
