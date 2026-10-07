//
//  FolioReaderPage+Anchors.swift
//  FolioReaderKit
//

import UIKit

extension FolioReaderPage {
    /**
     Handdle #anchors in html, get the offset and scroll to it

     - parameter anchor:                The #anchor
     - parameter avoidBeginningAnchors: Sometimes the anchor is on the beggining of the text, there is not need to scroll
     - parameter animated:              Enable or not scrolling animation
     */
    public func handleAnchor(_ anchor: String, offsetInWindow: CGFloat, avoidBeginningAnchors: Bool, animated: Bool, flashTarget: Bool = true, completion: (() -> Void)? = nil) {
        guard !anchor.isEmpty else { return }
        
        guard let webView = webView, webView.isHidden == false, self.layoutAdapting == nil else {
            DispatchQueue.main.asyncAfter(delay: 0.1) {
                self.handleAnchor(anchor, offsetInWindow: offsetInWindow, avoidBeginningAnchors: avoidBeginningAnchors, animated: animated, flashTarget: flashTarget, completion: completion)
            }
            return
        }
        
        getAnchorOffset(anchor) { offset in
            if let infoLabelText = self.readerContainer?.centerViewController?.pageIndicatorView?.infoLabel.text {
                self.readerContainer?.centerViewController?.pageIndicatorView?.infoLabel.text = "\(offset) \(infoLabelText)"
            }
            self.byWritingMode {
                switch self.readerConfig.scrollDirection {
                case .horizontalWithPagedContent:
                    let page = floor(offset / webView.frame.width)
                    self.scrollPageToOffset(page * webView.frame.width, animated: animated)
                default:
                    let isBeginning = (offset < self.frame.forDirection(withConfiguration: self.readerConfig) * 0.5)
                    
                    var voffset = offset > offsetInWindow ?
                    offset - offsetInWindow : offset
                    
                    if let contentHeight = self.webView?.scrollView.contentSize.height,
                       voffset + (self.folioReader.readerCenter?.pageHeight ?? 0) - (self.readerContainer?.navigationController?.navigationBar.frame.height ?? 0) > contentHeight {
                        voffset = contentHeight - (self.folioReader.readerCenter?.pageHeight ?? 0) + (self.readerContainer?.navigationController?.navigationBar.frame.height ?? 0)
                    }
                    
                    if !avoidBeginningAnchors {
                        self.scrollPageToOffset(voffset, animated: animated)
                    } else if avoidBeginningAnchors && !isBeginning {
                        self.scrollPageToOffset(voffset, animated: animated)
                    }
                }
            } vertical: {
                switch self.readerConfig.scrollDirection {
                case .horizontalWithPagedContent:
                    let page = ceil(offset / webView.frame.width)
                    self.scrollPageToOffset(webView.scrollView.contentSize.width - (page+1) * webView.frame.width, animated: true)
                default:
                    self.scrollPageToOffset(offset + webView.frame.width, animated: animated)
                }
            }
            
            self.folioReader.readerCenter?.currentWebViewScrollPositions.removeValue(forKey: self.pageNumber - 1)
            
            if flashTarget {
                self.webView?.js("highlightAnchorText('\(anchor)', 'highlight-yellow', 3)")
            }
            
            completion?()
        }
    }

    /**
     Get the #anchor offset in the page

     - parameter anchor: The #anchor id
     - returns: The element offset ready to scroll
     */
    func getAnchorOffset(_ anchor: String, completion: @escaping ((CGFloat) -> ())) {
        let horizontal = self.readerConfig.scrollDirection == .horizontalWithPagedContent
        self.webView?.js("getAnchorOffset(\"\(anchor)\", \(horizontal.description))") { strOffset in
            guard let strOffset = strOffset else {
                completion(CGFloat(0))
                return
            }
            completion(CGFloat((strOffset as NSString).floatValue))
        }
    }

    /**
     Audio Mark ID - marks an element with an ID with the given class and scrolls to it

     - parameter identifier: The identifier
     */
    func audioMarkID(_ identifier: String) {
        guard let currentPage = self.folioReader.readerCenter?.currentPage else {
            return
        }

        let playbackActiveClass = self.book.playbackActiveClass
        currentPage.webView?.js("audioMarkID('\(playbackActiveClass)','\(identifier)')")
    }
}
