//
//  Navigation.swift
//  FolioReaderKit
//
//  Created by 京太郎 on 2021/9/14.
//  Copyright © 2021 FolioReader. All rights reserved.
//

import Foundation

extension FolioReaderCenter {
    /* replaced by FolioReaderPage.updatePageInfo and .waitForLayoutFinish
    func updateCurrentPage(_ page: FolioReaderPage? = nil, navigating to: IndexPath? = nil, completion: (() -> Void)? = nil) {
        completion?()
        return;
        
        if readerConfig.debug.contains(.functionTrace) {
            folioLogger("ENTER");
            Thread.callStackSymbols.forEach{print($0)}
        }

        if let page = page {
            currentPage = page
//            self.previousPageNumber = page.pageNumber-1
            self.currentPageNumber = page.pageNumber
        } else {
            let currentIndexPath = getCurrentIndexPath(navigating: to)
            if let to = to, currentIndexPath != to {
                folioLogger("MISS MATCHING INDEX to=\(to) vs current=\(currentIndexPath)")
                return
            }
            currentPage = collectionView.cellForItem(at: currentIndexPath) as? FolioReaderPage

//            self.previousPageNumber = currentIndexPath.row
            self.currentPageNumber = currentIndexPath.row+1
        }

//        self.nextPageNumber = (((self.currentPageNumber + 1) <= totalPages) ? (self.currentPageNumber + 1) : self.currentPageNumber)

        // Set pages
        guard let currentPage = currentPage else {
            completion?()
            return
        }

        scrollScrubber?.setSliderVal()
        currentPage.webView?.js("getReadingTime(\"\(book.metadata.language)\")") { readingTime in
            self.pageIndicatorView?.totalMinutes = Int(readingTime ?? "0")!
            self.pagesForCurrentPage(currentPage)
            self.delegate?.pageDidAppear?(currentPage)
            self.delegate?.pageItemChanged?(self.getCurrentPageItemNumber())
            completion?()
        }
    }
    */
    
    func getCurrentIndexPath() -> IndexPath {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        let contentOffset = self.collectionView.contentOffset
        let indexPaths = collectionView.indexPathsForVisibleItems.compactMap { indexPath -> (indexPath: IndexPath, layoutAttributes: UICollectionViewLayoutAttributes)? in
            guard let layoutAttributes = self.collectionView.layoutAttributesForItem(at: indexPath) else { return nil }
//            folioLogger("indexPath=\(indexPath) offset=\(contentOffset) layoutSize=\(layoutAttributes.size) itemFrame=\(layoutAttributes.frame)")
            return (indexPath: indexPath, layoutAttributes: layoutAttributes)
        }.filter {
            let layoutAttributes = $0.layoutAttributes
            
            guard layoutAttributes.frame.maxX >= contentOffset.x,
                  layoutAttributes.frame.minX <= contentOffset.x + layoutAttributes.size.width
            else { return false }
            
            guard layoutAttributes.frame.maxY >= contentOffset.y,
                  layoutAttributes.frame.minY <= contentOffset.y + layoutAttributes.size.height
            else { return false }
            
            return true
        }
        
//        folioLogger("visibleIndexPath=\(indexPaths)")

        let indexPath = indexPaths.min {
            abs($0.layoutAttributes.frame.minX - contentOffset.x) + abs($0.layoutAttributes.frame.minY - contentOffset.y) <
                abs($1.layoutAttributes.frame.minX - contentOffset.x) + abs($1.layoutAttributes.frame.minY - contentOffset.y)
        }?.indexPath ?? IndexPath(row: 0, section: 0)

//        if indexPaths.count > 1 {
//            let first = indexPaths.first!
//            let last = indexPaths.last!
//
//            switch self.pageScrollDirection {
//            case .up, .left:
//                if first.compare(last) == .orderedAscending {
//                    indexPath = last
//                } else {
//                    indexPath = first
//                }
//            default:
//                if first.compare(last) == .orderedAscending {
//                    indexPath = first
//                } else {
//                    indexPath = last
//                }
//            }
//        } else {
//            indexPath = indexPaths.first ?? IndexPath(row: 0, section: 0)
//        }

        return indexPath
    }

