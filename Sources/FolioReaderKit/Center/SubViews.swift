//
//  SubViews.swift
//  FolioReaderKit
//
//  Created by 京太郎 on 2021/9/14.
//  Copyright © 2021 FolioReader. All rights reserved.
//

import Foundation
import UIKit

extension FolioReaderCenter {
    func isScrollMotionActive() -> Bool {
        if let collectionView = collectionView,
           collectionView.isDragging || collectionView.isDecelerating {
            return true
        }

        if let webScrollView = currentPage?.webView?.scrollView,
           webScrollView.isDragging || webScrollView.isDecelerating {
            return true
        }

        return isScrolling
    }

    func invalidatePendingBarReveal() {
        pendingBarRevealToken &+= 1
        pendingBarRevealWorkItem?.cancel()
        pendingBarRevealWorkItem = nil
    }

    func requestBarReveal(after delay: TimeInterval = 0.4, forPageNumber pageNumber: Int? = nil) {
        guard readerConfig.hideBars == false else { return }

        invalidatePendingBarReveal()
        let token = pendingBarRevealToken
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard self.canRevealBars(forToken: token, pageNumber: pageNumber) else { return }
            self.showBars()
        }

        pendingBarRevealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func canRevealBars(forToken token: UInt, pageNumber: Int?) -> Bool {
        guard readerConfig.hideBars == false else { return false }
        guard token == pendingBarRevealToken else { return false }
        guard barHostingNavigationController?.isNavigationBarHidden == true else { return false }
        guard isScrollMotionActive() == false else { return false }

        if let pageNumber = pageNumber, currentPage?.pageNumber != pageNumber {
            return false
        }

        if currentPage?.menuIsVisible == true {
            return false
        }

        return true
    }

    func updateSubviewFrames() {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        var collectionViewFrame = self.frameForCollectionView(outerBounds: screenBounds)
        collectionViewFrame = collectionViewFrame.insetBy(dx: tempCollectionViewInset, dy: tempCollectionViewInset)
        pageWidth = collectionViewFrame.width
        pageHeight = collectionViewFrame.height
//        let itemSize = CGSize(
//            width: collectionViewFrame.size.width,
//            height: collectionViewFrame.size.height)
//        self.collectionViewLayout.itemSize = itemSize
        self.collectionView.frame = collectionViewFrame

        self.pageIndicatorView?.frame = self.frameForPageIndicatorView(outerBounds: screenBounds)
        self.scrollScrubber?.frame = self.frameForScrollScrubber(outerBounds: screenBounds)
        
        self.collectionView.setContentOffset(
            self.readerConfig.isDirection(
                CGPoint(x: 0, y: CGFloat(self.currentPageNumber-1) * pageHeight),
                CGPoint(x: CGFloat(self.currentPageNumber-1) * pageWidth, y: 0),
                CGPoint(x: CGFloat(self.currentPageNumber-1) * pageWidth, y: 0))
            ,
            animated: false
        )
        self.collectionViewLayout.invalidateLayout()
    }

    func frameForPageIndicatorView(outerBounds: CGRect) -> CGRect {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        let safeAreaBottom = view.safeAreaInsets.bottom
        
        #if DEBUG
        let extraDebugHeight: CGFloat = 30
        #else
        let extraDebugHeight: CGFloat = 0
        #endif

        if safeAreaBottom > 0 {
            pageIndicatorHeight = safeAreaBottom + extraDebugHeight
        } else {
            pageIndicatorHeight = 40 + extraDebugHeight
        }
        
        let fullHeight = outerBounds.size.height + safeAreaBottom
        return CGRect(x: 0, y: fullHeight - pageIndicatorHeight, width: outerBounds.size.width, height: pageIndicatorHeight)
    }

    func frameForScrollScrubber(outerBounds: CGRect) -> CGRect {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        guard let currentPage = currentPage else { return .zero }
        
        let navBarHeight = self.folioReader.readerCenter?.navigationController?.navigationBar.frame.size.height ?? CGFloat(0)
        let topComponentTotal = self.readerConfig.hideBars ? 0 : navBarHeight
        let bottomComponentTotal = self.readerConfig.hidePageIndicator ? 0 : self.folioReader.readerCenter?.pageIndicatorHeight ?? CGFloat(0)
        
        let scrubberYforHorizontal: CGFloat = (self.readerConfig.hideBars == true ? 50 : 74)
        let scrubberYforVertical: CGFloat = self.pageHeight
        
        return currentPage.byWritingMode(
            CGRect(x: self.pageWidth + 10, y: scrubberYforHorizontal, width: 40, height: (self.pageHeight - 70 - topComponentTotal - bottomComponentTotal)),
            CGRect(x: self.pageWidth - 40, y: scrubberYforVertical, width: self.pageWidth - 100, height: 40)
        )
    }

    func frameForCollectionView(outerBounds: CGRect) -> CGRect {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        var bounds = CGRect(x: 0, y: 0, width: outerBounds.size.width, height: outerBounds.size.height)
        bounds.size.height = bounds.size.height + view.safeAreaInsets.bottom
        return bounds
    }
    
    func getScreenBounds() -> CGRect {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        var bounds = view.frame
        
        if readerConfig.debug.contains(.viewTransition) {
            print("getScreenBounds view.frame=\(bounds) view.safeAreaInsets=\(view.safeAreaInsets)")
        }
        bounds.size.height = bounds.size.height - view.safeAreaInsets.bottom
        
        if readerConfig.debug.contains(.borderHighlight) {
            let orientation = self.view.window?.windowScene?.interfaceOrientation ?? .portrait
            print("getScreenBounds \(bounds) \(orientation.rawValue)")
        }
        
        return bounds
    }
    
