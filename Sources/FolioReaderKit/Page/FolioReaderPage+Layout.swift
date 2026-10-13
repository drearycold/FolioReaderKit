//
//  FolioReaderPage+Layout.swift
//  FolioReaderKit
//

import UIKit

extension FolioReaderPage {
    // MARK: Change layout orientation
    func setScrollDirection(_ direction: FolioReaderScrollDirection) {
        // The first text on screen, for the new layout to start from. The offset ratio, the fallback,
        // doesn't carry over between paged and scroll layouts, whose content sizes differ: switching
        // went back about a screen, or to the start of the chapter.
        relayout(direction: direction, keepingFirstVisibleText: true)
    }

    /// Lays the page out again after the two-page spread setting changed (`spreadMinimumWidth`).
    /// Both layouts are paged, so it keeps what a rotation keeps: the pinned position, else the middle
    /// of the page. Keeping the first visible text went back a spread on every round trip, as the
    /// single page that holds a spread's first line starts before the spread.
    func applySpreadSetting() {
        guard let webView = webView else { return }
        // Where neither setting shows a spread (portrait, narrower than the minimum: the media query
        // in `spreadRules`), only the rules for a later rotation change, and the pages stay as they
        // are. The web view's size would tell only for one page: a spread's is narrower.
        guard fitsSpread(minimumWidth: readerConfig.spreadMinimumWidth) else {
            FolioReaderCSSInjector.apply(id: FolioReaderCSSInjector.StyleID.overflow, css: overflowCSS(for: webView), to: webView)
            return
        }
        relayout(direction: readerConfig.scrollDirection, keepingFirstVisibleText: false)
    }

    private func relayout(direction: FolioReaderScrollDirection, keepingFirstVisibleText: Bool) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        guard self.folioReader.readerCenter != nil, webView != nil else {
            readerConfig.applyEffectiveScrollDirection(direction)
            return
        }

        self.layoutAdapting = .scrollDirection

        // Both are measured in the current layout, so the reader config must still have the current
        // direction. The settings applied the new one first, which measured a scrolled page along
        // the paged axis: the position became the chapter heading, and the offset ratio 0.
        self.updatePageOffsetRate()

