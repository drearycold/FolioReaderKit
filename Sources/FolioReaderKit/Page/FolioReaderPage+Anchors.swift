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
        
        // A new destination; `restorePinned` pins its position again once the scroll has started.
        self.pinnedPosition = nil

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
                    
                    // No further than the last screen. The web view is shorter than the page (the
                    // status bar and page indicator are reserved), so the page height gave offsets
                    // short of the last screen, and below zero in a chapter of one screen.
                    let scrollView = webView.scrollView
                    voffset = max(min(voffset, scrollView.contentSize.height - scrollView.bounds.height), 0)
                    
                    if !avoidBeginningAnchors {
                        self.scrollPageToOffset(voffset, animated: animated)
                    } else if avoidBeginningAnchors && !isBeginning {
                        self.scrollPageToOffset(voffset, animated: animated)
                    }
                }
            } vertical: {
                self.scrollVerticalWriting(toAnchor: anchor, measured: offset, animated: self.readerConfig.scrollDirection == .horizontalWithPagedContent || animated)
            }
            
            self.folioReader.readerCenter?.currentWebViewScrollPositions.removeValue(forKey: self.pageNumber - 1)
            
            if flashTarget {
                self.webView?.js("highlightAnchorText('\(anchor)', 'highlight-yellow', 3)")
            }
            
            completion?()
        }
    }

    /// Vertical writing in scroll mode: the content offset that shows the anchor `getAnchorOffset`
    /// measured as `offset`, its start (the right edge of its column) at the right edge of the view.
    ///
    /// The chapter starts at the right end of the content. `getAnchorOffset` returns
    /// `-(right + scrollX)`, so the view shows the anchor at its right edge after scrolling
    /// `offset + viewWidth` from the start. Using that distance as the content offset, which counts
    /// from the left, restored every position mirrored: the start of a chapter to its end.
    static func verticalWritingScrollOffset(anchorOffset offset: CGFloat, contentWidth: CGFloat, viewWidth: CGFloat) -> CGFloat {
        verticalWritingContentOffset(fromStart: offset + viewWidth, contentWidth: contentWidth, viewWidth: viewWidth)
    }

    /// Vertical writing: the content offset of a view scrolled `distance` from the start of the
    /// chapter, the right end of the content.
    static func verticalWritingContentOffset(fromStart distance: CGFloat, contentWidth: CGFloat, viewWidth: CGFloat) -> CGFloat {
        let start = max(contentWidth - viewWidth, 0)
        return min(max(start - distance, 0), start)
    }

    /// Vertical writing: scrolls to `anchor`, whose `getAnchorOffset` is `offset`, by its distance from
    /// the start of the chapter, then measures again and corrects, retrying like `scrollPageToOffset`.
    ///
    /// Content offsets count from the left while the chapter starts at the right, and the page can
    /// still change after a load or a layout change (the body's `min-width` is rounded up to whole
    /// screens). WebKit keeps the text in place when the width grows by moving the offset, so retrying
    /// the offset computed before (as `scrollPageToOffset` does) moved the text back by the growth, two
    /// columns on an iPhone; and reflowing columns move the anchor itself. Each retry measures the
    /// anchor and works the offset out from the current width.
    ///
    /// Retries stop once the anchor is in place, and when anything else moved the page or the cell
    /// shows another chapter: they used to pull a page the reader had just turned back to the anchor.
    func scrollVerticalWriting(toAnchor anchor: String, measured offset: CGFloat, animated: Bool, retry: Int = 5) {
        guard let webView = webView else { return }
        let width = webView.frame.width
        let distance = readerConfig.scrollDirection == .horizontalWithPagedContent
            ? ceil(offset / width) * width    // the start of the page that holds the anchor
            : offset + width                  // the anchor's start at the right edge of the view
        let target = CGPoint(x: Self.verticalWritingContentOffset(
            fromStart: distance, contentWidth: webView.scrollView.contentSize.width, viewWidth: width
        ), y: 0)
        let inPlace = abs(target.x - webView.scrollView.contentOffset.x) < 1
        if !inPlace {
            setScrollViewContentOffset(target, animated: animated)
        }
        guard retry > 0, !(inPlace && retry < 5) else { return }
        let pageNumber = self.pageNumber
        DispatchQueue.main.asyncAfter(delay: 0.1 * Double(retry)) {
            // A moved offset means the reader (or a page turn) moved the page, or WebKit kept the text
            // in place as the content grew: either way there is nothing left to correct.
            guard self.pageNumber == pageNumber,
                  !webView.scrollView.isTracking, !webView.scrollView.isDecelerating,
                  abs(webView.scrollView.contentOffset.x - target.x) < 1 else { return }
            self.getAnchorOffset(anchor) { offset in
                self.scrollVerticalWriting(toAnchor: anchor, measured: offset, animated: animated, retry: retry - 1)
            }
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
