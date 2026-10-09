//
//  ReaderPaginationEngine.swift
//  FolioReaderKit
//
//  Created by Gemini on 2026/03/21.
//

import UIKit
import FolioEPUBCore

open class ReaderPaginationEngine {
    private weak var center: FolioReaderCenter?

    init(center: FolioReaderCenter) {
        self.center = center
    }

    private var collectionView: UICollectionView? {
        return center?.collectionView
    }

    private var readerConfig: FolioReaderConfig {
        return center?.readerConfig ?? FolioReaderConfig()
    }

    private var book: FRBook {
        return center?.book ?? FRBook()
    }

    private var folioReader: FolioReader {
        return center?.folioReader ?? FolioReader()
    }

    private var totalPages: Int {
        return center?.totalPages ?? 0
    }

    private var currentPageNumber: Int {
        return center?.currentPageNumber ?? 0
    }

    private var nextPageNumber: Int {
        return center?.nextPageNumber ?? 0
    }

    private var previousPageNumber: Int {
        return center?.previousPageNumber ?? 0
    }

    private var pageHeight: CGFloat {
        return center?.pageHeight ?? 0
    }

    private var pageWidth: CGFloat {
        return center?.pageWidth ?? 0
    }

    // MARK: - Pagination methods

    func frameForPage(_ page: Int) -> CGRect {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        return self.readerConfig.isDirection(
            CGRect(x: 0, y: self.pageHeight * CGFloat(page-1), width: self.pageWidth, height: self.pageHeight),
            CGRect(x: self.pageWidth * CGFloat(page-1), y: 0, width: self.pageWidth, height: self.pageHeight),
            CGRect(x: self.pageWidth * CGFloat(page-1), y: 0, width: self.pageWidth, height: self.pageHeight)
        )
    }

    public func changePageWith(page: Int, andFragment fragment: String, animated: Bool = false, completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        if (self.currentPageNumber == page) {
            if let currentPage = center?.currentPage , fragment != "" {
                currentPage.handleAnchor(fragment, offsetInWindow: 0, avoidBeginningAnchors: false, animated: animated)
            }
            completion?()
        } else {
            center?.tempFragment = fragment
            changePageWith(page: page, animated: animated, completion: { () -> Void in
                completion?()
            })
        }
    }

    public func changePageWith(href: String, animated: Bool = false, completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        guard let item = self.book.resources.findByHref(href)?.spineIndices.first else { return }
        let indexPath = IndexPath(row: item, section: 0)
        changePageWith(indexPath: indexPath, animated: animated, completion: { () -> Void in
            completion?()
        })
    }

    public func changePageWith(href: String, andAudioMarkID markID: String) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        if center?.recentlyScrolled == true { return } // if user recently scrolled, do not change pages or scroll the webview
        guard let currentPage = center?.currentPage else { return }

        guard let item = self.book.resources.findByHref(href)?.spineIndices.first else { return }
        let pageUpdateNeeded = item+1 != currentPage.pageNumber
        let indexPath = IndexPath(row: item, section: 0)
        changePageWith(indexPath: indexPath, animated: true) { [self] () -> Void in
            if pageUpdateNeeded {
                self.center?.currentPage?.waitForLayoutFinish {
                    currentPage.audioMarkID(markID)
                }
            } else {
                currentPage.audioMarkID(markID)
            }
        }
    }

    public func changePageWith(indexPath: IndexPath, retryDelaySec: Double = 0.4, animated: Bool = false, completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        guard indexPathIsValid(indexPath) else {
            print("ERROR: Attempt to scroll to invalid index path")
            completion?()
            return
        }
        
        FolioLogger.log("\(indexPath)")
        let frameForPage = self.frameForPage(indexPath.row + 1)
        print("changePageWith frameForPage origin=\(frameForPage.origin)")
        self.collectionView?.setContentOffset(frameForPage.origin, animated: false)
        center?.collectionViewLayout.invalidateLayout()
        self.collectionView?.layoutIfNeeded()
        
        DispatchQueue.main.asyncAfter(delay: retryDelaySec) {
            let indexPaths = self.collectionView?.indexPathsForVisibleItems ?? []
            if indexPaths.contains(indexPath) || retryDelaySec < 0.05 {
                completion?()
            } else {
                self.changePageWith(indexPath: indexPath, retryDelaySec: retryDelaySec - 0.1, animated: animated, completion: completion)
            }
        }
    }
    
    public func changePageWith(href: String, pageItem: Int, animated: Bool = false, completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        changePageWith(href: href, animated: animated) {
            self.changePageItem(to: pageItem)
        }
    }

    public func changePageToNext(_ completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        changePageWith(page: self.nextPageNumber, animated: true) { () -> Void in
            completion?()
        }
    }

    public func changePageToPrevious(_ completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        changePageWith(page: self.previousPageNumber, animated: true) { () -> Void in
            completion?()
        }
    }
    
    public func changePageItemToNext(_ completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        guard
            let cell = center?.currentPage,
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
            cell.pinnedPosition = nil
            cell.scrollPageToOffset(contentOffsetX, animated: true)
        }
        
        completion?()
    }

    func indexPathIsValid(_ indexPath: IndexPath) -> Bool {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        let section = indexPath.section
        let row = indexPath.row
        let lastSectionIndex = (collectionView?.numberOfSections ?? 0) - 1

        if section > lastSectionIndex {
            return false
        }

        guard let collectionView = collectionView else { return false }
        let rowCount = center?.collectionView(collectionView, numberOfItemsInSection: indexPath.section) ?? 0
        return row <= (rowCount - 1)
    }

    public func changePageItemToPrevious(_ completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        guard
            let cell = center?.currentPage,
            let contentOffset = cell.webView?.scrollView.contentOffset else {
                completion?()
                return
        }
        
        let cellSize = cell.frame.size
        let contentOffsetX = contentOffset.x - cellSize.width
        
        if contentOffsetX < 0 {
            changePageToPrevious(completion)
        } else {
            cell.pinnedPosition = nil
            cell.scrollPageToOffset(contentOffsetX, animated: true)
        }
        
        completion?()
    }

    public func changePageItemToLast(animated: Bool = true, _ completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        guard
            let cell = center?.currentPage,
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
        
        cell.pinnedPosition = nil
        cell.scrollPageToOffset(contentOffsetX, animated: animated)
        
        completion?()
    }

    public func changePageItem(to: Int, animated: Bool = true, completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        guard
            let cell = center?.currentPage,
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
            cell.pinnedPosition = nil
        cell.scrollPageToOffset(contentOffsetX, animated: animated)
        }) { (finished: Bool) -> Void in
            cell.updatePageInfo {
                self.center?.delegate?.pageItemChanged?(cell.currentPage)
                completion?()
            }
        }
    }

    public func changePageWith(page: Int, animated: Bool = false, completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        if page > 0 && page-1 < totalPages {
            let indexPath = IndexPath(row: page-1, section: 0)
            changePageWith(indexPath: indexPath, animated: animated, completion: { () -> Void in
                if self.currentPageNumber == page, let completion = completion {
                    self.center?.currentPage?.waitForLayoutFinish(completion: completion)
                }
            })
        }
    }
}