        // The pinned position needs no measuring.
        if !keepingFirstVisibleText, let pinned = pinnedPosition {
            let restorable = FolioReaderCenter.isRestorableCFI(pinned.cfi, pageNumber: pageNumber)
            applyScrollDirection(direction, restoring: restorable ? pinned : nil)
            return
        }
        getWebViewScrollPosition(firstVisibleText: keepingFirstVisibleText, onFailure: {
            self.applyScrollDirection(direction, restoring: nil)
        }) { position in
            let restorable = FolioReaderCenter.isRestorableCFI(position.cfi, pageNumber: self.pageNumber)
            self.applyScrollDirection(direction, restoring: restorable ? position : nil)
        }
    }

    private func applyScrollDirection(_ direction: FolioReaderScrollDirection, restoring anchorPosition: FolioReaderReadPosition?) {
        guard let readerCenter = self.folioReader.readerCenter, let webView = webView else {
            self.layoutAdapting = nil
            return
        }
        let currentPageNumber = readerCenter.currentPageNumber

        // Change layout
        self.readerConfig.applyEffectiveScrollDirection(direction)
        readerCenter.collectionViewLayout.scrollDirection = .direction(withConfiguration: self.readerConfig)
        self.setNeedsLayout()
        readerCenter.collectionView.collectionViewLayout.invalidateLayout()
        let frameForPage = readerCenter.frameForPage(currentPageNumber)
        readerCenter.collectionView.setContentOffset(frameForPage.origin, animated: false)
        readerCenter.updateOtherVisiblePages(except: self)

        // Page progressive direction
        readerCenter.setCollectionViewProgressiveDirection()
        DispatchQueue.main.asyncAfter(delay: 0.2) { readerCenter.setPageProgressiveDirection(self) }

        /**
         *  This delay is needed because the page will not be ready yet
         *  so the delay wait until layout finished the changes.
         */
        
        DispatchQueue.main.asyncAfter(delay: delaySec()) {
            webView.setupScrollDirection()
            self.updateOverflowStyle(delay: self.delaySec()) {
                if anchorPosition == nil {
                    self.scrollWebViewByPageOffsetRate(animated: false)
                }

                DispatchQueue.main.asyncAfter(delay: self.delaySec() + 0.2) {
                    self.updatePageInfo() {
                        guard let anchorPosition = anchorPosition else {
                            self.updateScrollPosition(delay: self.delaySec()) {
                                self.updateStyleBackgroundPadding(delay: self.delaySec()) {
                                    self.layoutAdapting = nil
                                }
                            }
                            return
                        }
                        self.updateStyleBackgroundPadding(delay: self.delaySec()) {
                            // handleAnchor waits while the page is adapting.
                            self.layoutAdapting = nil
                            self.restorePinned(anchorPosition) {
                                self.updatePageOffsetRate()
                                self.updatePageInfo()
                            }
                        }
                    }
                }
            }
        }
    }

    func updateOverflowStyle(delay bySecond: Double, completion: (() -> Void)? = nil) {
        guard let webView = webView else { return }
        
        self.layoutAdapting = .layout
        
        let overflowInterval = FolioSignpost.begin("OverflowJS", "page \(pageNumber)")
        webView.js(
"""
writingMode = window.getComputedStyle(document.body).getPropertyValue("writing-mode")

{
    var viewport = document.querySelector("meta[name=viewport]");
    if (viewport) {
        if (writingMode == "vertical-rl") {
            viewport.setAttribute('content', 'height=device-height, initial-scale=1.0, maximum-scale=1.0, user-scalable=0, viewport-fit=cover');
        } else {
            viewport.setAttribute('content', 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=0, viewport-fit=cover');
        }
    } else {
        var metaTag=document.createElement('meta');
        metaTag.name = "viewport"
        if (writingMode == "vertical-rl") {
            metaTag.content = "height=device-height, initial-scale=1.0, maximum-scale=1.0, user-scalable=0, viewport-fit=cover"
        } else {
            metaTag.content = "width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=0, viewport-fit=cover"
        }
        document.head.appendChild(metaTag);
    }
}

document.body.style.minHeight = null;
document.body.style.minWidth = null;
document.body.style.width = null;

writingMode
"""
        ) { writingMode in
            overflowInterval.end()
            let laidOut = (self.writingMode, self.pagesDown)
            if let writingMode = writingMode {
                self.writingMode = writingMode
            }
            // Vertical writing in `.vertical` pages down: the scroll view pages now that it's known.
            self.pagesDown = self.writingMode == "vertical-rl" && self.readerConfig.isDirection(true, false, false)
            webView.setupScrollDirection()
            // The web view's frame follows both. A reused cell computed it for the chapter it showed
            // before, and the load chain lays it out again only for vertical writing.
            if (self.writingMode, self.pagesDown) != laidOut {
                self.setNeedsLayout()
            }
            // The overflow CSS depends on the writing mode, which is only known after the script above.
            let overflowCSSInterval = FolioSignpost.begin("OverflowCSS", "page \(self.pageNumber)")
            FolioReaderCSSInjector.apply(
                id: FolioReaderCSSInjector.StyleID.overflow,
                css: self.overflowCSS(for: webView),
                to: webView
            ) {
                overflowCSSInterval.end()
                self.waitForLayout(timeout: bySecond, label: "overflow") {
                    completion?()
                }
            }
        }
    }
    
    /// The `folio_style_overflow` CSS for the current layout, with the spread setting in effect now,
    /// which it records (`spreadMinimumWidth`): a page that was in scroll mode or vertical writing
    /// when the setting changed may have kept the old one. It records the layout too (`recordLayout`).
    private func overflowCSS(for webView: FolioReaderWebView) -> String {
        if let readerCenter = folioReader.readerCenter {
            spreadMinimumWidth = readerCenter.spreadMinimumWidth
        }
        recordLayout()
        return FolioReaderCSSBuilder.overflowCSS(overflow: webView.cssOverflowProperty, verticalWritingMode: writingMode == "vertical-rl", spreadMinimumWidth: spreadMinimumWidth, tiersMinimumHeight: pagesDown ? readerConfig.tiersMinimumHeight : nil)
    }

    /// Records the scroll direction and web view size the chapter is laid out for, which
    /// `FolioReaderCenter.hasOtherLayout` compares with the current ones: when it is loaded, and when
    /// its overflow style is chosen, once its writing mode is known. The spread setting too, which
    /// the size depends on.
    func recordLayout() {
        layoutScrollDirection = readerConfig.scrollDirection
        layoutSpreadMinimumWidth = spreadMinimumWidth
        layoutSize = webViewFrame().size
    }

    /// Continues once the web view's native content size reflects the current layout, or after
    /// `timeout` at the latest (the fixed delay this replaces). See `WebViewLayoutWaiter`.
    func waitForLayout(timeout: Double, label: String, _ completion: @escaping () -> Void) {
        guard let webView = webView else {
            DispatchQueue.main.asyncAfter(delay: timeout, execute: completion)
            return
        }
        let paged = webView.cssOverflowProperty == "-webkit-paged-x"
        WebViewLayoutWaiter.wait(for: webView, timeout: timeout, paged: paged, label: "\(label) page \(pageNumber)") { _ in
            completion()
        }
    }

    func updateRuntimeStyle(delay bySecond: Double, completion: (() -> Void)? = nil) {
        guard let webView = webView else { return }

        self.layoutAdapting = .style
        self.updatePageOffsetRate()
        // A spread's or tiers' outer margins are outside the web view, so its frame follows the margins.
        self.setNeedsLayout()

        let styleState = currentStyleState()
        recordStyle(styleState)
        let script = FolioReaderCSSInjector.runtimeStyleSource(
            themeMode: folioReader.themeMode,
            styleState: styleState,
            runtimeSheets: FolioReaderCSSInjector.customSheets(readerConfig.customStyleSheets, stage: .runtime),
            includeDebugDump: readerConfig.debug.contains(.htmlStyling)
        )

        let runtimeStyleInterval = FolioSignpost.begin("RuntimeStyleJS", "page \(pageNumber)")
        webView.js(script) { _ in
            runtimeStyleInterval.end()
            let delaySec = self.delaySec() + bySecond
            self.waitForLayout(timeout: delaySec, label: "runtimeStyle") {
                self.layoutAdapting = .almostReady
                self.updatePageInfo {
                    self.waitForLayout(timeout: delaySec, label: "pageInfo") {
                        self.updateStyleBackgroundPadding(delay: delaySec, completion: completion != nil ? completion : {
                            self.updatePageInfo() {
                                // Restored by ratio, not to the pinned position: record what it shows.
                                self.pinnedPosition = nil
                                self.scrollWebViewByPageOffsetRate()
                                DispatchQueue.main.asyncAfter(delay: delaySec) {
                                    self.updatePageOffsetRate()
                                    self.layoutAdapting = nil
                                    self.updatePageInfo()
                                }
                            }
                        })
                    }
                }
            }
        }
    }

    /// The style settings `updateRuntimeStyle` applies now.
    func currentStyleState() -> FolioReaderStyleState {
        FolioReaderStyleState(preferences: folioReader.preferences, isVerticalWritingMode: writingMode == "vertical-rl", reserveSafeArea: readerConfig.reserveSafeAreaInsidePageFrame, userFontDescriptors: readerConfig.userFontDescriptors)
    }

    /// Records the style settings and theme the chapter is styled with, which
    /// `FolioReaderCenter.hasOtherStyle` and `hasOtherTheme` compare with the current ones.
    func recordStyle(_ styleState: FolioReaderStyleState) {
        self.styleState = styleState
        styledThemeMode = folioReader.themeMode
    }

    /// Styles a chapter kept next to the current page with the current settings, and returns it to
    /// `position`, the one it recorded: the offset ratio `updateRuntimeStyle` restores otherwise
    /// lands elsewhere in reflowed text. Without a position it restores the ratio.
    func restyle(restoring position: FolioReaderReadPosition?) {
        guard let position = position else {
            updateRuntimeStyle(delay: 0.4)
            return
        }
        // Still this chapter: the cell may be reused, or the chapter reloaded, meanwhile.
        let pageNumber = self.pageNumber
        let loadGeneration = self.loadGeneration
        updateRuntimeStyle(delay: 0.4) {
            guard self.pageNumber == pageNumber, self.loadGeneration == loadGeneration else { return }
            // handleAnchor waits while the page is adapting.
            self.layoutAdapting = nil
            self.restorePinned(position) {
                self.updatePageOffsetRate()
                self.updatePageInfo()
            }
        }
    }

    func updateStyleBackgroundPadding(delay bySecond: Double, tryShrinking: Bool = true, completion: (() -> Void)? = nil) {
        // Every layout pass ends here, a rotation's too: the padding, and the offsets set after it,
        // fit this size.
        layoutSize = webViewFrame().size
        let fillsScreens = self.byWritingMode(self.readerConfig.scrollDirection == .horizontalWithPagedContent, true)
        let step = BackgroundPaddingSearch.Step(screens: fillsScreens ? max(self.totalPages ?? 1, 1) : 1, shrinking: tryShrinking)
        applyBackgroundPadding(step, search: BackgroundPaddingSearch(), fillsScreens: fillsScreens, delay: bySecond, completion: completion)
    }

    private func applyBackgroundPadding(_ step: BackgroundPaddingSearch.Step, search: BackgroundPaddingSearch, fillsScreens: Bool, delay bySecond: Double, completion: (() -> Void)?) {
        self.layoutAdapting = .finalizing

        // must set width instead of minWidth, otherwise there will be an extra blank page after calling scrollView.setContentOffset
        // could be a bug?
        // and shrinking by 100vw has no effect on totalPages
        let paddingInterval = FolioSignpost.begin("PaddingJS", "page \(pageNumber)")
        self.webView?.js(BackgroundPaddingSearch.script(for: step)) { _ in
            paddingInterval.end()
            self.waitForLayout(timeout: bySecond, label: "padding") {
                self.updatePageInfo {
                    let totalPages = self.totalPages ?? 0
                    FolioLogger.log("updateStyleBackgroundPadding pageNumber=\(self.pageNumber) minScreenCount=\(step.screens) totalPages=\(totalPages) tryShrinking=\(step.shrinking)")
                    var search = search
                    guard fillsScreens, let next = search.next(after: step, totalPages: totalPages) else {
                        if fillsScreens, step.shrinking || totalPages != step.screens {
                            FolioLogger.log("updateStyleBackgroundPadding pageNumber=\(self.pageNumber) gave up: the page count doesn't follow the body")
                        }
                        completion?()
                        return
                    }
                    self.applyBackgroundPadding(next, search: search, fillsScreens: fillsScreens, delay: bySecond, completion: completion)
                }
            }
        }
    }
    
    func updateViewerLayout(delay bySecond: Double) {
        guard let webView = webView else { return }
        
        self.layoutAdapting = .viewerLayout
        self.updatePageOffsetRate()
        
        webView.js(
        """
            document.body.style.minHeight = null;
            document.body.style.minWidth = null;
        """) { _ in
            self.setNeedsLayout()
            
            DispatchQueue.main.asyncAfter(delay: self.delaySec() + bySecond) {
                self.updatePageInfo {
                    self.updateStyleBackgroundPadding(delay: self.delaySec()) {
                        // Restored by ratio, not to the pinned position: record what it shows.
                        self.pinnedPosition = nil
                        self.scrollWebViewByPageOffsetRate()
                        DispatchQueue.main.asyncAfter(delay: 0.2) {
                            self.updatePageOffsetRate()
                            self.layoutAdapting = nil
                            self.updatePageInfo()
                        }
                    }
                }
            }
        }
    }
}

