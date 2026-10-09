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
    func testRuntimeStyleSourceSwapsBodyClassesAndSetsPropertiesAgainstBridgeJS() {
        let messages = MockScriptMessageHandler()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(FolioReaderScript.bridgeJS)
        configuration.userContentController.add(messages, name: "FolioReaderPage")
        let webView = loadedWebView(configuration: configuration)
        evaluate("writingMode = 'horizontal-tb'; document.body.className = 'chapter folioStyleVertical folioStyleScopeAll'; true", in: webView)

        let styleState = FolioReaderStyleState(
            styleOverride: .PNode, font: "Gill Sans", fontSize: "20px", fontWeight: "400",
            letterSpacing: 0, lineHeight: 0, textIndent: 0,
            marginTop: 0, marginBottom: 0, marginLeft: 5, marginRight: 5,
            isVerticalWritingMode: false
        )
        for includeDebugDump in [false, true] {
            let result = evaluate(FolioReaderCSSInjector.runtimeStyleSource(
                themeMode: 1,
                styleState: styleState,
                runtimeSheets: [(id: "folio_custom_x", css: "p { color: red; }")],
                includeDebugDump: includeDebugDump
            ), in: webView)

            XCTAssertEqual(result as? String, "horizontal-tb")
            let bodyClasses = (evaluate("document.body.className", in: webView) as? String ?? "").split(separator: " ").map(String.init)
            XCTAssertEqual(Set(bodyClasses), Set(["chapter", "folioStyleHorizontal", "folioStyleScopeP", "folioStyleFontScopeP"]))
            XCTAssertEqual(evaluate("document.body.style.getPropertyValue('--folio-font-family')", in: webView) as? String, "\"Gill Sans\"")
            XCTAssertEqual(evaluate("document.body.style.getPropertyValue('--folio-padding-left')", in: webView) as? String, "2.5vw")
            XCTAssertEqual(evaluate("document.documentElement.classList.contains('serpiaMode')", in: webView) as? Bool, true)
            XCTAssertEqual(evaluate("document.getElementById('folio_custom_x').textContent", in: webView) as? String, "p { color: red; }")
        }
        XCTAssertGreaterThan(messages.messageReceivedCount, 0, "Debug dump should post to the bridge")
    }

    // MARK: - Helpers

    private func loadedWebView(configuration: WKWebViewConfiguration = WKWebViewConfiguration()) -> WKWebView {
        loadedWebView(html: page, configuration: configuration)
    }
}
