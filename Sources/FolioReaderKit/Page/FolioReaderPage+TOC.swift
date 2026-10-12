//
//  FolioReaderPage+TOC.swift
//  FolioReaderKit
//

import UIKit
import FolioEPUBCore

extension FolioReaderPage {
    /**
     Find and return the current chapter resource.
     */
    public func getChapter() -> FRResource? {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        var foundResource: FRResource?

        func search(_ items: [FRTocReference]) {
            for item in items {
                guard foundResource == nil else { break }

                if let reference = book.spine.spineReferences[safe: (pageNumber - 1)], let resource = item.resource, resource == reference.resource {
                    foundResource = resource
                    break
                } else if !item.children.isEmpty {
                    search(item.children)
                }
            }
        }
        search(book.flatTableOfContents)

        return foundResource
    }

    
    
    /**
     Find and return the current chapter name.
     */
    public func getChapterName() -> String? {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        var foundChapterName: String?
        
        func search(_ items: [FRTocReference]) {
            for item in items {
                guard foundChapterName == nil else { break }
                
                if let reference = self.book.spine.spineReferences[safe: pageNumber - 1],
                    let resource = item.resource,
                    resource == reference.resource {
                    foundChapterName = item.title
                } else if !item.children.isEmpty {
                    search(item.children)
                }
            }
        }
        search(self.book.flatTableOfContents)
        
        return foundChapterName
    }

    public func getBundleRootTocIndex() -> Int? {
        guard self.book.bundleRootTableOfContents.isEmpty == false else { return nil }

        var tocRef = self.folioReader.readerCenter?.getChapterName(pageNumber: pageNumber)
        var bookTocIndex: Int? = nil
        while let currentTocRef = tocRef {
            bookTocIndex = self.book.bundleRootTableOfContents.firstIndex(of: currentTocRef) ?? bookTocIndex
            tocRef = currentTocRef.parent
        }
        
        return bookTocIndex
    }

    func updateCurrentChapterName() {
        guard let contentOffset = self.webView?.scrollView.contentOffset,
              let webViewFrameSize = self.webView?.frame.size else { return }
        
        DispatchQueue.main.async {
            if let firstChapterTocReference = self.getChapterTocReferences(for: contentOffset, by: webViewFrameSize).first {
                self.currentChapterName = firstChapterTocReference.title
            } else {
                self.currentChapterName = self.folioReader.readerCenter?.getChapterName(pageNumber: self.pageNumber)?.title
            }
            
            guard let readerCenter = self.folioReader.readerCenter,
                  self.pageNumber == readerCenter.currentPageNumber else { return }
            
            if self.folioReader.structuralStyle == .bundle,
               self.readerConfig.displayTitle,
               let bookTocIndex = self.getBundleRootTocIndex(),
               let bookToc = self.book.bundleRootTableOfContents[safe: bookTocIndex],
               let bundleTitle = self.book.title {
                let bookTitle = bookToc.title
                if readerCenter.navigationItem.titleView == nil {
                    let titleView = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 50))
                    readerCenter.navigationItem.titleView = titleView
                    titleView.translatesAutoresizingMaskIntoConstraints = false
                    
                    let bookTitleLabel = UILabel()
                    bookTitleLabel.tag = 101
                    bookTitleLabel.font = .systemFont(ofSize: 16)
                    bookTitleLabel.textColor = self.readerConfig.themeModeTextColor[self.folioReader.themeMode]
                    bookTitleLabel.textAlignment = .center
                    bookTitleLabel.translatesAutoresizingMaskIntoConstraints = false
                    bookTitleLabel.adjustsFontSizeToFitWidth = true
                    bookTitleLabel.adjustsFontForContentSizeCategory = true
                    titleView.addSubview(bookTitleLabel)
                    
                    let bundleTitleLabel = UILabel()
                    bundleTitleLabel.tag = 102
                    bundleTitleLabel.font = .systemFont(ofSize: 11)
                    bundleTitleLabel.textColor = self.readerConfig.themeModeTextColor[self.folioReader.themeMode]
                    bundleTitleLabel.textAlignment = .center
                    bundleTitleLabel.translatesAutoresizingMaskIntoConstraints = false
                    bundleTitleLabel.adjustsFontSizeToFitWidth = true
                    bundleTitleLabel.adjustsFontForContentSizeCategory = true
                    titleView.addSubview(bundleTitleLabel)
                    
                    var constraints = [NSLayoutConstraint]()
                    let views = ["book": bookTitleLabel, "bundle": bundleTitleLabel]
                    
                    constraints.append(contentsOf: NSLayoutConstraint.constraints(withVisualFormat: "H:|-[book]-|", options: [], metrics: nil, views: views))
                    constraints.append(contentsOf: NSLayoutConstraint.constraints(withVisualFormat: "H:|-[bundle]-|", options: [], metrics: nil, views: views))
                    constraints.append(contentsOf: NSLayoutConstraint.constraints(withVisualFormat: "V:|-[book]-2-[bundle]-|", options: [], metrics: nil, views: views))
                    
                    titleView.addConstraints(constraints)
                }
                if let bookTitleLabel = readerCenter.navigationItem.titleView?.viewWithTag(101) as? UILabel {
                    bookTitleLabel.text = bookTitle
                    bookTitleLabel.sizeToFit()
                }
                if let bundleTitleLabel = readerCenter.navigationItem.titleView?.viewWithTag(102) as? UILabel {
                    bundleTitleLabel.text = bundleTitle
                    bundleTitleLabel.sizeToFit()
                }
                readerCenter.navigationItem.titleView?.sizeToFit()
            } else {
                readerCenter.navigationItem.titleView = nil
            }
            
            readerCenter.pageIndicatorView?.reloadViewWithPage(self.currentPage)
        }
    }
    
    /**
     return: array from child to each level of parent
     */
    func getChapterTocReferences(for contentOffset: CGPoint, by webViewFrameSize: CGSize) -> [FRTocReference] {
        var firstChapterTocReference = self.folioReader.readerCenter?.getChapterName(pageNumber: self.pageNumber)
        
        if let pageChapterTocReferences = self.pageChapterTocReferences,
           let idOffsets = self.idOffsets {
            let tocRefWithDistance = pageChapterTocReferences.compactMap({ (toc) -> (toc: FRTocReference, offset: Int, distance: CGFloat)? in
                guard let id = toc.fragmentID,
                      let offset = idOffsets[id] else { return nil }
                return (
                 toc: toc,
                 offset: offset,
                 distance: self.pagesDown
                    ? contentOffset.y + webViewFrameSize.height / 2 - CGFloat(offset)
                    : self.byWritingMode(
                     contentOffset.forDirection(withConfiguration: self.readerConfig) + webViewFrameSize.forDirection(withConfiguration: self.readerConfig) / 2 - CGFloat(offset),
                     -(contentOffset.x - CGFloat(offset))
                     )
                )
            })
            
            if let toc = tocRefWithDistance.filter({ $0.distance > 0 }).min(by: { $0.distance < $1.distance })?.toc {
                firstChapterTocReference = toc
            }
        }
           
        var chapterTocReferences = [FRTocReference]()
        while let currentRef = firstChapterTocReference {
            chapterTocReferences.append(currentRef)
            firstChapterTocReference = currentRef.parent
            if self.folioReader.structuralStyle != .atom, (firstChapterTocReference?.level ?? 0) < self.folioReader.structuralTrackingTocLevel.rawValue - 1 {
                break
            }
        }
        return chapterTocReferences
    }
}