    func frameForPage(_ page: Int) -> CGRect {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        return self.readerConfig.isDirection(
            CGRect(x: 0, y: self.pageHeight * CGFloat(page-1), width: self.pageWidth, height: self.pageHeight),
            CGRect(x: self.pageWidth * CGFloat(page-1), y: 0, width: self.pageWidth, height: self.pageHeight),
            CGRect(x: self.pageWidth * CGFloat(page-1), y: 0, width: self.pageWidth, height: self.pageHeight)
        )
    }

    public func changePageWith(page: Int, andFragment fragment: String, animated: Bool = false, completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        if (self.currentPageNumber == page) {
            if let currentPage = currentPage , fragment != "" {
                currentPage.handleAnchor(fragment, offsetInWindow: 0, avoidBeginningAnchors: false, animated: animated)
            }
            completion?()
        } else {
            tempFragment = fragment
            changePageWith(page: page, animated: animated, completion: { () -> Void in
                completion?()
            })
        }
    }

    public func changePageWith(href: String, animated: Bool = false, completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        guard let item = self.book.resources.findByHref(href)?.spineIndices.first else { return }
        let indexPath = IndexPath(row: item, section: 0)
        changePageWith(indexPath: indexPath, animated: animated, completion: { () -> Void in
//            self.updateCurrentPage(navigating: indexPath) {
                completion?()
//            }
        })
    }

    public func changePageWith(href: String, andAudioMarkID markID: String) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        if recentlyScrolled { return } // if user recently scrolled, do not change pages or scroll the webview
        guard let currentPage = currentPage else { return }

