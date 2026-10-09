//
//  WebViewLayoutWaiter.swift
//  FolioReaderKit
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import WebKit

/// Waits until a web view's native scroll view reflects the page's current layout, instead of
/// sleeping for a fixed time.
///
/// Page measurements (`totalPages`, the current page) read `scrollView.contentSize`, which WebKit
/// updates only after it re-lays out the document and commits a frame to the UI process. Each poll
/// runs a script that forces layout and reports the document and viewport sizes and whether web
/// fonts have loaded. The wait ends once `contentSize` matches the expected size on two consecutive
/// polls. `timeout` caps the wait, so a page is never slower than with a fixed delay of the same length.
///
/// Under `overflow: -webkit-paged-x` the reader's documents may report their unpaginated size to
/// JavaScript while WebKit paginates the view, so in paged mode the expected size is the paginated
/// one (whole viewport pages laid side by side). The document size counts only when it already has
/// the page height: a taller document size is also what the scroll view held before pagination took
/// effect, so accepting it would end the wait too early.
enum WebViewLayoutWaiter {
    static let pollInterval: TimeInterval = 1.0 / 60.0

    struct Measurement: Equatable {
        let document: CGSize
        let viewport: CGSize
    }

    /// Reading `scrollWidth`/`scrollHeight` forces a synchronous layout, so the size is current.
    static let measureScript = """
        (function () {
            var e = document.scrollingElement || document.documentElement;
            var fontsLoaded = !document.fonts || document.fonts.status === 'loaded';
            // window.inner* is the viewport; documentElement.client* is the whole document in quirks mode.
            return JSON.stringify([e.scrollWidth, e.scrollHeight, window.innerWidth, window.innerHeight, fontsLoaded]);
        })()
        """

    /// Content sizes (CSS px) that mean the layout has been committed: the document size, or in
    /// paged mode the paginated size, plus the document size if it is already one page high.
    static func expectedContentSizes(for measurement: Measurement, paged: Bool, tolerance: CGFloat = 2) -> [CGSize] {
        let document = measurement.document
        let viewport = measurement.viewport
        guard paged, viewport.width > 0, viewport.height > 0 else { return [document] }

        var sizes = [CGSize]()
        if document.height <= viewport.height + tolerance {
            sizes.append(document)
        }
        // The 1 px slack keeps an exact multiple (7 × 662 = 4634) from rounding up a page.
        let pages = max(1, ceil((document.height - 1) / viewport.height))
        sizes.append(CGSize(width: pages * viewport.width, height: viewport.height))
        return sizes
    }

    /// Whether the native content size matches an expected size (CSS px scaled by the zoom).
    static func layoutMatches(contentSize: CGSize, documentSize: CGSize, zoomScale: CGFloat, tolerance: CGFloat = 2) -> Bool {
        abs(contentSize.width - documentSize.width * zoomScale) <= tolerance
            && abs(contentSize.height - documentSize.height * zoomScale) <= tolerance
    }

    /// Parses the result of `measureScript`, or returns `nil` while web fonts are still loading.
    static func measurement(from result: Any?) -> Measurement? {
        guard let json = result as? String,
              let data = json.data(using: .utf8),
              let values = (try? JSONSerialization.jsonObject(with: data)) as? [Any],
              values.count == 5,
              (values[4] as? Bool) == true else {
            return nil
        }
        let numbers = values[0..<4].compactMap { ($0 as? NSNumber)?.doubleValue }
        guard numbers.count == 4 else { return nil }
        return Measurement(document: CGSize(width: numbers[0], height: numbers[1]),
                           viewport: CGSize(width: numbers[2], height: numbers[3]))
    }

    /// Calls `completion(true)` once the layout has settled, or `completion(false)` after `timeout`
    /// (or if the web view goes away). Always calls back on the main queue.
    static func wait(for webView: WKWebView, timeout: TimeInterval, paged: Bool = false, label: String = "", completion: @escaping (_ settled: Bool) -> Void) {
        let interval = FolioSignpost.begin("LayoutWait", label)
        let deadline = Date().addingTimeInterval(timeout)
        var matchedPolls = 0
        var lastMeasurement = "none"
        // `poll` is retained by the scheduled retries, so it must not hold the web view itself.
        weak var weakWebView = webView

        func gone() {
            interval.end("gone")
            completion(false)
        }

        func poll() {
            guard let webView = weakWebView else { return gone() }
            webView.evaluateJavaScript(measureScript) { result, _ in
                guard let webView = weakWebView else { return gone() }
                let contentSize = webView.scrollView.contentSize
                let zoomScale = webView.scrollView.zoomScale
                if let measurement = measurement(from: result),
                   expectedContentSizes(for: measurement, paged: paged).contains(where: {
                       layoutMatches(contentSize: contentSize, documentSize: $0, zoomScale: zoomScale)
                   }) {
                    matchedPolls += 1
                } else {
                    matchedPolls = 0
                }
                lastMeasurement = "js=\(result ?? "nil") content=\(Int(contentSize.width))x\(Int(contentSize.height)) zoom=\(zoomScale)"

                if matchedPolls >= 2 {
                    interval.end("settled \(label)")
                    completion(true)
                } else if Date() >= deadline {
                    interval.end("timeout \(label) \(lastMeasurement)")
                    completion(false)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) { poll() }
                }
            }
        }
        poll()
    }
}
