//
//  FolioReaderCSSInjectorTests.swift
//  FolioReaderKitTests
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import WebKit
import XCTest
@testable import FolioReaderKit

/// Runs `FolioReaderCSSInjector` output in a real `WKWebView`.
@MainActor
class FolioReaderCSSInjectorTests: XCTestCase {

    private let page = "<html><head></head><body><p>x</p></body></html>"

    /// Content that broke the previous `innerHTML = '...'` injection or bare `atob` decoding.
    private let hostileCSS = """
        p::before { content: 'it\\'s "quoted"'; }
        /* back\\slash */ </style><script>window.injected = true</script>
        body { font-family: "思源宋体", serif; }
        """

    func testUpsertRoundTripsHostileCSSWithoutParsingIt() {
        let webView = loadedWebView()

        evaluate(FolioReaderCSSInjector.upsertSource(id: "folio_test", css: hostileCSS), in: webView)

        XCTAssertEqual(evaluate("document.getElementById('folio_test').textContent", in: webView) as? String, hostileCSS)
        XCTAssertEqual(evaluate("document.querySelectorAll('style, script').length", in: webView) as? Int, 1)
        XCTAssertEqual(evaluate("window.injected === undefined", in: webView) as? Bool, true)
    }

    func testUpsertWithSameIDReplacesContent() {
        let webView = loadedWebView()

        evaluate(FolioReaderCSSInjector.upsertSource(id: "folio_test", css: "p { color: red; }"), in: webView)
        evaluate(FolioReaderCSSInjector.upsertSource(id: "folio_test", css: "p { color: blue; }"), in: webView)

        XCTAssertEqual(evaluate("document.querySelectorAll('style').length", in: webView) as? Int, 1)
        XCTAssertEqual(evaluate("document.getElementById('folio_test').textContent", in: webView) as? String, "p { color: blue; }")
    }

    func testUpsertHandlesIDsThatNeedEscaping() {
        let webView = loadedWebView()
        let id = "folio_custom_it's \"odd\""

        evaluate(FolioReaderCSSInjector.upsertSource(id: id, css: "p {}"), in: webView)

        XCTAssertEqual(evaluate("document.querySelector('style').id", in: webView) as? String, id)
    }

    func testUserScriptInjectsOnPageLoad() {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(FolioReaderCSSInjector.userScript(id: "folio_test", css: hostileCSS))
        let webView = loadedWebView(configuration: configuration)

        XCTAssertEqual(evaluate("document.getElementById('folio_test').textContent", in: webView) as? String, hostileCSS)
    }

    /// Runs the real `updateRuntimeStyle` script against `Bridge.js`; a JS syntax or runtime error fails `evaluate`.
    func testRuntimeStyleSourceSwapsBodyClassesAgainstBridgeJS() {
        let messages = MockScriptMessageHandler()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(FolioReaderScript.bridgeJS)
        configuration.userContentController.add(messages, name: "FolioReaderPage")
        let webView = loadedWebView(configuration: configuration)
        evaluate("writingMode = 'horizontal-tb'; document.body.className = 'chapter folioStyleL1FontSize17px'; true", in: webView)

        let classes = ["folioStyleBodyPaddingLeft1", "folioStyleBodyPaddingRight1", "folioStyleL1FontSize20px"]
        for includeDebugDump in [false, true] {
            let result = evaluate(FolioReaderCSSInjector.runtimeStyleSource(
                themeMode: 1,
                bodyClasses: classes,
                runtimeSheets: [(id: "folio_custom_x", css: "p { color: red; }")],
                includeDebugDump: includeDebugDump
            ), in: webView)

            XCTAssertEqual(result as? String, "horizontal-tb")
            let bodyClasses = (evaluate("document.body.className", in: webView) as? String ?? "").split(separator: " ").map(String.init)
            XCTAssertEqual(Set(bodyClasses), Set(["chapter"] + classes))
            XCTAssertEqual(evaluate("document.documentElement.classList.contains('serpiaMode')", in: webView) as? Bool, true)
            XCTAssertEqual(evaluate("document.getElementById('folio_custom_x').textContent", in: webView) as? String, "p { color: red; }")
        }
        XCTAssertGreaterThan(messages.messageReceivedCount, 0, "Debug dump should post to the bridge")
    }

    // MARK: - Helpers

    private func loadedWebView(configuration: WKWebViewConfiguration = WKWebViewConfiguration()) -> WKWebView {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), configuration: configuration)
        let loader = NavigationWaiter(expectation(description: "page loaded"))
        webView.navigationDelegate = loader
        webView.loadHTMLString(page, baseURL: nil)
        wait(for: [loader.loaded], timeout: 10)
        return webView
    }

    @discardableResult
    private func evaluate(_ script: String, in webView: WKWebView, file: StaticString = #filePath, line: UInt = #line) -> Any? {
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