        guard let item = self.book.resources.findByHref(href)?.spineIndices.first else { return }
        let pageUpdateNeeded = item+1 != currentPage.pageNumber
        let indexPath = IndexPath(row: item, section: 0)
        changePageWith(indexPath: indexPath, animated: true) { () -> Void in
            if pageUpdateNeeded {
                self.currentPage?.waitForLayoutFinish {
                    currentPage.audioMarkID(markID)
                }
            } else {
                currentPage.audioMarkID(markID)
            }
        }
    }

    public func changePageWith(indexPath: IndexPath, retryDelaySec: Double = 0.4, animated: Bool = false, completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        guard indexPathIsValid(indexPath) else {
            print("ERROR: Attempt to scroll to invalid index path")
            completion?()
            return
        }
        
        folioLogger("\(indexPath)")
        //self.collectionView.scrollToItem(at: indexPath, at: .direction(withConfiguration: self.readerConfig), animated: false)
        let frameForPage = self.frameForPage(indexPath.row + 1)
        print("changePageWith frameForPage origin=\(frameForPage.origin)")
        self.collectionView.setContentOffset(frameForPage.origin, animated: false)
        self.collectionViewLayout.invalidateLayout()
        self.collectionView.layoutIfNeeded()
        
        delay(retryDelaySec) {
            let indexPaths = self.collectionView.indexPathsForVisibleItems
            if indexPaths.contains(indexPath) || retryDelaySec < 0.05 {
                completion?()
            } else {
                self.changePageWith(indexPath: indexPath, retryDelaySec: retryDelaySec - 0.1, animated: animated, completion: completion)
            }
        }
        
//        // MARK: TEMPFIX first time scrolling will fail mystically
//        UIView.animate(withDuration: animated ? 1.0 : 0.5, delay: 0, options: UIView.AnimationOptions(), animations: { () -> Void in
//            self.collectionView.scrollToItem(at: indexPath, at: .direction(withConfiguration: self.readerConfig), animated: false)
//        }) { (finished: Bool) -> Void in
//            UIView.animate(withDuration: animated ? 1.0 : 0.5, delay: 0, options: UIView.AnimationOptions(), animations: { () -> Void in
//                let frameForPage = self.frameForPage(indexPath.row + 1)
//                print("changePageWith frameForPage origin=\(frameForPage.origin)")
//                self.collectionView.setContentOffset(frameForPage.origin, animated: false)
//            }) { (finished: Bool) -> Void in
//                completion?()
//            }
//        }
    }
    
    public func changePageWith(href: String, pageItem: Int, animated: Bool = false, completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        changePageWith(href: href, animated: animated) {
            self.changePageItem(to: pageItem)
        }
    }

    public func changePageToNext(_ completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        changePageWith(page: self.nextPageNumber, animated: true) { () -> Void in
            completion?()
        }
    }

    public func changePageToPrevious(_ completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        changePageWith(page: self.previousPageNumber, animated: true) { () -> Void in
            completion?()
        }
    }
    
    public func changePageItemToNext(_ completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        // TODO: It was implemented for horizontal orientation.
        // Need check page orientation (v/h) and make correct calc for vertical
        guard
            let cell = collectionView.cellForItem(at: getCurrentIndexPath()) as? FolioReaderPage,
            let contentOffset = cell.webView?.scrollView.contentOffset,
            let contentOffsetXLimit = cell.webView?.scrollView.contentSize.width else {
                completion?()
                return
        }
        
        let cellSize = cell.frame.size
        let contentOffsetX = contentOffset.x + cellSize.width
        
        if contentOffsetX >= contentOffsetXLimit {
            changePageToNext(completion)
        } else {
            cell.scrollPageToOffset(contentOffsetX, animated: true)
        }
        
        completion?()
    }

    func indexPathIsValid(_ indexPath: IndexPath) -> Bool {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        let section = indexPath.section
        let row = indexPath.row
        let lastSectionIndex = numberOfSections(in: collectionView) - 1

        //Make sure the specified section exists
        if section > lastSectionIndex {
            return false
        }

        let rowCount = self.collectionView(collectionView, numberOfItemsInSection: indexPath.section) - 1
        return row <= rowCount
    }

    /*
    public func getCurrentPageItemNumber() -> Int {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        guard let page = currentPage, let webView = page.webView else { return 0 }
        
        let pageSize = page.byWritingMode(
            readerConfig.isDirection(pageHeight, pageWidth, pageHeight),
            webView.frame.width
        )
        let pageOffSet = page.byWritingMode(
            webView.scrollView.contentOffset.forDirection(withConfiguration: readerConfig),
            webView.scrollView.contentOffset.x + webView.frame.width
        )
        let webViewPage = pageForOffset(pageOffSet, pageHeight: pageSize)
        
        return webViewPage
    }
    */
    
    public func changePageItemToPrevious(_ completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        // TODO: It was implemented for horizontal orientation.
        // Need check page orientation (v/h) and make correct calc for vertical
        guard
            let cell = collectionView.cellForItem(at: getCurrentIndexPath()) as? FolioReaderPage,
            let contentOffset = cell.webView?.scrollView.contentOffset else {
                completion?()
                return
        }
        
        let cellSize = cell.frame.size
        let contentOffsetX = contentOffset.x - cellSize.width
        
        if contentOffsetX < 0 {
            changePageToPrevious(completion)
        } else {
            cell.scrollPageToOffset(contentOffsetX, animated: true)
        }
        
        completion?()
    }

    public func changePageItemToLast(animated: Bool = true, _ completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        // TODO: It was implemented for horizontal orientation.
        // Need check page orientation (v/h) and make correct calc for vertical
        guard
            let cell = collectionView.cellForItem(at: getCurrentIndexPath()) as? FolioReaderPage,
            let contentSize = cell.webView?.scrollView.contentSize else {
                completion?()
                return
        }
        
        let cellSize = cell.frame.size
        var contentOffsetX: CGFloat = 0.0
        
        if contentSize.width > 0 && cellSize.width > 0 {
            contentOffsetX = (cellSize.width * (contentSize.width / cellSize.width)) - cellSize.width
        }
        
        if contentOffsetX < 0 {
            contentOffsetX = 0
        }
        
        cell.scrollPageToOffset(contentOffsetX, animated: animated)
        
        completion?()
    }

    public func changePageItem(to: Int, animated: Bool = true, completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        // TODO: It was implemented for horizontal orientation.
        // Need check page orientation (v/h) and make correct calc for vertical
        guard
            let cell = collectionView.cellForItem(at: getCurrentIndexPath()) as? FolioReaderPage,
            let contentSize = cell.webView?.scrollView.contentSize else {
                completion?()
                return
        }
        
        let cellSize = cell.frame.size
        var contentOffsetX: CGFloat = 0.0
        
        if contentSize.width > 0 && cellSize.width > 0 {
            contentOffsetX = (cellSize.width * CGFloat(to)) - cellSize.width
        }
        
        if contentOffsetX > contentSize.width {
            contentOffsetX = contentSize.width - cellSize.width
        }
        
        if contentOffsetX < 0 {
            contentOffsetX = 0
        }
        
        UIView.animate(withDuration: animated ? 0.3 : 0, delay: 0, options: UIView.AnimationOptions(), animations: { () -> Void in
            cell.scrollPageToOffset(contentOffsetX, animated: animated)
        }) { (finished: Bool) -> Void in
            cell.updatePageInfo {
                self.delegate?.pageItemChanged?(cell.currentPage)
                completion?()
            }
        }
    }

    /**
     Find and return the chapter name, first of current page, or last of previous pages
     */
    public func getChapterName(pageNumber: Int) -> FRTocReference? {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        var foundChapterName: FRTocReference?
        
//        func search(_ items: [FRTocReference]) {
//            for item in items {
//                guard foundChapterName == nil else { break }
//
//                if let reference = self.book.spine.spineReferences[safe: (pageNumber - 1)],
//                    let resource = item.resource,
//                    resource == reference.resource,
//                   item.title != nil {
//                    foundChapterName = item
//                } else if let children = item.children, children.isEmpty == false {
//                    search(children)
//                }
//            }
//        }
//        search(self.book.flatTableOfContents)
        
        var findPageNumber = pageNumber
        
        while( findPageNumber > 0 ) {
            if let reference = self.book.spine.spineReferences[safe: findPageNumber - 1],
               let tocReferences = self.book.resourceTocMap[reference.resource],
               tocReferences.isEmpty == false {
                if findPageNumber == pageNumber {
                    foundChapterName = tocReferences.first
                } else {
                    foundChapterName = tocReferences.last
                }
                break
            } else {
                findPageNumber -= 1
            }
        }
        
        return foundChapterName
    }

    /**
     Find and return the chapter name, limit to current page only
     */
    public func getChapterNames(pageNumber: Int) -> [FRTocReference] {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        var foundChapterNames = [FRTocReference]()
        
//        func search(_ items: [FRTocReference]) {
//            for item in items {
//                if let reference = self.book.spine.spineReferences[safe: (pageNumber - 1)],
//                    let resource = item.resource,
//                    resource == reference.resource {
//                    foundChapterNames.append(item)
//                } else if let children = item.children, children.isEmpty == false {
//                    search(children)
//                }
//            }
//        }
//        search(self.book.flatTableOfContents)
        
        if let reference = self.book.spine.spineReferences[safe: pageNumber - 1],
           let tocReferences = self.book.resourceTocMap[reference.resource],
           tocReferences.isEmpty == false {
            foundChapterNames.append(contentsOf: tocReferences)
        }
        
        return foundChapterNames
    }

    // MARK: Public page methods

    /**
     Changes the current page of the reader.

     - parameter page: The target page index. Note: The page index starts at 1 (and not 0).
     - parameter animated: En-/Disables the animation of the page change.
     - parameter completion: A Closure which is called if the page change is completed.
     */
    public func changePageWith(page: Int, animated: Bool = false, completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        if page > 0 && page-1 < totalPages {
            let indexPath = IndexPath(row: page-1, section: 0)
            changePageWith(indexPath: indexPath, animated: animated, completion: { () -> Void in
//                self.updateCurrentPage(navigating: indexPath) {
                if self.currentPageNumber == page, let completion = completion {
                    self.currentPage?.waitForLayoutFinish(completion: completion)
                }
//                }
            })
        }
    }

    // MARK: - Audio Playing

    func audioMark(href: String, fragmentID: String) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        changePageWith(href: href, andAudioMarkID: fragmentID)
    }

}
