//
//  UIScrollViewDelegation.swift
//  FolioReaderKit
//
//  Created by 京太郎 on 2021/9/14.
//  Copyright © 2021 FolioReader. All rights reserved.
//

import UIKit
import WebKit

class ReaderScrollDelegateHandler: NSObject, UIScrollViewDelegate, UICollectionViewDelegate {
    private weak var center: FolioReaderCenter?

    init(center: FolioReaderCenter) {
        self.center = center
    }

    private var readerConfig: FolioReaderConfig {
        return center?.readerConfig ?? FolioReaderConfig()
    }

    private var folioReader: FolioReader {
        return center?.folioReader ?? FolioReader()
    }

    open func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard let center = center else { return }
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        center.invalidatePendingBarReveal()
        center.isScrolling = true
        center.clearRecentlyScrolled()
        center.recentlyScrolled = true
        center.pointNow = scrollView.contentOffset

        if let page = center.currentPage, page.webView?.scrollView === scrollView {
            page.pinnedPosition = nil
        }

        if let currentPage = center.currentPage {
            currentPage.webView?.createMenu(onHighlight: false)
            currentPage.webView?.setMenuVisible(false)
        }

        if center.barHostingNavigationController?.isNavigationBarHidden == false {
            center.hideBars()
        }

        center.scrollScrubber?.scrollViewWillBeginDragging(scrollView)
    }

    open func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let center = center else { return }
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER"); }

        if scrollView.isDragging || scrollView.isDecelerating {
            center.invalidatePendingBarReveal()
        }

        center.scrollScrubber?.scrollViewDidScroll(scrollView)

        let isCollectionScrollView = (scrollView is UICollectionView)
        let scrollType: ScrollType = ((isCollectionScrollView == true) ? .chapter : .page)

        // Update current reading page
        center.updatePageScrollDirection(inScrollView: scrollView, forScrollType: scrollType)
        
        if (isCollectionScrollView == false), let page = center.currentPage, page.layoutAdapting == nil {
            page.updatePages(updateWebViewScrollPosition: false)
            
            center.delegate?.pageItemChanged?(page.currentPage)
        }
    }
    
    open func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard let center = center else { return }
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        center.isScrolling = false
        
        // Perform the page after a short delay as the collection view hasn't completed it's transition if this method is called (the index paths aren't right during fast scrolls).
        DispatchQueue.main.asyncAfter(delay: 0.2, execute: { [weak center] in
            guard let center = center else { return }

            if (scrollView is UICollectionView) {
                guard center.totalPages > 0,
                      let page = center.currentPage
                else {
                    return
                }
                
                page.waitForLayoutFinish {
                    page.updatePageInfo {
                        guard center.currentPageNumber == page.pageNumber else { return }
                        center.delegate?.pageItemChanged?(page.currentPage)
                    }
                }
            } else {
                center.scrollScrubber?.scrollViewDidEndDecelerating(scrollView)
                self.recordPosition(afterScrolling: scrollView)
            }
        })
    }

    /// Records where a page's own scrolling came to rest. Positions were otherwise only recorded when
    /// the screen-page number changed, so in scroll mode the stored one could be up to a screen
    /// behind, and a rotation restored the reader there.
    private func recordPosition(afterScrolling scrollView: UIScrollView) {
        guard let page = center?.currentPage,
              page.webView?.scrollView === scrollView,
              page.layoutAdapting == nil else { return }
        page.getAndRecordScrollPosition()
    }

    open func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard let center = center else { return }
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        if decelerate == false {
            center.isScrolling = false
            if !(scrollView is UICollectionView) {
                recordPosition(afterScrolling: scrollView)
            }
        }

        let timer = Timer(timeInterval:center.recentlyScrolledDelay, target: center, selector: #selector(FolioReaderCenter.clearRecentlyScrolled), userInfo: nil, repeats: false)
        center.recentlyScrolledTimer = timer
        RunLoop.current.add(timer, forMode: RunLoop.Mode.common)
    }

    open func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard let center = center else { return }
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        center.scrollScrubber?.scrollViewDidEndScrollingAnimation(scrollView)
        // An animated programmatic scroll (a page-item turn, the back button) recorded where it
        // started; a rotation then restored the page just left.
        if !(scrollView is UICollectionView) {
            recordPosition(afterScrolling: scrollView)
        }
    }
}

extension FolioReaderCenter {
    func updatePageScrollDirection(inScrollView scrollView: UIScrollView, forScrollType scrollType: ScrollType) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        let scrollViewContentOffsetForDirection = scrollView.contentOffset.forDirection(withConfiguration: self.readerConfig, scrollType: scrollType)
        let pointNowForDirection = pointNow.forDirection(withConfiguration: self.readerConfig, scrollType: scrollType)
        // The movement is either positive or negative. This happens if the page change isn't completed. Toggle to the other scroll direction then.
        let isCurrentlyPositive = (self.pageScrollDirection == .left || self.pageScrollDirection == .up)

        if (scrollViewContentOffsetForDirection < pointNowForDirection) {
            self.pageScrollDirection = .negative(withConfiguration: self.readerConfig, scrollType: scrollType)
        } else if (scrollViewContentOffsetForDirection > pointNowForDirection) {
            self.pageScrollDirection = .positive(withConfiguration: self.readerConfig, scrollType: scrollType)
        } else if (isCurrentlyPositive == true) {
            self.pageScrollDirection = .negative(withConfiguration: self.readerConfig, scrollType: scrollType)
        } else {
            self.pageScrollDirection = .positive(withConfiguration: self.readerConfig, scrollType: scrollType)
        }
    }
    
    @objc func clearRecentlyScrolled() {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        recentlyScrolledTimer?.invalidate()
        recentlyScrolledTimer = nil
        recentlyScrolled = false
    }
}
