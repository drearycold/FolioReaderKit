//
//  Navigation.swift
//  FolioReaderKit
//
//  Created by 京太郎 on 2021/9/14.
//  Copyright © 2021 FolioReader. All rights reserved.
//

import Foundation

extension FolioReaderCenter {
    func updateCurrentPage(_ page: FolioReaderPage? = nil, navigating to: IndexPath? = nil, completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) {
            folioLogger("ENTER");
            Thread.callStackSymbols.forEach{print($0)}
        }

        if let page = page {
            currentPage = page
            self.previousPageNumber = page.pageNumber-1
            self.currentPageNumber = page.pageNumber
        } else {
            let currentIndexPath = getCurrentIndexPath(navigating: to)
            if let to = to, currentIndexPath != to {
                folioLogger("MISS MATCHING INDEX to=\(to) vs current=\(currentIndexPath)")
                return
            }
            currentPage = collectionView.cellForItem(at: currentIndexPath) as? FolioReaderPage

            self.previousPageNumber = currentIndexPath.row
            self.currentPageNumber = currentIndexPath.row+1
        }

        self.nextPageNumber = (((self.currentPageNumber + 1) <= totalPages) ? (self.currentPageNumber + 1) : self.currentPageNumber)

        // Set pages
        guard let currentPage = currentPage else {
            completion?()
            return
        }

