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
            // A cell kept off screen may still show a chapter from a port the server left.
            if cell.needsReload || cell.loadedPort != readerContainer.pagePort {
                reloadChapter(in: cell)
            }
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
        page.needsReload = false
        page.loadInterval = FolioSignpost.begin("PageLoad", "page \(page.pageNumber)", log: FolioSignpost.milestones)
        page.loadNavigation = page.webView?.load(URLRequest(url: url))
    }

    /// Loads a page's chapter again, after its web content process died or the server moved to
    /// another port, and restores the position the page last recorded (`pageDidLoad`).
    func reloadChapter(in page: FolioReaderPage) {
        if let pinned = page.pinnedPosition {
            currentWebViewScrollPositions[page.pageNumber - 1] = pinned
        }
        page.pinnedPosition = nil
        page.loadInterval?.end("replaced")
        page.loadInterval = nil
        page.loadNavigation = nil
        page.layoutAdapting = .initializing
        loadChapter(in: page)
    }

    /// Reloads the visible pages that need it: those whose web content died, or every page when
    /// `all` (the server moved to another port). Cells kept off screen reload when shown again.
    func reloadPages(all: Bool) {
        guard let readerContainer = readerContainer else { return }
        for case let page as FolioReaderPage in collectionView.visibleCells
        where all || page.needsReload || page.loadedPort != readerContainer.pagePort {
            reloadChapter(in: page)
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
