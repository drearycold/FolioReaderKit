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
//        guard var html = try? String(contentsOfFile: resource.fullHref, encoding: String.Encoding.utf8) else {
//            return cell
//        }
        var html = ""
        
        // Inject viewport
        if (false) {
        let viewportTag = ""  //  "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, shrink-to-fit=no\">"
        let initialRuntimeStyleCss = ""//folioReader.generateRuntimeStyle()

        let toInject = """
            \(viewportTag)
            <style id=\"style-folioreader-runtime\" type=\"text/css\">
                \(initialRuntimeStyleCss)
            </style>
        </head>
        """
        html = html.replacingOccurrences(of: "</head>", with: toInject)
        }

        if (false) {
        // Font class name
        var classes = ""
        classes += " " + folioReader.currentMediaOverlayStyle.className()

        switch folioReader.themeMode {
        case 1:
            classes += " serpiaMode"
            break
        case 2:
            classes += " greenMode"
            break
        case 3:
            classes += " darkMode"
            break
        case 4:
            classes += " nightMode"
            break
        default:
            break
        }

        // Font Size
//        classes += " \(folioReader.currentFontSize.cssIdentifier)"

        // TODO block layout
        classes += " justifiedBlockMode"
        
        html = html.replacingOccurrences(of: "<html ", with: "<html class=\"\(classes)\" ")
        }
        // Let the delegate adjust the html string
        if let modifiedHtmlContent = self.delegate?.htmlContentForPage(cell, htmlContent: html) {
            html = modifiedHtmlContent
        }
        
//        if let resourceBasePath = self.book.smils.basePath {
//            let contentURL = URL(fileURLWithPath: resource.fullHref)
//            print("\(#function) CONFIG \(cell.debugDescription) \(cell.webView.debugDescription) \(contentURL) \(resourceBasePath)")
//            cell.webView?.loadFileURL(contentURL, allowingReadAccessTo: URL(fileURLWithPath: resourceBasePath))
            
//            urlComponents.path = contentURL.path
            
            guard let fileName = self.book.name,
                  let resourceHref = resource.href
            else { return cell }
            guard let path = ["", fileName, self.book.opfResource.href.deletingLastPathComponent, resourceHref].joined(separator: "/").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return cell }
        
            var urlComponents = URLComponents()
            urlComponents.scheme = "http"
            urlComponents.host = "localhost"
            urlComponents.port = readerConfig.serverPort
            urlComponents.path = path
            guard let url = urlComponents.url else { return cell }
            folioLogger("webView.load url=\(url.absoluteString)")
            cell.webView?.load(URLRequest(url: url))
//        }
        
        if (false) {
            cell.loadHTMLString(html, baseURL: URL(fileURLWithPath: resource.fullHref.deletingLastPathComponent))
        }
        return cell
    }

}
