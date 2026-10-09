//
//  ReaderStyleRenderingTests.swift
//  FolioReaderKitTests
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import WebKit
import XCTest
@testable import FolioReaderKit

/// Renders a chapter-like page under many reader style settings and snapshots the computed styles.
///
/// The snapshot (`__Snapshots__/ReaderStyleRenderingTests/computedStyles.txt`) records what WebKit
/// actually applies, not the CSS text, so it stays valid when the way styles are generated changes.
@MainActor
class ReaderStyleRenderingTests: XCTestCase {

    /// Author styles that the reader settings have to win against, or leave alone. Transitions are off
    /// because `Style.css` animates `html` and `body`, and the snapshot must hold the settled values.
    private let page = """
        <html><head><style>
        html, body { -webkit-transition: none !important; transition: none !important; }
        body { margin: 8px; }
        p { margin: 0.5em 0; text-indent: 2em; font-size: 12px; line-height: 1.2; }
        td, span { font-size: 13px; letter-spacing: 1px; }
        img { margin: 3px; }
        </style></head><body class="chapter">
        <h1 id="h1">Title</h1>
        <p id="p">Paragraph <span id="spanInP">span</span></p>
        <div id="div">Div <span id="span">span</span></div>
        <table><tr><td id="td">cell</td></tr></table>
        <p><img id="imgInP" class="folioImg" width="10" height="10"></p>
        <div><img id="imgInDiv" class="folioImg" width="10" height="10"></div>
        </body></html>
        """

    private let textProperties = [
        "font-family", "font-size", "font-weight", "letter-spacing", "line-height", "text-indent",
        "text-align", "-webkit-hyphens",
        "margin-top", "margin-right", "margin-bottom", "margin-left",
        "padding-top", "padding-right", "padding-bottom", "padding-left", "overflow",
    ]
    private let imageProperties = [
        "max-height", "max-width", "margin-top", "margin-right", "margin-bottom", "margin-left", "overflow",
    ]

    func testComputedStylesSnapshot() {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(FolioReaderScript.bridgeJS)
        configuration.userContentController.addUserScript(
            FolioReaderCSSInjector.userScript(id: FolioReaderCSSInjector.StyleID.bundle, css: FolioReaderCSSBuilder.baseStyleSheet())
        )
        let webView = loadedWebView(html: page, configuration: configuration)

        var lines = [String]()
        for (label, state) in Self.cases() {
            let writingMode = state.isVerticalWritingMode ? "vertical-rl" : "horizontal-tb"
            evaluate("writingMode = '\(writingMode)'; document.documentElement.style.writingMode = writingMode; true", in: webView)
            evaluate(applyStyle(state), in: webView)
            lines.append("## \(label)")
            lines.append(evaluate(collectSource(), in: webView) as? String ?? "<no result>")
        }

        assertSnapshot(lines.joined(separator: "\n") + "\n", named: "computedStyles.txt")
    }

    /// Backs the `FolioReaderConfig.customStyleSheets` documentation: `!important` alone loses to the
    /// reader's `html body.folioStyleScopeP p` rule, and a selector of equal specificity wins by coming later.
    func testCustomRulesNeedImportantAndMatchingSpecificity() {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(FolioReaderScript.bridgeJS)
        configuration.userContentController.addUserScript(
            FolioReaderCSSInjector.userScript(id: FolioReaderCSSInjector.StyleID.bundle, css: FolioReaderCSSBuilder.baseStyleSheet())
        )
        let webView = loadedWebView(html: page, configuration: configuration)
        let state = Self.cases()[1].1   // horizontal, override=only <p>, font size 18.5px
        XCTAssertEqual(state.styleOverride, .PNode)

        func paragraphFontSize(withCustomRule rule: String) -> String? {
            evaluate("writingMode = 'horizontal-tb'; true", in: webView)
            evaluate(FolioReaderCSSInjector.runtimeStyleSource(
                themeMode: 0,
                styleState: state,
                runtimeSheets: [(id: "folio_custom_test", css: rule)],
                includeDebugDump: false
            ), in: webView)
            return evaluate("window.getComputedStyle(document.getElementById('p')).fontSize", in: webView) as? String
        }

        XCTAssertEqual(paragraphFontSize(withCustomRule: "p { font-size: 30px !important; }"), "18.5px")
        XCTAssertEqual(paragraphFontSize(withCustomRule: "html:root body p { font-size: 30px !important; }"), "30px")
    }

    /// The script `FolioReaderPage.updateRuntimeStyle` runs for `state`.
    private func applyStyle(_ state: FolioReaderStyleState) -> String {
        FolioReaderCSSInjector.runtimeStyleSource(
            themeMode: 0,
            styleState: state,
            runtimeSheets: [],
            includeDebugDump: false
        )
    }

    /// One line per element: `<id>: <property>=<computed value>; ...`.
    private func collectSource() -> String {
        func json(_ value: [String]) -> String {
            String(data: try! JSONEncoder().encode(value), encoding: .utf8)!
        }
        return """
            (function () {
                var text = \(json(textProperties)), image = \(json(imageProperties));
                return [['body', text], ['h1', text], ['p', text], ['spanInP', text], ['div', text],
                        ['span', text], ['td', text], ['imgInP', image], ['imgInDiv', image]].map(function (entry) {
                    var element = entry[0] == 'body' ? document.body : document.getElementById(entry[0]);
                    var style = window.getComputedStyle(element);
                    return entry[0] + ': ' + entry[1].map(function (name) {
                        return name + '=' + style.getPropertyValue(name);
                    }).join('; ');
                }).join('\\n');
            })()
            """
    }

    private static func cases() -> [(String, FolioReaderStyleState)] {
        let base = FolioReaderStyleState(
            styleOverride: .AllText,
            font: "Helvetica Neue",
            fontSize: "18.5px",
            fontWeight: "400",
            letterSpacing: 2,
            lineHeight: 3,
            textIndent: 1,
            marginTop: 10,
            marginBottom: 15,
            marginLeft: 20,
            marginRight: 25,
            isVerticalWritingMode: false
        )

        var cases = [(String, FolioReaderStyleState)]()
        for vertical in [false, true] {
            let mode = vertical ? "vertical" : "horizontal"
            func add(_ label: String, _ change: (inout FolioReaderStyleState) -> Void) {
                var state = base
                state.isVerticalWritingMode = vertical
                change(&state)
                cases.append(("\(mode) \(label)", state))
            }

            for level in StyleOverrideTypes.allCases {
                add("override=\(level.description)") { $0.styleOverride = level }
            }
            for size in ["15.5px", "35.5px"] {
                add("fontSize=\(size)") { $0.fontSize = size }
            }
            for weight in ["100", "900"] {
                add("fontWeight=\(weight)") { $0.fontWeight = weight }
            }
            for value in [0, 5, 10] {
                add("letterSpacing=\(value)") { $0.letterSpacing = value }
                add("lineHeight=\(value)") { $0.lineHeight = value }
            }
            for indent in -4...4 {
                add("textIndent=\(indent)") { $0.textIndent = indent }
            }
            for margin in [0, 5, 25, 50] {
                add("margins=\(margin)") {
                    $0.marginTop = margin
                    $0.marginBottom = margin
                    $0.marginLeft = margin
                    $0.marginRight = margin
                }
            }
            add("font=Gill Sans, override=PNode") {
                $0.font = "Gill Sans"
                $0.styleOverride = .PNode
            }
        }
        return cases
    }
}