/// `updateStyleBackgroundPadding`'s search for the body size that fills whole screens, so the last
/// page has the page background: it sizes the body short of the page count while the count falls,
/// then to the count.
struct BackgroundPaddingSearch {
    struct Step: Hashable {
        /// The page count the body is sized from.
        let screens: Int
        /// The body is sized short of `screens` (two screens in vertical writing paged right to left,
        /// one otherwise, pages that run down too), to see whether the page count falls.
        let shrinking: Bool
    }

    private var taken = Set<Step>()

    /// Sizes `<body>` for `step`. In horizontal writing its height counts the pages it fills, each one
    /// viewport high: the pages of `-webkit-paged-x`, or the columns of a two-page spread, two to a
    /// screen. When vertical-writing pages run down (`FolioReaderCSSBuilder.tieredRules`), its width
    /// counts its tiers, or pages, each a viewport wide, and the search shrinks by one screen. The
    /// column count stays in the CSS (`FolioReaderCSSBuilder.spreadColumnsReference`), so a chapter
    /// that isn't laid out again after a rotation keeps its size in screens.
    static func script(for step: Step) -> String {
        """
        if (folioPagesDown()) {
            document.body.style.width = "calc(\(step.screens - (step.shrinking ? 1 : 0)) * \(FolioReaderCSSBuilder.spreadColumnsReference) * 100vw)"
        } else if (writingMode == 'vertical-rl') {
            document.body.style.width     = "\(step.screens * 100 - (step.shrinking ? 200 : 0))vw"
        } else {
            document.body.style.minHeight = "calc(\(step.screens - (step.shrinking ? 1 : 0)) * \(FolioReaderCSSBuilder.spreadColumnsReference) * 100vh)"
        }
        """
    }

    /// The step after `step`, from the page count measured with it, or nil when the search is over:
    /// the body fills `step.screens` pages, or the next step was taken before. A page count that
    /// doesn't follow the body (pages wider than the screen) would otherwise go round forever.
    mutating func next(after step: Step, totalPages: Int) -> Step? {
        taken.insert(step)
        let screens = max(totalPages, 1)
        let next: Step
        if step.shrinking {
            next = Step(screens: screens, shrinking: totalPages < step.screens)
        } else if totalPages != step.screens {
            next = Step(screens: screens, shrinking: totalPages > step.screens)
        } else {
            return nil
        }
        return taken.contains(next) ? nil : next
    }
}
