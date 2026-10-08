//
//  FolioReaderPage+Scroll.swift
//  FolioReaderKit
//

import UIKit

extension FolioReaderPage {
    /// Get internal page offset before layout change.
    /// Represent upper-left point regardless of layout
    public func updatePageOffsetRate() {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        guard let webView = self.webView else { return }

        let pageScrollView = webView.scrollView
        let contentSize = byWritingMode(
            pageScrollView.contentSize.forDirection(withConfiguration: self.readerConfig),
            pageScrollView.contentSize.width
        )
        let contentOffset = byWritingMode(
            pageScrollView.contentOffset.forDirection(withConfiguration: self.readerConfig),
            pageScrollView.contentOffset.x
        )
        self.pageOffsetRate = (contentSize != 0 ? (contentOffset / contentSize) : 0)
    }

    public func updateScrollPosition(delay bySecond: Double = 0.1, completion: (() -> Void)?) {
        // After rotation fix internal page offset
        if self.pageOffsetRate > 0 {
            DispatchQueue.main.asyncAfter(delay: bySecond) {
                self.scrollWebViewByPageOffsetRate()
                self.updatePageOffsetRate()
                completion?()
            }
        } else {
            completion?()
        }
    }
    
    public func scrollWebViewByPosition(pageOffset: CGFloat, pageProgress: Double, animated: Bool = true, completion: (() -> Void)? = nil) {
        var pageOffset = pageOffset
        let pageProgress = pageProgress
        
        let fileSize = self.book.spine.spineReferences[safe: self.pageNumber - 1]?.resource.size ?? 102400
        let delaySec = 0.2 + Double(fileSize / 51200) * (self.readerConfig.scrollDirection == .horizontalWithPagedContent ? 0.25 : 0.1)
        DispatchQueue.main.asyncAfter(delay: delaySec) {
            guard let webView = self.webView,
                  let readerCenter = self.folioReader.readerCenter else {
                completion?()
                return
            }
            
            let contentSize = webView.scrollView.contentSize
            let webViewFrameSize = webView.frame.size
            
            var pageOffsetByProgress = self.byWritingMode(
                contentSize.forDirection(withConfiguration: self.readerConfig) * pageProgress,
                contentSize.width * (100 - pageProgress - webViewFrameSize.width * 100 / contentSize.width)) / 100
            if pageOffset < pageOffsetByProgress * 0.95 || pageOffset > pageOffsetByProgress * 1.05 {
                if self.byWritingMode(self.readerConfig.scrollDirection == .horizontalWithPagedContent, true) {
                    let pageInPage = self.byWritingMode(
                        floor( pageOffsetByProgress / webViewFrameSize.width ),
                        max(floor( (contentSize.width - pageOffsetByProgress) / webViewFrameSize.width), 1)
                    )
                    pageOffsetByProgress = self.byWritingMode(pageInPage * webViewFrameSize.width, contentSize.width - pageInPage * webViewFrameSize.width)
                }
                pageOffset = pageOffsetByProgress - self.byWritingMode(
                    self.readerConfig.isDirection(readerCenter.pageHeight / 2, readerCenter.pageWidth / 2, readerCenter.pageHeight / 2),
                    webViewFrameSize.width / 2
                )
            }
            if pageOffset < 0 {
                pageOffset = 0
            }
            self.pageOffsetRate = pageOffset / self.byWritingMode(contentSize.forDirection(withConfiguration: self.readerConfig), contentSize.width)
            self.scrollWebViewByPageOffsetRate(animated: animated) {
                DispatchQueue.main.asyncAfter(delay: 0.5) {
                    self.getWebViewScrollPosition { position in
                        readerCenter.currentWebViewScrollPositions[self.pageNumber - 1] = position
                        completion?()
                    }
                }
            }
        }
    }
    
    public func scrollWebViewByPageOffsetRate(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard let webViewFrameSize = webView?.frame.size,
              webViewFrameSize.width > 0, webViewFrameSize.height > 0,
              let contentSize = webView?.scrollView.contentSize else { return }
        
        var pageOffset = byWritingMode(
            contentSize.forDirection(withConfiguration: self.readerConfig),
            contentSize.width
        ) * self.pageOffsetRate
        
        // Fix the offset for paged scroll
        if byWritingMode(self.readerConfig.scrollDirection == .horizontalWithPagedContent, true) {
            let page = byWritingMode(
                floor( pageOffset / webViewFrameSize.width ),
                max(floor( (contentSize.width - pageOffset) / webViewFrameSize.width), 1)
            )
            pageOffset = byWritingMode(page * webViewFrameSize.width, contentSize.width - page * webViewFrameSize.width)
        }
        
        scrollPageToOffset(pageOffset, animated: animated, retry: 0, completion: completion)
    }
    