        scrollScrubber?.setSliderVal()
        currentPage.webView?.js("getReadingTime()") { readingTime in
            self.pageIndicatorView?.totalMinutes = Int(readingTime ?? "0")!
            self.pagesForCurrentPage(currentPage)
            self.delegate?.pageDidAppear?(currentPage)
            self.delegate?.pageItemChanged?(self.getCurrentPageItemNumber())
            completion?()
        }
    }

    func pagesForCurrentPage(_ page: FolioReaderPage?) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        guard let page = page, let webView = page.webView else { return }

        delay(0.2) {
            let pageSize = self.readerConfig.isDirection(self.pageHeight, self.pageWidth, self.pageHeight)
            let contentSize = page.webView?.scrollView.contentSize.forDirection(withConfiguration: self.readerConfig) ?? 0
            self.pageIndicatorView?.totalPages = ((pageSize != 0) ? Int(ceil(contentSize / pageSize)) : 0)
            if self.readerConfig.scrollDirection == .horizontal {
                var totalPages = self.pageIndicatorView?.totalPages ?? 1
                if totalPages < 1 {
                    totalPages = 1
                }
                page.webView?.js(
                    """
                    document.body.style.minHeight = "\(totalPages * 100)vh"
                    """
                )
            }

            let pageOffSet = self.readerConfig.isDirection(webView.scrollView.contentOffset.x, webView.scrollView.contentOffset.x, webView.scrollView.contentOffset.y)
            let webViewPage = self.pageForOffset(pageOffSet, pageHeight: pageSize)

            self.pageIndicatorView?.currentPage = webViewPage
        }
    }

    func pageForOffset(_ offset: CGFloat, pageHeight height: CGFloat) -> Int {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        guard (height != 0) else {
            return 0
        }

        let page = Int(ceil(offset / height))+1
        return page
    }

    func getCurrentIndexPath(navigating to: IndexPath?) -> IndexPath {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        let contentOffset = self.collectionView.contentOffset
        let indexPaths = collectionView.indexPathsForVisibleItems.filter {
            guard let layoutAttributes = self.collectionView.layoutAttributesForItem(at: $0) else { return false }
            
            folioLogger("offset=\(contentOffset) layoutSize=\(layoutAttributes.size) itemFrame=\(layoutAttributes.frame)")
            //for horizontal
            
            guard layoutAttributes.frame.maxX >= contentOffset.x,
                  layoutAttributes.frame.minX <= contentOffset.x + layoutAttributes.size.width
            else { return false }
            
            guard layoutAttributes.frame.maxY >= contentOffset.y,
                  layoutAttributes.frame.minY <= contentOffset.y + layoutAttributes.size.height
            else { return false }
            
            return true
        }
        
        folioLogger("\(indexPaths)")

        if let to = to, indexPaths.contains(to) {
            return to
        }
        var indexPath = IndexPath()

        if indexPaths.count > 1 {
            let first = indexPaths.first!
            let last = indexPaths.last!

            switch self.pageScrollDirection {
            case .up, .left:
                if first.compare(last) == .orderedAscending {
                    indexPath = last
                } else {
                    indexPath = first
                }
            default:
                if first.compare(last) == .orderedAscending {
                    indexPath = first
                } else {
                    indexPath = last
                }
            }
        } else {
            indexPath = indexPaths.first ?? IndexPath(row: 0, section: 0)
        }

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

    open func changePageWith(page: Int, andFragment fragment: String, animated: Bool = false, completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        if (self.currentPageNumber == page) {
            if let currentPage = currentPage , fragment != "" {
                currentPage.handleAnchor(fragment, offsetInWindow: 0, avoidBeginningAnchors: true, animated: animated)
            }
            completion?()
        } else {
            tempFragment = fragment
            changePageWith(page: page, animated: animated, completion: { () -> Void in
                completion?()
            })
        }
    }

    open func changePageWith(href: String, animated: Bool = false, completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        let item = findPageByHref(href)
        let indexPath = IndexPath(row: item, section: 0)
        changePageWith(indexPath: indexPath, animated: animated, completion: { () -> Void in
            self.updateCurrentPage(navigating: indexPath) {
                completion?()
            }
        })
    }

    open func changePageWith(href: String, andAudioMarkID markID: String) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        if recentlyScrolled { return } // if user recently scrolled, do not change pages or scroll the webview
        guard let currentPage = currentPage else { return }

        let item = findPageByHref(href)
        let pageUpdateNeeded = item+1 != currentPage.pageNumber
        let indexPath = IndexPath(row: item, section: 0)
        changePageWith(indexPath: indexPath, animated: true) { () -> Void in
            if pageUpdateNeeded {
                self.updateCurrentPage(navigating: indexPath) {
                    currentPage.audioMarkID(markID)
                }
            } else {
                currentPage.audioMarkID(markID)
            }
        }
    }

    open func changePageWith(indexPath: IndexPath, animated: Bool = false, completion: (() -> Void)? = nil) {
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
        
        delay(0.4) {
            let indexPaths = self.collectionView.indexPathsForVisibleItems
            if indexPaths.contains(indexPath) {
                completion?()
            } else {
                self.changePageWith(indexPath: indexPath, animated: animated, completion: completion)
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
    
    open func changePageWith(href: String, pageItem: Int, animated: Bool = false, completion: (() -> Void)? = nil) {
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
            let cell = collectionView.cellForItem(at: getCurrentIndexPath(navigating: nil)) as? FolioReaderPage,
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

    
    
    public func getCurrentPageItemNumber() -> Int {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        guard let page = currentPage, let webView = page.webView else { return 0 }
        
        let pageSize = readerConfig.isDirection(pageHeight, pageWidth, pageHeight)
        let pageOffSet = readerConfig.isDirection(webView.scrollView.contentOffset.y, webView.scrollView.contentOffset.x, webView.scrollView.contentOffset.y)
        let webViewPage = pageForOffset(pageOffSet, pageHeight: pageSize)
        
        return webViewPage
    }
    
    public func getCurrentPageProgress() -> Double {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        guard let page = currentPage else { return 0 }
        
        let pageSize = self.readerConfig.isDirection(pageHeight, self.pageWidth, pageHeight)
        let contentSize = page.webView?.scrollView.contentSize.forDirection(withConfiguration: self.readerConfig) ?? 0
        let totalPages = ((pageSize != 0) ? Int(ceil(contentSize / pageSize)) : 0)
        let currentPageItem = getCurrentPageItemNumber()
        
        if totalPages > 0 {
            var progress = Double(currentPageItem - 1) * 100.0 / Double(totalPages)
            
            if progress < 0 { progress = 0 }
            if progress > 100 { progress = 100 }
            
            return progress
        }
        
        return 0
    }

    public func changePageItemToPrevious(_ completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        // TODO: It was implemented for horizontal orientation.
        // Need check page orientation (v/h) and make correct calc for vertical
        guard
            let cell = collectionView.cellForItem(at: getCurrentIndexPath(navigating: nil)) as? FolioReaderPage,
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
            let cell = collectionView.cellForItem(at: getCurrentIndexPath(navigating: nil)) as? FolioReaderPage,
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
            let cell = collectionView.cellForItem(at: getCurrentIndexPath(navigating: nil)) as? FolioReaderPage,
            let contentSize = cell.webView?.scrollView.contentSize else {
                delegate?.pageItemChanged?(getCurrentPageItemNumber())
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
            self.updateCurrentPage {
                completion?()
            }
        }
    }

    /**
     Find a page by FRTocReference.
     */
    public func findPageByResource(_ reference: FRTocReference) -> Int {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        var count = 0
        for item in self.book.spine.spineReferences {
            if let resource = reference.resource, item.resource == resource {
                return count
            }
            count += 1
        }
        return count
    }

    /**
     Find a page by href.
     */
    public func findPageByHref(_ href: String) -> Int {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        var count = 0
        for item in self.book.spine.spineReferences {
            if item.resource.href == href {
                return count
            }
            count += 1
        }
        return count
    }

    /**
     Find and return the current chapter resource.
     */
    public func getCurrentChapter() -> FRResource? {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        var foundResource: FRResource?

        func search(_ items: [FRTocReference]) {
            for item in items {
                guard foundResource == nil else { break }

                if let reference = book.spine.spineReferences[safe: (currentPageNumber - 1)], let resource = item.resource, resource == reference.resource {
                    foundResource = resource
                    break
                } else if let children = item.children, children.isEmpty == false {
                    search(children)
                }
            }
        }
        search(book.flatTableOfContents)

        return foundResource
    }

    /**
     Return the current chapter progress based on current chapter and total of chapters.
     */
    public func getCurrentChapterProgress() -> Double {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }
        
        guard book.spine.size > 0 else { return 0 }
        guard currentPageNumber > 0 else { return 0 }
        
        let total = book.spine.size
        let current = book.spine.spineReferences[currentPageNumber - 1].sizeUpTo
        
        return 100.0 * Double(current) / Double(total)
    }

    public func getBookProgress() -> Double {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }
        
        guard book.spine.size > 0 else { return 0 }
        
        let chapterProgress = getCurrentChapterProgress()
        let pageProgress = getCurrentPageProgress()
        
        return chapterProgress + Double(pageProgress) * Double( book.spine.spineReferences[currentPageNumber - 1].resource.size ?? 0) / Double(book.spine.size)
    }
    
    /**
     Find and return the current chapter name.
     */
    public func getCurrentChapterName() -> String? {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        var foundChapterName: String?
        
        func search(_ items: [FRTocReference]) {
            for item in items {
                guard foundChapterName == nil else { break }
                
                if let reference = self.book.spine.spineReferences[safe: (self.currentPageNumber - 1)],
                    let resource = item.resource,
                    resource == reference.resource,
                    let title = item.title {
                    foundChapterName = title
                } else if let children = item.children, children.isEmpty == false {
                    search(children)
                }
            }
        }
        search(self.book.flatTableOfContents)
        
        return foundChapterName
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
                self.updateCurrentPage(navigating: indexPath) {
                    completion?()
                }
            })
        }
    }

    // MARK: - Audio Playing

    func audioMark(href: String, fragmentID: String) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        changePageWith(href: href, andAudioMarkID: fragmentID)
    }

}
