//
//  UICollectionViewDataSource.swift
//  FolioReaderKit
//
//  Created by 京太郎 on 2021/9/14.
//  Copyright © 2021 FolioReader. All rights reserved.
//

import Foundation
import UIKit

extension FolioReaderCenter: UICollectionViewDataSource {
    
    open func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    open func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return totalPages
    }

    open func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        let reuseableCell = collectionView.dequeueReusableCell(withReuseIdentifier: kReuseCellIdentifier, for: indexPath) as? FolioReaderPage
        return self.configure(readerPageCell: reuseableCell, atIndexPath: indexPath)
    }

    private func configure(readerPageCell cell: FolioReaderPage?, atIndexPath indexPath: IndexPath) -> UICollectionViewCell {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        guard let cell = cell, let readerContainer = readerContainer else {
            return UICollectionViewCell()
        }
        
        if cell.pageNumber == indexPath.row + 1 {
            updateKeptPage(cell)
            return cell
        }
        
        cell.setup(withReaderContainer: readerContainer)
        cell.pageNumber = indexPath.row+1
        // A load still running for the page this cell showed before won't reach pageDidLoad.
        cell.loadInterval?.end("replaced")
        cell.loadInterval = nil
        cell.loadNavigation = nil
        cell.layoutAdapting = .initializing
        cell.pinnedPosition = nil
        
        cell.webView?.scrollView.delegate = self.scrollHandler
        cell.webView?.scrollView.contentInsetAdjustmentBehavior = .never
        cell.webView?.setupScrollDirection()
        cell.webView?.frame = cell.webViewFrame()
        cell.delegate = self
        cell.backgroundColor = .clear

        setPageProgressiveDirection(cell)

        loadChapter(in: cell)
        return cell
    }

    /// Loads `page`'s chapter from the resource server.
    func loadChapter(in page: FolioReaderPage) {
        guard let readerContainer = readerContainer,
              let resource = self.book.spine.spineReferences[safe: page.pageNumber - 1]?.resource,
              !resource.href.isEmpty,
              let fileName = self.book.name,
              let opfResource = self.book.opfResource,
              let url = FolioReaderCenter.resourceURL(
                fileName: fileName,
                opfHref: opfResource.href,
                resourceHref: resource.href,
                port: readerContainer.pagePort
              )
        else { return }

        FolioLogger.log("webView.load url=\(url.absoluteString)")
        page.loadedPort = readerContainer.pagePort
        page.spreadMinimumWidth = spreadMinimumWidth
        page.recordLayout()
        page.needsReload = false
        // The load styles the chapter with the settings in effect then.
        page.styleState = nil
        page.styledThemeMode = nil
        page.loadGeneration += 1
        page.loadInterval = FolioSignpost.begin("PageLoad", "page \(page.pageNumber)", log: FolioSignpost.milestones)
        page.loadNavigation = page.webView?.load(URLRequest(url: url))
    }

    /// Loads a page's chapter again (`shouldReload`), and restores the position the page last
    /// recorded (`pageDidLoad`).
    func reloadChapter(in page: FolioReaderPage) {
        if let pinned = page.pinnedPosition {
            currentWebViewScrollPositions[page.pageNumber - 1] = pinned
        }
        page.pinnedPosition = nil
        page.loadInterval?.end("replaced")
        page.loadInterval = nil
        page.loadNavigation = nil
        page.layoutAdapting = .initializing
        // After a scroll-direction change the page's bounds may be unchanged: set up its web view's
        // scrolling and frame for the current direction (`layoutSubviews`).
        page.setNeedsLayout()
        loadChapter(in: page)
    }

    /// Reloads the visible pages that need it: those whose web content died, or every page when
    /// `all` (the server moved to another port). Cells kept off screen reload when shown again.
    func reloadPages(all: Bool) {
        guard let readerContainer = readerContainer else { return }
        for case let page as FolioReaderPage in collectionView.visibleCells
        where all || page.needsReload || page.loadedPort != readerContainer.pagePort || hasOtherSpreadSetting(page) {
            reloadChapter(in: page)
        }
    }

    /// After a rotation, a scroll-direction change or a style setting change, which `current` follows
    /// itself, brings the other visible pages up to date (`updateKeptPage`). Pages off screen are
    /// checked when shown again (`configure`), but the cell holding the first responder (a chapter
    /// loaded later than the one the reader went back to) stays among the visible cells off screen,
    /// takes the new size with them, and comes back without the data source.
    func updateOtherVisiblePages(except current: FolioReaderPage) {
        for case let page as FolioReaderPage in collectionView.visibleCells where page !== current {
            updateKeptPage(page)
        }
    }

    /// Brings a page that still shows its chapter up to date with what changed while only the current
    /// page followed: loads the chapter again from a port the server left, or laid out for another
    /// spread setting, scroll direction or size (`shouldReload`); else gives it the current theme
    /// (`hasOtherTheme`) and styles it again (`hasOtherStyle`). Either way it keeps its recorded
    /// position.
    func updateKeptPage(_ page: FolioReaderPage) {
        if shouldReload(page) {
            FolioLogger.log("kept page \(page.pageNumber): reload")
            reloadChapter(in: page)
            return
        }
        if hasOtherTheme(page) {
            FolioLogger.log("kept page \(page.pageNumber): theme")
            page.applyTheme(folioReader.themeMode)
        }
        if hasOtherStyle(page) {
            restyleChapter(in: page)
        }
    }

    /// Styles `page`'s chapter again with the current settings (`hasOtherStyle`) once a load or
    /// relayout in progress is over, at the position the page last recorded: the one restored to,
    /// else the one recorded for its chapter. That is lighter than a reload, and the layout it
    /// keeps (spread setting, direction, size) is the current one.
    func restyleChapter(in page: FolioReaderPage) {
        let pageNumber = page.pageNumber
        page.waitForLayoutFinish {
            guard page.pageNumber == pageNumber, self.hasOtherStyle(page) else { return }
            let position = (page.pinnedPosition ?? self.currentWebViewScrollPositions[pageNumber - 1])
                .flatMap { Self.isRestorableCFI($0.cfi, pageNumber: pageNumber) ? $0 : nil }
            FolioLogger.log("kept page \(pageNumber): restyle cfi=\(position?.cfi ?? "none")")
            page.restyle(restoring: position)
        }
    }
}

extension FolioReaderCenter {
    static func resourceURL(fileName: String, opfHref: String, resourceHref: String, port: UInt) -> URL? {
        var urlComponents = URLComponents()
        urlComponents.scheme = "http"
        urlComponents.host = "localhost"
        urlComponents.port = Int(port)
        urlComponents.path = ["", fileName, opfHref.deletingLastPathComponent, resourceHref].joined(separator: "/")
        return urlComponents.url
    }
}
