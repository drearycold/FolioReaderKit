//
//  BridgeHighlightTests.swift
//  FolioReaderKitTests
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import WebKit
import XCTest
@testable import FolioReaderKit

/// Runs `Bridge.js`'s `injectHighlights` with the real CFI library in a `WKWebView`.
@MainActor
class BridgeHighlightTests: XCTestCase {

    /// A highlight without its encoded content fields and with an unusable CFI (what a host can
    /// persist by mistake) must come back as a per-highlight error, not abort the batch.
    func testMalformedHighlightIsReportedNotThrown() throws {
        warmUpWebKit()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(FolioReaderScript.readiumCFIJS)
        configuration.userContentController.addUserScript(FolioReaderScript.bridgeJS)
        configuration.userContentController.add(MockScriptMessageHandler(), name: "FolioReaderPage")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), configuration: configuration)
        let loader = BridgePageLoadWaiter(expectation(description: "page loaded"))
        webView.navigationDelegate = loader
        webView.loadHTMLString("<html><head></head><body><p id=\"p1\">Some text to highlight.</p></body></html>", baseURL: nil)
        wait(for: [loader.loaded], timeout: webKitTimeout)

        let malformed = #"[{"highlightId":"h1","cfiStart":"/4/2[nope]:0","cfiEnd":"/4/2[nope]:4","style":"highlight-yellow"},{"highlightId":"h2"}]"#
        let encoded = Data(malformed.utf8).base64EncodedString()

        let done = expectation(description: "injectHighlights returned")
        var output: Any?
        var scriptError: Error?
        webView.evaluateJavaScript("injectHighlights('\(encoded)')") { result, error in
            output = result
            scriptError = error
            done.fulfill()
        }
        wait(for: [done], timeout: webKitTimeout)

        XCTAssertNil(scriptError, "injectHighlights must not throw: \(String(describing: scriptError))")
        let results = try XCTUnwrap((output as? String)?.data(using: .utf8).flatMap { try? JSONDecoder().decode([String].self, from: $0) })
        XCTAssertEqual(results.count, 2, "One result per highlight")
        for result in results {
            let object = try XCTUnwrap(try? JSONDecoder().decode(NodeBoundingClientRect.self, from: Data(result.utf8)))
            XCTAssertFalse(object.err.isEmpty, "Each malformed highlight reports an error: \(result)")
        }
    }
}

@MainActor
private final class BridgePageLoadWaiter: NSObject, WKNavigationDelegate {
    let loaded: XCTestExpectation

    init(_ loaded: XCTestExpectation) {
        self.loaded = loaded
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded.fulfill()
    }
}
