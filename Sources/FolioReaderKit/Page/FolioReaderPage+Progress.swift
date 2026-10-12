//
//  FolioReaderPage+Progress.swift
//  FolioReaderKit
//

import UIKit

extension FolioReaderPage {
    func updatePageInfo(completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) {
            FolioLogger.log("ENTER");
        }

        self.webView?.js("getReadingTime(\"\(book.metadata.language)\")") { readingTime in
            self.totalMinutes = Int(readingTime ?? "0") ?? 0
            
            self.updatePageIdOffsets {
                self.updatePages()
                
                defer {
                    completion?()
                }
                guard let readerCenter = self.folioReader.readerCenter,
                      readerCenter.currentPageNumber == self.pageNumber else { return }
                
                readerCenter.scrollScrubber?.setSliderVal()
                readerCenter.pageIndicatorView?.reloadViewWithPage(self.currentPage)
                readerCenter.delegate?.pageDidAppear?(self)
                readerCenter.delegate?.pageItemChanged?(self.currentPage)
            }
        }
    }
    
    func updatePageIdOffsets(completion: (() -> Void)? = nil) {
        let isHorizontal: Bool = self.folioReader.readerConfig?.isDirection(false, true, false) ?? false
        self.webView?.js("getOffsetsOfElementsWithID(\(isHorizontal))") { result in
            defer {
                completion?()
            }
            
            guard let data = result?.data(using: .utf8),
                  let offsets = try? JSONDecoder().decode([String:Int].self, from: data) else { return }
            
            //print("\(#function) \(offsets)")
            self.idOffsets = offsets
        }
    }
    
    func updatePages(updateWebViewScrollPosition: Bool = true) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        guard let readerCenter = self.folioReader.readerCenter, let webView = self.webView else { return }

        // Pages that run down are a web view high: the page frame keeps the status bar and margins.
        let pageSize = pagesDown ? webView.frame.height : self.byWritingMode(
            self.readerConfig.isDirection(readerCenter.pageHeight, readerCenter.pageWidth, readerCenter.pageHeight),
            webView.frame.width
        )
        let contentSize = pagesDown ? webView.scrollView.contentSize.height : self.byWritingMode(
            webView.scrollView.contentSize.forDirection(withConfiguration: self.readerConfig),
            webView.scrollView.contentSize.width
        )
        self.totalPages = ((pageSize != 0) ? Int(ceil(contentSize / pageSize)) : 0)
        
        let pageOffSet = pagesDown ? webView.scrollView.contentOffset.y : self.byWritingMode(
            webView.scrollView.contentOffset.forDirection(withConfiguration: self.readerConfig),
            webView.scrollView.contentOffset.x //+ webView.frame.width
        )
        
        FolioLogger.log("updatePages pageNumber=\(self.pageNumber) totalPages=\(self.totalPages ?? 0) contentSize=\(contentSize) pageSize=\(pageSize)")
        self.currentPage = pageForOffset(pageOffSet, pageHeight: pageSize)
        
        self.updateCurrentChapterName()
        
        guard !(webView.isHidden || layoutAdapting != nil) else { return }
        
        guard updateWebViewScrollPosition else { return }
        getAndRecordScrollPosition()
    }
    
    func pageForOffset(_ offset: CGFloat, pageHeight height: CGFloat) -> Int {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        guard (height != 0) else {
            return 0
        }

        guard let scrollDirection = self.folioReader.readerCenter?.pageScrollDirection, scrollDirection != .none else {
            return Int(ceil(offset / height))+1
        }
        let page = self.byWritingMode(
            self.readerConfig.isDirection(
                Int(ceil(offset / height))+1,
                scrollDirection == .right ? Int(ceil(offset / height))+1 : Int(floor(offset / height))+1,
                Int(ceil(offset / height))+1
            ),
            Int(ceil(offset / height))+1
        )
        return page
    }

    
    func getPageProgress() -> Double {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        guard let readerCenter = self.folioReader.readerCenter,
              let webView = webView else {
            return 0
        }
        
        let pageSize = pagesDown ? webView.frame.height : self.byWritingMode(
            self.readerConfig.isDirection(readerCenter.pageHeight, readerCenter.pageWidth, readerCenter.pageHeight),
            webView.frame.width
        )
        let contentSize = pagesDown ? webView.scrollView.contentSize.height : self.byWritingMode(
            webView.scrollView.contentSize.forDirection(withConfiguration: self.readerConfig),
            webView.scrollView.contentSize.width
        )
        let totalPages = ((pageSize != 0) ? Int(ceil(contentSize / pageSize)) : 0)
        let currentPageItem = currentPage
        
        if totalPages > 0 {
            // Pages that run down count from the start of the chapter, at the top.
            var progress = pagesDown ? Double(currentPageItem - 1) * 100.0 / Double(totalPages) : self.byWritingMode(
                Double(currentPageItem - 1) * 100.0 / Double(totalPages),
                100.0 - Double(currentPageItem) * 100.0 / Double(totalPages)
            )
            
            if progress < 0 { progress = 0 }
            if progress > 100 { progress = 100 }
            
            return progress
        }
        
        return 0
    }
    
    func getBookProgress() -> Double {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }
        
        guard book.spine.size > 0 else { return .zero }
    
        if self.folioReader.structuralStyle == .bundle,
           self.book.bundleRootTableOfContents.isEmpty == false,
           let bookTocIndex = getBundleRootTocIndex(),
           let bookSize = self.book.bundleBookSizes[safe: bookTocIndex] {
            let bookTocSpineIndex = self.book.findPageByResource(self.book.bundleRootTableOfContents[bookTocIndex])
            let bookTocSizeUpto = self.book.spine.spineReferences[bookTocSpineIndex].sizeUpTo
            
            if bookSize > 0 {
                let chapterProgress = 100.0 * Double(book.spine.spineReferences[pageNumber - 1].sizeUpTo - bookTocSizeUpto) / Double(bookSize)
                let pageProgress = getPageProgress()
                
                return chapterProgress + Double(pageProgress) * Double( book.spine.spineReferences[pageNumber - 1].resource.size ?? 0) / Double(bookSize)
            }
        }
    
        let chapterProgress = 100.0 * Double(book.spine.spineReferences[pageNumber - 1].sizeUpTo) / Double(book.spine.size)
        let pageProgress = getPageProgress()
        
        return chapterProgress + Double(pageProgress) * Double( book.spine.spineReferences[pageNumber - 1].resource.size ?? 0) / Double(book.spine.size)
    }
    
    public func getBundleProgress() -> Double {
        guard self.folioReader.structuralStyle == .bundle,
              self.book.spine.size > 0,
              let bookId = self.book.name?.deletingPathExtension else { return .zero }
        
        var bundleProgress = Double.zero
        
        (self.book.bundleRootTableOfContents.startIndex..<self.book.bundleRootTableOfContents.endIndex).forEach { bookTocIndex in
            let bookSize = self.book.bundleBookSizes[bookTocIndex]
            let bookTocSpineIndex = self.book.findPageByResource(self.book.bundleRootTableOfContents[bookTocIndex])
            
            if let position = self.folioReader.delegate?.folioReaderReadPositionProvider?(self.folioReader).folioReaderReadPosition(self.folioReader, bookId: bookId, by: bookTocSpineIndex + 1) {
                bundleProgress += position.bookProgress * Double(bookSize)
            }
        }
        
        bundleProgress /= Double(book.spine.size)
        
        return bundleProgress
    }
}