    public func setScrollViewContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        FolioLogger.log("pageNumber=\(pageNumber) contentOffset=\(contentOffset)")
        webView?.scrollView.setContentOffset(contentOffset, animated: animated)
        getAndRecordScrollPosition()
    }

    /**
     Scrolls the page to a given offset

     - parameter offset:   The offset to scroll
     - parameter animated: Enable or not scrolling animation
     */
    /// Restores `position` with `handleAnchor`, then keeps it as the recorded position (`pinnedPosition`).
    func restorePinned(_ position: FolioReaderReadPosition, completion: (() -> Void)? = nil) {
        handleAnchor(position.cfi, offsetInWindow: 0, avoidBeginningAnchors: false, animated: false, flashTarget: false) {
            self.pinnedPosition = position
            self.folioReader.readerCenter?.currentWebViewScrollPositions[self.pageNumber - 1] = position
            completion?()
        }
    }

    public func scrollPageToOffset(_ offset: CGFloat, animated: Bool, retry: Int = 5, completion: (() -> Void)? = nil) {
        guard let webView = webView else {
            return
        }

        let pageOffsetPoint = byWritingMode(
            self.readerConfig.isDirection(CGPoint(x: 0, y: offset), CGPoint(x: offset, y: 0), CGPoint(x: 0, y: offset)),
            CGPoint(x: offset, y: 0)
        )
        setScrollViewContentOffset(pageOffsetPoint, animated: animated)
        
        if retry > 0 {
            DispatchQueue.main.asyncAfter(delay: 0.1 * Double(retry)) {
                if pageOffsetPoint != webView.scrollView.contentOffset {
                    self.scrollPageToOffset(offset, animated: animated, retry: retry - 1, completion: completion)
                } else {
                    completion?()
                }
            }
        } else {
            completion?()
        }
    }

    /// Shows the start of the chapter. Vertical writing reads right to left whatever the scroll
    /// direction, so its start is the right end of the content; a content offset of 0, which a
    /// `.vertical` direction gave it, is the end of the chapter.
    func scrollPageToChapterStart() {
        guard let webView = webView else { return }
        if writingMode == "vertical-rl" {
            let start = Self.verticalWritingContentOffset(fromStart: 0, contentWidth: webView.scrollView.contentSize.width, viewWidth: webView.frame.width)
            setScrollViewContentOffset(CGPoint(x: start, y: 0), animated: false)
        } else if folioReader.needsRTLChange {
            scrollPageToBottom()
        } else {
            scrollPageToOffset(.zero, animated: false, retry: 0)
        }
    }

    /**
     Scrolls the page to bottom
     */
    public func scrollPageToBottom() {
        guard let webView = webView else { return }
        let bottomOffset = self.readerConfig.isDirection(
            CGPoint(x: 0, y: webView.scrollView.contentSize.height - webView.scrollView.bounds.height),
            CGPoint(x: webView.scrollView.contentSize.width - webView.scrollView.bounds.width, y: 0),
            CGPoint(x: webView.scrollView.contentSize.width - webView.scrollView.bounds.width, y: 0)
        )

        if bottomOffset.forDirection(withConfiguration: self.readerConfig) >= 0 {
            DispatchQueue.main.async {
                self.setScrollViewContentOffset(bottomOffset, animated: false)
            }
        }
    }

    func getAndRecordScrollPosition() {
        guard pinnedPosition == nil else { return }
        getWebViewScrollPosition { position in
            //prevent overwriting last known good cfi
            if self.layoutAdapting != nil || self.pinnedPosition != nil {
                return
            }
            
            let badCFI = "epubcfi(/\((self.pageNumber ?? 1) * 2)/2)"
            if position.cfi == badCFI,
               let oldPosition = self.folioReader.readerCenter?.currentWebViewScrollPositions[self.pageNumber - 1],
               oldPosition.cfi != badCFI {
                return
            }
            
            self.folioReader.readerCenter?.currentWebViewScrollPositions[self.pageNumber - 1] = position
            
            //prevent invisible pages updating read positions
            guard self.pageNumber == self.folioReader.readerCenter?.currentPageNumber else { return }
            
            if let bookId = self.folioReader.readerCenter?.book.name?.deletingPathExtension {
                self.folioReader.save(readPosition: position, for: bookId)
            }
        }
    }
    
    /// Reads the JSON of `getVisibleCFI` / `getVisibleMiddleCFI`: the partial CFI of the character
    /// offset if there is one, else of the element, with its snippet.
    static func recordedPosition(fromVisibleCFIJSON json: String?) -> (cfi: String, snippet: String, message: String) {
        guard let json = json,
              let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            return ("", "", "json fail")
        }
        let message = object["message"] as? String ?? "Missing message in json"
        if let offsetComponent = object["offsetComponent"] as? String,
           let offsetSnippet = object["offsetSnippet"] as? String,
           offsetComponent.isEmpty == false {
            return (offsetComponent, offsetSnippet, message)
        }
        // The snippet only labels the position; without one the element CFI still counts.
        return (object["cfi"] as? String ?? "", object["snippet"] as? String ?? "", message)
    }

    /// - Parameter firstVisibleText: record the first visible text in paged mode too, as the start of a
    ///   different layout (a scroll-direction switch); otherwise paged mode records the middle of the page.
    /// - Parameter onFailure: called instead of `completion` when the page couldn't be measured: its
    ///   web content process died, so the script returned nothing. Its position used to come out as the
    ///   start of the chapter, which was then saved.
    func getWebViewScrollPosition(firstVisibleText: Bool = false, onFailure: (() -> Void)? = nil, completion: ((_ position: FolioReaderReadPosition) -> Void)? = nil) {
        guard let webView = webView, !needsReload else {
            onFailure?()
            return
        }

        let isHorizontal: Bool = self.byWritingMode(
            self.folioReader.readerConfig?.isDirection(false, true, false),
            true) ?? false
        // Paged mode records the middle of the page, which survives a relayout; see getVisibleMiddleCFI.
        let locate = readerConfig.scrollDirection == .horizontalWithPagedContent && !firstVisibleText ? "getVisibleMiddleCFI" : "getVisibleCFI"
        webView.js("\(locate)(\(isHorizontal))") { jsonString in
            guard let jsonString = jsonString, (try? JSONSerialization.jsonObject(with: Data(jsonString.utf8))) != nil else {
                onFailure?()
                return
            }
            let (cfi, snippet, message) = Self.recordedPosition(fromVisibleCFIJSON: jsonString)
            #if DEBUG
            if cfi.isEmpty, self.pageNumber > 1 {
                let alertController = UIAlertController(title: "Empty CFI pageNumber=\(self.pageNumber ?? 0)", message: message, preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { action in
                    
                }))
                self.folioReader.readerCenter?.present(alertController, animated: false, completion: {
                    
                })
            }
            #endif
            
            let structuralStyle = self.folioReader.structuralStyle
            let structuralTrackingTocLevel = self.folioReader.structuralTrackingTocLevel
            let structuralRootPageNumber = { () -> Int in
                switch structuralStyle {
                case .atom:
                    return 0
                case .bundle:
                    let tocRefs = self.getChapterTocReferences(for: webView.scrollView.contentOffset, by: webView.frame.size)
                    if let rootTocRef = tocRefs.filter({ $0.level == structuralTrackingTocLevel.rawValue - 1 }).first {
                        return self.book.findPageByResource(rootTocRef) + 1
                    }
                    return 0
                case .topic:
                    return self.pageNumber
                }
            }()
            
            let position = FolioReaderReadPosition(
                deviceId: UIDevice.current.name,
                structuralStyle: structuralStyle,
                positionTrackingStyle: structuralTrackingTocLevel,
                structuralRootPageNumber: structuralRootPageNumber,
                pageNumber: self.pageNumber,
                cfi: "epubcfi(/\((self.pageNumber ?? 1) * 2)/2\(cfi))"    //partial cfi to full cfi
            )
            position.snippet = .init(snippet.prefix(64))
            position.maxPage = self.readerContainer?.book.spine.spineReferences.count ?? 1
            position.pageOffset = webView.scrollView.contentOffset
            position.chapterProgress = self.getPageProgress()
            position.chapterName = self.currentChapterName ?? "Untitled Chapter"
            position.bookProgress = self.getBookProgress()
            position.bookName = self.book.title ?? self.book.name ?? "Unnamed Book"
            if self.folioReader.structuralStyle == .bundle,
               let bookRootTocIndex = self.getBundleRootTocIndex(),
               let bookRootToc = self.book.bundleRootTableOfContents[safe: bookRootTocIndex] {
                position.bookName = bookRootToc.title
            }
            
            DispatchQueue.global().async { [weak self] in
                guard let self = self else { return }
                position.bundleProgress = self.getBundleProgress()
                
                DispatchQueue.main.async {
                    completion?(position)
                }
            }
        }
    }
}
