//
//  WebViewTestSupport.swift
//  FolioReaderKitTests
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import WebKit
import XCTest

@MainActor
extension XCTestCase {
    /// A 320×480 web view that has finished loading `html`.
    func loadedWebView(html: String, configuration: WKWebViewConfiguration = WKWebViewConfiguration()) -> WKWebView {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), configuration: configuration)
        let loader = NavigationWaiter(expectation(description: "page loaded"))
        webView.navigationDelegate = loader
        webView.loadHTMLString(html, baseURL: nil)
        wait(for: [loader.loaded], timeout: 10)
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
        wait(for: [done], timeout: 10)
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
