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

        // Configure the cell
        let resource = self.book.spine.spineReferences[indexPath.row].resource

        let resourceHref = resource.href
        guard let fileName = self.book.name,
              !resourceHref.isEmpty,
              let opfResource = self.book.opfResource
        else { return cell }
        
        guard let url = FolioReaderCenter.resourceURL(
            fileName: fileName,
            opfHref: opfResource.href,
            resourceHref: resourceHref,
            port: readerContainer.webServer.port
        ) else { return cell }
        
        FolioLogger.log("webView.load url=\(url.absoluteString)")
        cell.loadInterval = FolioSignpost.begin("PageLoad", "page \(indexPath.row + 1)", log: FolioSignpost.milestones)
        cell.loadNavigation = cell.webView?.load(URLRequest(url: url))
        
        return cell
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
