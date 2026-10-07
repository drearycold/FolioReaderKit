//
//  FolioReaderCSSInjector.swift
//  FolioReaderKit
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import WebKit

/// Adds or replaces `<style id=...>` elements in a page.
///
/// CSS and ids travel to JS as base64 and are decoded as UTF-8 in the page, so their content
/// never has to be escaped into a JS string literal.
enum FolioReaderCSSInjector {

    /// Internal `<style>` ids. Document-base sheets (bundle, user font faces, then custom) are injected
    /// at document end; runtime custom sheets follow the overflow sheet.
    enum StyleID {
        static let bundle = "folio_bundle_style"
        static let userFontFaces = "folio_style_user_font_faces"
        static let overflow = "folio_style_overflow"
        static let customPrefix = "folio_custom_"
    }

    /// Self-contained JS that creates `<style id=id>` in `<head>` if needed and sets its text to `css`.
    /// The leading `;` keeps it a separate statement wherever it is concatenated.
    static func upsertSource(id: String, css: String) -> String {
        """
        ;(function () {
            function folioDecode(b64) {
                return new TextDecoder().decode(Uint8Array.from(atob(b64), function (c) { return c.charCodeAt(0); }));
            }
            var id = folioDecode('\(Data(id.utf8).base64EncodedString())');
            var style = document.getElementById(id);
            if (style == null) {
                style = document.createElement('style');
                style.type = 'text/css';
                style.id = id;
                (document.head || document.documentElement).appendChild(style);
            }
            style.textContent = folioDecode('\(Data(css.utf8).base64EncodedString())');
            return true;
        })();
        """
    }

    /// Script run by `FolioReaderPage.updateRuntimeStyle`: applies the theme, swaps the `folioStyle*`
    /// classes and sets the `--folio-*` properties on `<body>` for `styleState`, re-applies runtime
    /// custom sheets, and evaluates to the page's `writingMode`.
    /// Relies on `Bridge.js` (`themeMode`, `removeClasses`, `addClass`) and the global `writingMode`
    /// set by `updateOverflowStyle`.
    static func runtimeStyleSource(themeMode: Int, styleState: FolioReaderStyleState, runtimeSheets: [(id: String, css: String)], includeDebugDump: Bool) -> String {
        let bodyClassesJSON = json(FolioReaderCSSBuilder.bodyClasses(for: styleState))
        let propertiesJSON = json(FolioReaderCSSBuilder.customProperties(for: styleState).map { [$0.name, $0.value] })
        let sheets = runtimeSheets.map { upsertSource(id: $0.id, css: $0.css) }.joined(separator: "\n")
        // Posts the whole chapter HTML over the bridge (and to a temp file), so only when debugging styles.
        let debugDump = includeDebugDump ? """
            window.webkit.messageHandlers.FolioReaderPage.postMessage("bridgeFinished " + getHTML());
            window.webkit.messageHandlers.FolioReaderPage.postMessage("getComputedStyle document.documentElement " + window.getComputedStyle(document.documentElement).cssText);
            window.webkit.messageHandlers.FolioReaderPage.postMessage("getComputedStyle document.body" + window.getComputedStyle(document.body).cssText);
            window.webkit.messageHandlers.FolioReaderPage.postMessage("writingMode " + writingMode);
            """ : ""

        return """
            themeMode(\(themeMode));
            removeClasses(document.body, 'folioStyle\\\\w+');
            \(bodyClassesJSON).forEach(function (cls) { addClass(document.body, cls); });
            \(propertiesJSON).forEach(function (property) { document.body.style.setProperty(property[0], property[1]); });
            if (writingMode == 'vertical-rl') {
                document.body.style.minWidth = "100vw";
            } else {
                document.body.style.minHeight = "100vh";
            }
            \(sheets)
            \(debugDump)
            writingMode
            """
    }

    /// A document-end user script that injects `css` on every page load of the web view.
    static func userScript(id: String, css: String) -> FolioReaderScript {
        FolioReaderScript(source: upsertSource(id: id, css: css))
    }

    /// Injects `css` into the currently loaded page.
    static func apply(id: String, css: String, to webView: FolioReaderWebView, completion: (() -> Void)? = nil) {
        webView.js(upsertSource(id: id, css: css)) { _ in completion?() }
    }

    /// Custom sheets for `stage` with their injected ids, in first-appearance order; a repeated id keeps the last CSS.
    static func customSheets(_ sheets: [FolioReaderStyleSheet], stage: FolioReaderCSSStage) -> [(id: String, css: String)] {
        var order = [String]()
        var cssByID = [String: String]()
        for sheet in sheets where sheet.stage == stage {
            let id = StyleID.customPrefix + sheet.id
            if cssByID[id] == nil {
                order.append(id)
            }
            cssByID[id] = sheet.css
        }
        return order.map { (id: $0, css: cssByID[$0] ?? "") }
    }

    private static func json<T: Encodable>(_ value: T) -> String {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}