    func configureNavBar() {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        let navBackground = folioReader.preferences.navBackgroundColor(withConfiguration: readerConfig)
        let tintColor = readerConfig.tintColor
        let navText = folioReader.preferences.navTextColor()
        let font = UIFont(name: "Avenir-Light", size: 17) ?? .systemFont(ofSize: 17)
        setTranslucentNavigation(color: navBackground, tintColor: tintColor, titleColor: navText, andFont: font)
    }

    func configureNavBarButtons() {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }


        let navText = folioReader.preferences.navTextColor()
        let shareIcon = UIImage(readerImageNamed: "icon-navbar-share")?.imageTintColor(navText)?.withRenderingMode(.alwaysOriginal)
        let audioIcon = UIImage(readerImageNamed: "icon-navbar-tts")?.imageTintColor(navText)?.withRenderingMode(.alwaysOriginal) //man-speech-icon
        let closeIcon = UIImage(readerImageNamed: "icon-navbar-close")?.imageTintColor(navText)?.withRenderingMode(.alwaysOriginal)
        let tocIcon = UIImage(readerImageNamed: "icon-navbar-toc")?.imageTintColor(navText)?.withRenderingMode(.alwaysOriginal)
        let fontIcon = UIImage(readerImageNamed: "icon-navbar-font")?.imageTintColor(navText)?.withRenderingMode(.alwaysOriginal)
        let logoIcon = UIImage(readerImageNamed: "icon-button-back")?.imageTintColor(navText)?.withRenderingMode(.alwaysOriginal)
        let bookmarkIcon = UIImage(readerImageNamed: "icon-navbar-bookmark")?.imageTintColor(navText)?.withRenderingMode(.alwaysOriginal)

        let toc = UIBarButtonItem(image: tocIcon, style: .plain, target: self, action:#selector(presentChapterList(_:)))
        let bookmark = UIBarButtonItem(image: bookmarkIcon, style: .plain, target: self, action: #selector(presentBookmarkList(_:)))

        var leftBarIcons = [UIBarButtonItem]()
        if readerConfig.showCloseButton {
            leftBarIcons.append(UIBarButtonItem(image: closeIcon, style: .plain, target: self, action: #selector(closeReader(_:))))
        }
        leftBarIcons.append(contentsOf: [toc, bookmark])

        navigationItem.leftBarButtonItems = leftBarIcons

        var rightBarIcons = [UIBarButtonItem]()

        if (self.readerConfig.allowSharing == true) {
            rightBarIcons.append(UIBarButtonItem(image: shareIcon, style: .plain, target: self, action:#selector(shareChapter(_:))))
        }

        if self.book.hasAudio || self.readerConfig.enableTTS {
            rightBarIcons.append(UIBarButtonItem(image: audioIcon, style: .plain, target: self, action:#selector(presentPlayerMenu(_:))))
        }

        let font = UIBarButtonItem(image: fontIcon, style: .plain, target: self, action: #selector(presentFontsMenu))
        let lrp = UIBarButtonItem(image: logoIcon, style: .plain, target: self, action: #selector(logoButtonAction(_:)))
        lrp.isEnabled = false

        rightBarIcons.append(contentsOf: [font, lrp])
        navigationItem.rightBarButtonItems = rightBarIcons
        
        if (self.readerConfig.displayTitle) {
            navigationItem.title = book.title
        }
        
    }

    @objc func closeReader(_ sender: UIBarButtonItem) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        dismiss()
        folioReader.close()
    }
    
    @objc func logoButtonAction(_ sender: UIBarButtonItem) {
        print("\(#function) \(self.navigateWebViewScrollPositions)")
        
        guard let position = self.navigateWebViewScrollPositions.popLast() else { return }
        self.navigationItem.rightBarButtonItems?.last?.isEnabled = !self.navigateWebViewScrollPositions.isEmpty
        if position.0 == currentPageNumber {
            self.currentPage?.setScrollViewContentOffset(position.1, animated: true)
        } else {
            self.changePageWith(page: position.0) {     //depends on `currentWebViewScrollPositions` to in page reposition
                self.currentPage?.updatePages()
            }
        }
    }

    // MARK: Change page progressive direction

    private func transformViewForRTL(_ view: UIView?) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        if folioReader.needsRTLChange {
            view?.transform = CGAffineTransform(scaleX: -1, y: 1)
        } else {
            view?.transform = CGAffineTransform.identity
        }
    }

    func setCollectionViewProgressiveDirection() {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        self.transformViewForRTL(self.collectionView)
    }

    func setPageProgressiveDirection(_ page: FolioReaderPage) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        self.transformViewForRTL(page)
    }
    // MARK: Status bar and Navigation bar

    func hideBars() {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        invalidatePendingBarReveal()
        self.updateBarsStatus(true)
    }

    func showBars() {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }
        guard readerConfig.hideBars == false else { return }

        invalidatePendingBarReveal()
        self.configureNavBar()
        self.updateBarsStatus(false)
    }

    func toggleBars() {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }
        guard let navigationController = barHostingNavigationController else { return }

        if readerConfig.hideBars == true {
            hideBars()
            return
        }

        let shouldHide = !navigationController.isNavigationBarHidden
        if shouldHide == false {
            self.configureNavBar()
        }

        self.updateBarsStatus(shouldHide)
    }

    private func updateBarsStatus(_ shouldHide: Bool, shouldShowIndicator: Bool = false) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        guard let readerContainer = readerContainer else { return }
        readerContainer.shouldHideStatusBar = shouldHide

        UIView.animate(withDuration: 0.25, animations: {
            readerContainer.setNeedsStatusBarAppearanceUpdate()

            self.pageIndicatorView?.alpha = shouldHide ? 0 : 1
        })
        barHostingNavigationController?.setNavigationBarHidden(shouldHide, animated: true)
    }
}
