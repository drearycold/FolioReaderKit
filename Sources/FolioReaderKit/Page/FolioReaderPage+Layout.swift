//
//  FolioReaderPage+Layout.swift
//  FolioReaderKit
//

import UIKit

extension FolioReaderPage {
    // MARK: Change layout orientation
    func setScrollDirection(_ direction: FolioReaderScrollDirection) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        guard self.folioReader.readerCenter != nil, let webView = webView else {
            readerConfig.applyEffectiveScrollDirection(direction)
            return
        }

        self.layoutAdapting = .scrollDirection

        // Both are measured in the current layout, so the reader config must still have the current
        // direction. The settings applied the new one first, which measured a scrolled page along
        // the paged axis: the position became the chapter heading, and the offset ratio 0.
        self.updatePageOffsetRate()

        // The first text on screen, for the new layout to start from. The offset ratio, the fallback,
        // doesn't carry over between paged and scroll layouts, whose content sizes differ: switching
        // went back about a screen, or to the start of the chapter.
        getWebViewScrollPosition(firstVisibleText: true, onFailure: {
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

writingMode
"""
        ) { writingMode in
            overflowInterval.end()
            if let writingMode = writingMode {
                self.writingMode = writingMode
            }
            // The overflow CSS depends on the writing mode, which is only known after the script above.
            let overflowCSSInterval = FolioSignpost.begin("OverflowCSS", "page \(self.pageNumber)")
            FolioReaderCSSInjector.apply(
                id: FolioReaderCSSInjector.StyleID.overflow,
                css: FolioReaderCSSBuilder.overflowCSS(overflow: webView.cssOverflowProperty, verticalWritingMode: self.writingMode == "vertical-rl"),
                to: webView
            ) {
                overflowCSSInterval.end()
                self.waitForLayout(timeout: bySecond, label: "overflow") {
                    completion?()
                }
            }
        }
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

        let styleState = FolioReaderStyleState(preferences: folioReader.preferences, isVerticalWritingMode: writingMode == "vertical-rl", reserveSafeArea: readerConfig.reserveSafeAreaInsidePageFrame, userFontDescriptors: readerConfig.userFontDescriptors)
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
    
    func updateStyleBackgroundPadding(delay bySecond: Double, tryShrinking: Bool = true, completion: (() -> Void)? = nil) {
        self.layoutAdapting = .finalizing
        
        var minScreenCount = 1
        if self.byWritingMode(self.readerConfig.scrollDirection == .horizontalWithPagedContent, true) {
            minScreenCount = self.totalPages ?? minScreenCount
            if minScreenCount < 1 {
                minScreenCount = 1
            }
        }
        
        // must set width instead of minWidth, otherwise there will be an extra blank page after calling scrollView.setContentOffset
        // could be a bug?
        // and shrinking by 100vw has no effect on totalPages
        let paddingInterval = FolioSignpost.begin("PaddingJS", "page \(pageNumber)")
        self.webView?.js(
            """
            if (writingMode == 'vertical-rl') {
                document.body.style.width     = "\(minScreenCount * 100 - (tryShrinking ? 200 : 0))vw"
            } else {
                document.body.style.minHeight = "\(minScreenCount * 100 - (tryShrinking ? 100 : 0))vh"
            }
            """
        ) { _ in
            paddingInterval.end()
            self.waitForLayout(timeout: bySecond, label: "padding") {
                self.updatePageInfo {
                    FolioLogger.log("updateStyleBackgroundPadding pageNumber=\(self.pageNumber) minScreenCount=\(minScreenCount) totalPages=\(self.totalPages ?? 0) tryShrinking=\(tryShrinking)")
                    if self.byWritingMode(self.readerConfig.scrollDirection == .horizontalWithPagedContent, true) {
                        if tryShrinking {
                            if (self.totalPages ?? 0) < minScreenCount {   //shrinked one page, try again
                                self.updateStyleBackgroundPadding(delay: bySecond, tryShrinking: true, completion: completion)
                            } else {  //stop shrinking
                                self.updateStyleBackgroundPadding(delay: bySecond, tryShrinking: false, completion: completion)
                            }
                        } else {
                            if (self.totalPages ?? 0) > minScreenCount {
                                self.updateStyleBackgroundPadding(delay: bySecond, tryShrinking: true, completion: completion)
                            } else if (self.totalPages ?? 0) < minScreenCount {
                                self.updateStyleBackgroundPadding(delay: bySecond, tryShrinking: false, completion: completion)
                            } else {
                                completion?()
                            }
                        }
                    } else {
                        completion?()
                    }
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
