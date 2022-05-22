//
//  UIScrollViewDelegation.swift
//  FolioReaderKit
//
//  Created by 京太郎 on 2021/9/14.
//  Copyright © 2021 FolioReader. All rights reserved.
//

import Foundation
import WebKit

extension FolioReaderCenter: UIScrollViewDelegate {
    open func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        self.isScrolling = true
        clearRecentlyScrolled()
        recentlyScrolled = true
        pointNow = scrollView.contentOffset
        
        if (scrollView is UICollectionView) {
            scrollView.isUserInteractionEnabled = false
        }

        if let currentPage = currentPage {
            currentPage.webView?.createMenu(onHighlight: false)
            currentPage.webView?.setMenuVisible(false)
        }

        scrollScrubber?.scrollViewWillBeginDragging(scrollView)
    }

    open func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER"); }

        if (navigationController?.isNavigationBarHidden == false) {
            self.toggleBars()
        }

        scrollScrubber?.scrollViewDidScroll(scrollView)

        let isCollectionScrollView = (scrollView is UICollectionView)
        let scrollType: ScrollType = ((isCollectionScrollView == true) ? .chapter : .page)

        // Update current reading page
        if (isCollectionScrollView == false), let page = currentPage, let webView = page.webView {

            let pageSize = page.byWritingMode(
                self.readerConfig.isDirection(self.pageHeight, self.pageWidth, self.pageHeight),
                webView.frame.width
            )
            let contentOffset = page.byWritingMode(
                webView.scrollView.contentOffset.forDirection(withConfiguration: self.readerConfig),
                webView.scrollView.contentOffset.x
            )
            let contentSize = page.byWritingMode(
                webView.scrollView.contentSize.forDirection(withConfiguration: self.readerConfig),
                webView.scrollView.contentSize.width
            )
            if page.byWritingMode(contentOffset + pageSize <= contentSize, contentOffset >= 0) {

                let webViewPage = pageForOffset(contentOffset, pageHeight: pageSize)

                if (readerConfig.scrollDirection == .horizontalWithVerticalContent) {
                    let currentIndexPathRow = (page.pageNumber - 1)

                    // if the cell reload doesn't save the top position offset
                    if let oldOffSet = self.currentWebViewScrollPositions[currentIndexPathRow], (abs(oldOffSet.y - scrollView.contentOffset.y) > 100) {
                        // Do nothing
                    } else {
                        self.currentWebViewScrollPositions[currentIndexPathRow] = scrollView.contentOffset
                    }
                }

                if (page.currentPage != webViewPage) {
                    page.currentPage = webViewPage
                }
                
                self.delegate?.pageItemChanged?(webViewPage)
            }
        }

        self.updatePageScrollDirection(inScrollView: scrollView, forScrollType: scrollType)
    }
    
    open func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        self.isScrolling = false
        
        if (scrollView is UICollectionView) {
            scrollView.isUserInteractionEnabled = true
        }

        // Perform the page after a short delay as the collection view hasn't completed it's transition if this method is called (the index paths aren't right during fast scrolls).
        delay(0.2, closure: { [weak self] in
            if (self?.readerConfig.scrollDirection == .horizontalWithVerticalContent),
                let cell = ((scrollView.superview as? WKWebView)?.navigationDelegate as? FolioReaderPage) {
                let currentIndexPathRow = cell.pageNumber - 1
                self?.currentWebViewScrollPositions[currentIndexPathRow] = scrollView.contentOffset
            }

            if (scrollView is UICollectionView) {
                guard let instance = self else {
                    return
                }
                
                if instance.totalPages > 0 {
//                    instance.updateCurrentPage()
                    instance.currentPage?.waitForLayoutFinish {
                        instance.currentPage?.updatePageInfo {
                            instance.delegate?.pageItemChanged?(instance.getCurrentPageItemNumber())
                        }
                    }
                }
            } else {
                self?.scrollScrubber?.scrollViewDidEndDecelerating(scrollView)
            }
        })
    }

    open func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        recentlyScrolledTimer = Timer(timeInterval:recentlyScrolledDelay, target: self, selector: #selector(FolioReaderCenter.clearRecentlyScrolled), userInfo: nil, repeats: false)
        RunLoop.current.add(recentlyScrolledTimer, forMode: RunLoop.Mode.common)
    }

    open func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        scrollScrubber?.scrollViewDidEndScrollingAnimation(scrollView)
    }

    func updatePageScrollDirection(inScrollView scrollView: UIScrollView, forScrollType scrollType: ScrollType) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

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
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        if(recentlyScrolledTimer != nil) {
            recentlyScrolledTimer.invalidate()
            recentlyScrolledTimer = nil
        }
        recentlyScrolled = false
    }
}
