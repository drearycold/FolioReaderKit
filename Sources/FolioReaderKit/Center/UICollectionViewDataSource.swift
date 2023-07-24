//
//  UICollectionViewDataSource.swift
//  FolioReaderKit
//
//  Created by 京太郎 on 2021/9/14.
//  Copyright © 2021 FolioReader. All rights reserved.
//

import Foundation

extension FolioReaderCenter: UICollectionViewDataSource {
    
    open func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    open func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return totalPages
    }

    open func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        let reuseableCell = collectionView.dequeueReusableCell(withReuseIdentifier: kReuseCellIdentifier, for: indexPath) as? FolioReaderPage
        return self.configure(readerPageCell: reuseableCell, atIndexPath: indexPath)
    }

    private func configure(readerPageCell cell: FolioReaderPage?, atIndexPath indexPath: IndexPath) -> UICollectionViewCell {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        guard let cell = cell, let readerContainer = readerContainer else {
            return UICollectionViewCell()
        }
        
        if cell.pageNumber == indexPath.row + 1 {
            return cell
        }
        
        cell.setup(withReaderContainer: readerContainer)
        cell.pageNumber = indexPath.row+1
        cell.layoutAdapting = "Initializing..."
        
        cell.webView?.scrollView.delegate = self
        if #available(iOS 11.0, *) {
            cell.webView?.scrollView.contentInsetAdjustmentBehavior = .never
        }
        //cell.webView?.cssRuntimeProperty = self.folioReader.generateRuntimeStyle()
        cell.webView?.setupScrollDirection()
        cell.webView?.frame = cell.webViewFrame()
        cell.delegate = self
        cell.backgroundColor = .clear

        setPageProgressiveDirection(cell)

        // Configure the cell
        let resource = self.book.spine.spineReferences[indexPath.row].resource

        guard let fileName = self.book.name,
              let resourceHref = resource.href
        else { return cell }
        
        var urlComponents = URLComponents()
        urlComponents.scheme = "http"
        urlComponents.host = "localhost"
        urlComponents.port = readerConfig.serverPort
        urlComponents.path = ["", fileName, self.book.opfResource.href.deletingLastPathComponent, resourceHref].joined(separator: "/")
        
        guard let url = urlComponents.url else { return cell }
        
        folioLogger("webView.load url=\(url.absoluteString)")
        cell.webView?.load(URLRequest(url: url))
        
        return cell
    }

}
