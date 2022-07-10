//
//  FolioReaderPage.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 10/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import SafariServices
import MenuItemKit
import OSLog
import WebKit

/// Protocol which is used from `FolioReaderPage`s.
@objc public protocol FolioReaderPageDelegate: AnyObject {

    /**
     Notify that the page will be loaded. Note: The webview content itself is already loaded at this moment. But some java script operations like the adding of class based on click listeners will happen right after this method. If you want to perform custom java script before this happens this method is the right choice. If you want to modify the html content (and not run java script) you have to use `htmlContentForPage()` from the `FolioReaderCenterDelegate`.

     - parameter page: The loaded page
     */
    @objc optional func pageWillLoad(_ page: FolioReaderPage)

    /**
     Notifies that page did load. A page load doesn't mean that this page is displayed right away, use `pageDidAppear` to get informed about the appearance of a page.

     - parameter page: The loaded page
     */
    @objc optional func pageDidLoad(_ page: FolioReaderPage)
    
    /**
     Notifies that page receive tap gesture.
     
     - parameter recognizer: The tap recognizer
     */
    @objc optional func pageTap(_ recognizer: UITapGestureRecognizer)
}

open class FolioReaderPage: UICollectionViewCell, WKNavigationDelegate, UIGestureRecognizerDelegate, WKScriptMessageHandler {
    weak var delegate: FolioReaderPageDelegate?
    weak var readerContainer: FolioReaderContainer?

    /// The index of the current page. Note: The index start at 1!
    open var pageNumber: Int! {
        didSet {
            self.pageChapterNames = self.folioReader.readerCenter?.getChapterNames(pageNumber: self.pageNumber)
        }
    }
    open var webView: FolioReaderWebView?
    open var panDeadZoneTop: UIView?
    open var panDeadZoneBot: UIView?
    open var panDeadZoneLeft: UIView?
    open var panDeadZoneRight: UIView?
    open var loadingView = UIActivityIndicatorView()

    open var writingMode = "horizontal-tb"
    
    open var pageOffsetRate: CGFloat = 0 {
        didSet {
            folioLogger("SET pageOffsetRate=\(pageOffsetRate) pageNumber=\(pageNumber!) currentPage=\(currentPage) totalPages=\(totalPages ?? -1)")
        }
    }

    var totalMinutes: Int?
    var totalPages: Int?
    var currentPage: Int = 1 {
        didSet {
            guard let contentOffset = self.webView?.scrollView.contentOffset,
                  let webViewFrameSize = self.webView?.frame.size else { return }
            DispatchQueue.global(qos: .utility).async {
                if let names = self.pageChapterNames,
                   let idOffsets = self.idOffsets,
                   let firstChapterName = names.compactMap({ (name) -> (id: String, name: String, offset: Int, distance: CGFloat)? in
                       guard let id = name.id else { return nil }
                       guard let offset = idOffsets[id] else { return nil }
                       return (
                        id: id,
                        name: name.name,
                        offset: offset,
                        distance: self.byWritingMode(
                            contentOffset.forDirection(withConfiguration: self.readerConfig) + webViewFrameSize.forDirection(withConfiguration: self.readerConfig) / 2 - CGFloat(offset),
                            -(contentOffset.x - CGFloat(offset))
                            )
                       )
                   }).filter({ $0.distance > 0 }).min(by: { $0.distance < $1.distance }) {
                    self.currentChapterName = firstChapterName.name
                } else {
                    self.currentChapterName = self.folioReader.readerCenter?.getChapterName(pageNumber: self.pageNumber)
                }
                
                DispatchQueue.main.async {
                    if self.pageNumber == self.folioReader.readerCenter?.currentPageNumber {
                        self.folioReader.readerCenter?.pageIndicatorView?.reloadViewWithPage(self.currentPage)
                    }
                }
            }
        }
    }
    var currentChapterName: String?
    var pageChapterNames: [(id: String?, name: String)]?
    var idOffsets: [String: Int]?
    
    fileprivate var colorView: UIView!
    fileprivate var shouldShowBar = true
    fileprivate var menuIsVisible = false
    fileprivate var firstLoadReloaded = false
    
    var layoutAdapting = false {
        didSet {
            layoutAdapting ? loadingView.startAnimating() : loadingView.stopAnimating()
        }
    }
    fileprivate var readerConfig: FolioReaderConfig {
        guard let readerContainer = readerContainer else { return FolioReaderConfig() }
        return readerContainer.readerConfig
    }

    fileprivate var book: FRBook {
        guard let readerContainer = readerContainer else { return FRBook() }
        return readerContainer.book
    }

    fileprivate var folioReader: FolioReader {
        guard let readerContainer = readerContainer else { return FolioReader() }
        return readerContainer.folioReader
    }

    // MARK: - View life cicle

    public override init(frame: CGRect) {
        // Init explicit attributes with a default value. The `setup` function MUST be called to configure the current object with valid attributes.
        self.readerContainer = FolioReaderContainer(withConfig: FolioReaderConfig(), folioReader: FolioReader(), epubPath: "")
        super.init(frame: frame)
        self.backgroundColor = UIColor.clear

        NotificationCenter.default.addObserver(self, selector: #selector(refreshPageMode), name: NSNotification.Name(rawValue: "needRefreshPageMode"), object: nil)
    }

    public func setup(withReaderContainer readerContainer: FolioReaderContainer) {
        self.readerContainer = readerContainer
        guard let readerContainer = self.readerContainer else { return }

        self.pageNumber = -1     //guard against webView didFinish handler
        
        if webView == nil {
            webView = FolioReaderWebView(frame: webViewFrame(), readerContainer: readerContainer)
            webView?.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            webView?.scrollView.showsVerticalScrollIndicator = false
            webView?.scrollView.showsHorizontalScrollIndicator = false
            webView?.scrollView.scrollsToTop = false
            webView?.backgroundColor = .clear
            webView?.configuration.userContentController.add(self, name: "FolioReaderPage")
            self.contentView.addSubview(webView!)
            if readerConfig.debug.contains(.borderHighlight) {
                webView?.layer.borderWidth = 10
                webView?.layer.borderColor = UIColor.magenta.cgColor
            }
        }
        webView?.isHidden = true
        webView?.navigationDelegate = self

        if panDeadZoneTop == nil {
            panDeadZoneTop = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
            panDeadZoneTop?.autoresizingMask = []
            panDeadZoneTop?.backgroundColor = self.readerContainer?.readerConfig.themeModeBackground[self.folioReader.themeMode]
            panDeadZoneTop?.isOpaque = false
            
            let panGeature = UIPanGestureRecognizer(target: self, action: nil)
            panGeature.delegate = self
            panDeadZoneTop?.addGestureRecognizer(panGeature)
            
            self.contentView.addSubview(panDeadZoneTop!)
        }
        
        if panDeadZoneBot == nil {
            panDeadZoneBot = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
            panDeadZoneBot?.autoresizingMask = []
            panDeadZoneBot?.backgroundColor = self.readerContainer?.readerConfig.themeModeBackground[self.folioReader.themeMode]
            panDeadZoneBot?.isOpaque = false
            
            let panGeature = UIPanGestureRecognizer(target: self, action: nil)
            panGeature.delegate = self
            panDeadZoneBot?.addGestureRecognizer(panGeature)
            
            self.contentView.addSubview(panDeadZoneBot!)
        }
        
        if panDeadZoneLeft == nil {
            panDeadZoneLeft = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
            panDeadZoneLeft?.autoresizingMask = []
            panDeadZoneLeft?.backgroundColor = self.readerContainer?.readerConfig.themeModeBackground[self.folioReader.themeMode]
            panDeadZoneLeft?.isOpaque = false
            
            let panGeature = UIPanGestureRecognizer(target: self, action: nil)
            panGeature.delegate = self
            panDeadZoneLeft?.addGestureRecognizer(panGeature)
            
            self.contentView.addSubview(panDeadZoneLeft!)
        }
        
        if panDeadZoneRight == nil {
            panDeadZoneRight = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
            panDeadZoneRight?.autoresizingMask = []
            panDeadZoneRight?.backgroundColor = self.readerContainer?.readerConfig.themeModeBackground[self.folioReader.themeMode]
            panDeadZoneRight?.isOpaque = false
            
            let panGeature = UIPanGestureRecognizer(target: self, action: nil)
            panGeature.delegate = self
            panDeadZoneRight?.addGestureRecognizer(panGeature)
            
            self.contentView.addSubview(panDeadZoneRight!)
        }
        
        if colorView == nil {
            colorView = UIView()
            colorView.backgroundColor = self.readerConfig.nightModeBackground
            webView?.scrollView.addSubview(colorView)
        }

        loadingView.style = folioReader.isNight(.white, .gray)
        loadingView.hidesWhenStopped = true
        loadingView.startAnimating()
        self.contentView.addSubview(loadingView)
        
        // Remove all gestures before adding new one
        webView?.gestureRecognizers?.forEach({ gesture in
            webView?.removeGestureRecognizer(gesture)
        })
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        tapGestureRecognizer.numberOfTapsRequired = 1
        tapGestureRecognizer.delegate = self
        webView?.addGestureRecognizer(tapGestureRecognizer)
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("storyboards are incompatible with truth and beauty")
    }

    deinit {
        webView?.scrollView.delegate = nil
        webView?.navigationDelegate = nil
        NotificationCenter.default.removeObserver(self)
    }

    override open func layoutSubviews() {
        super.layoutSubviews()

        webView?.setupScrollDirection()
        let webViewFrame = self.webViewFrame()
        webView?.frame = webViewFrame
        
        let panDeadZoneTopFrame = CGRect(x: 0, y: 0, width: webViewFrame.width, height: webViewFrame.minY)
        panDeadZoneTop?.frame = panDeadZoneTopFrame
        
        let panDeadZoneBotFrame = CGRect(x: 0, y: webViewFrame.maxY, width: webViewFrame.width, height: frame.height - webViewFrame.maxY)
        panDeadZoneBot?.frame = panDeadZoneBotFrame
        
        let panDeadZoneLeftFrame = CGRect(x: 0, y: 0, width: webViewFrame.minX, height: webViewFrame.height)
        panDeadZoneLeft?.frame = panDeadZoneLeftFrame
        
        let panDeadZoneRightFrame = CGRect(x: webViewFrame.maxX, y: 0, width: frame.width - webViewFrame.maxX, height: webViewFrame.height)
        panDeadZoneRight?.frame = panDeadZoneRightFrame
        
        print("\(#function) frame=\(frame) webViewFrame=\(webViewFrame)  panDeadZoneLeftFrame=\(panDeadZoneLeftFrame) panDeadZoneRightFrame=\(panDeadZoneRightFrame)")
        loadingView.center = contentView.center
    }

    func webViewFrame() -> CGRect {
        guard (self.readerConfig.hideBars == false) else {
            return bounds
        }
        
        let navBarHeight = self.folioReader.readerCenter?.navigationController?.navigationBar.frame.size.height ?? CGFloat(0)
        let topComponentTotal = self.readerConfig.shouldHideNavigationOnTap ? 0 : navBarHeight
        let bottomComponentTotal = self.readerConfig.hidePageIndicator ? 0 : self.folioReader.readerCenter?.pageIndicatorHeight ?? CGFloat(0)
        let paddingTop: CGFloat = floor(CGFloat(self.folioReader.currentMarginTop) / 200 * (self.folioReader.readerCenter?.pageHeight ?? CGFloat(0)))
        let paddingBottom: CGFloat = floor(CGFloat(self.folioReader.currentMarginBottom) / 200 * (self.folioReader.readerCenter?.pageHeight ?? CGFloat(0)))
        let paddingLeft: CGFloat = floor(CGFloat(self.folioReader.currentMarginLeft) / 200 * (self.folioReader.readerCenter?.pageWidth ?? CGFloat(0)))
        let paddingRight: CGFloat = floor(CGFloat(self.folioReader.currentMarginRight) / 200 * (self.folioReader.readerCenter?.pageWidth ?? CGFloat(0)))
        
        return byWritingMode(
            CGRect(
                x: bounds.origin.x,
                y: self.readerConfig.isDirection(
                    bounds.origin.y + topComponentTotal,
                    bounds.origin.y + topComponentTotal + paddingTop,
                    bounds.origin.y + topComponentTotal),
                width: bounds.width,
                height: max(self.readerConfig.isDirection(
                    bounds.height - topComponentTotal,
                    bounds.height - topComponentTotal - paddingTop - bottomComponentTotal - paddingBottom,
                    bounds.height - topComponentTotal), 0)
            ),
            CGRect(
                x: self.readerConfig.isDirection(
                    bounds.origin.x,
                    bounds.origin.x + paddingLeft,
                    bounds.origin.x),
                y: bounds.origin.y + topComponentTotal,
                width: self.readerConfig.isDirection(
                    bounds.width,
                    bounds.width - paddingLeft - paddingRight,
                    bounds.width),
                height: bounds.height - topComponentTotal - bottomComponentTotal
            )
        )
    }
    
    func webViewFrameVanilla() -> CGRect {
        guard (self.readerConfig.hideBars == false) else {
            return bounds
        }
        
        let statusbarHeight = UIApplication.shared.statusBarFrame.size.height
        let navBarHeight = self.folioReader.readerCenter?.navigationController?.navigationBar.frame.size.height ?? CGFloat(0)
        let navTotal = self.readerConfig.shouldHideNavigationOnTap ? 0 : statusbarHeight + navBarHeight
        let paddingTop: CGFloat = 20
        let paddingBottom: CGFloat = 30
        
        return CGRect(
            x: bounds.origin.x,
            y: self.readerConfig.isDirection(bounds.origin.y + navTotal, bounds.origin.y + navTotal + paddingTop, bounds.origin.y + navTotal),
            width: bounds.width,
            height: self.readerConfig.isDirection(bounds.height - navTotal, bounds.height - navTotal - paddingTop - paddingBottom, bounds.height - navTotal)
        )
    }
    
    func webViewFramePeter() -> CGRect {
        guard (self.readerConfig.hideBars == false) else {
            return bounds
        }

        let statusbarHeight = UIApplication.shared.statusBarFrame.size.height
        let navBarHeight = self.folioReader.readerCenter?.navigationController?.navigationBar.frame.size.height ?? CGFloat(0)
        let navTotal = self.readerConfig.shouldHideNavigationOnTap ? 0 : statusbarHeight + navBarHeight
        let paddingTop: CGFloat = -40
        let paddingBottom: CGFloat = 50

        print("boundsFrame \(bounds)")
        print("statusBarFrame \(UIApplication.shared.statusBarFrame)")
        print("navigationBarFrame \(String(describing: self.folioReader.readerCenter?.navigationController?.navigationBar.frame))")
        
        let x = bounds.origin.x
        var y = self.readerConfig.isDirection(bounds.origin.y + navTotal, bounds.origin.y + navTotal + paddingTop, bounds.origin.y + navTotal)
        y = navBarHeight
        let width = bounds.width
        var height = self.readerConfig.isDirection(bounds.height - navTotal, bounds.height - navTotal - paddingTop - paddingBottom, bounds.height - navTotal)
        height = bounds.height - navBarHeight - statusbarHeight
        
        var frame = CGRect(x:x, y:y, width: width, height: height)
        frame = frame.insetBy(
            dx: CGFloat((self.folioReader.currentMarginLeft + self.folioReader.currentMarginRight) / 2),
            dy: CGFloat((self.folioReader.currentMarginTop + self.folioReader.currentMarginBottom) / 2))
        frame = frame.offsetBy(
            dx: CGFloat((self.folioReader.currentMarginLeft - self.folioReader.currentMarginRight) / 2),
            dy: CGFloat((self.folioReader.currentMarginTop - self.folioReader.currentMarginBottom) / 2))
        
        print("Frame \(frame)")
        
        return frame
    }

    func loadHTMLString(_ htmlContent: String!, baseURL: URL!) {
        // Load the html into the webview
        webView?.alpha = 0
        webView?.loadHTMLString(htmlContent, baseURL: baseURL)
        
//        var result = webView?.js("removeOuterTable()")
//        Logger().info("removeOuterTable: \(result ?? "empty")")
//        
//        
//        result = webView?.js("getHTML()")
//        Logger().info("getHTML: \(result ?? "empty")")
    }

    // MARK: - WKNavigation Delegate

    open func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard webView is FolioReaderWebView else {
            return
        }

        delegate?.pageWillLoad?(self)
    }
    
    open func webView(_ webView: WKWebView, didFail: WKNavigation!, withError: Error) {
        self.readerContainer?.alert(message: "LOAD FAIL WITH ERROR \(withError.localizedDescription)")
    }

    open func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let readerCenter = self.folioReader.readerCenter,
              let webView = webView as? FolioReaderWebView,
              let pageNumber = self.pageNumber else {
            return
        }
        
        print("\(#function) bridgeFinished pageNumber=\(String(describing: pageNumber))")
        var preprocessor = ""
        if folioReader.doClearClass {
            preprocessor.append("removeBodyClass();tweakStyleOnly();")
        }
        if folioReader.doWrapPara {
            preprocessor.append("removeOuterTable();reParagraph();removePSpace();")
        }
        
        preprocessor.append("document.body.style.minHeight = null;")
        
        self.webView?.js(preprocessor) {_ in
            guard self.pageNumber == pageNumber else { folioLogger("bridgeFinished pageNumberMisMatch \(pageNumber) vs \(self.pageNumber!)"); return }

            folioLogger("bridgeFinished pageNumber=\(String(describing: self.pageNumber)) size=\(String(describing: self.book.spine.spineReferences[self.pageNumber-1].resource.size))")
            self.updateOverflowStyle(delay: 0.2) {
                guard self.pageNumber == pageNumber else { folioLogger("bridgeFinished pageNumberMisMatch updateOverflowStyle \(pageNumber) vs \(self.pageNumber!)"); return }
                folioLogger("bridgeFinished updateOverflowStyle pageNumber=\(pageNumber)")

                if self.writingMode == "vertical-rl" {
                    self.setNeedsLayout()       //resize webViewFrame
                }
                
                self.updateRuntimStyle(delay: 0.2) {
                    guard self.pageNumber == pageNumber else { folioLogger("bridgeFinished pageNumberMisMatch updateRuntimStyle \(pageNumber) vs \(self.pageNumber!)"); return }

                    folioLogger("bridgeFinished updateRuntimStyle pageNumber=\(pageNumber)")
                    
                    self.injectHighlights() {
                        guard self.pageNumber == pageNumber else { folioLogger("bridgeFinished pageNumberMisMatch injectHighlights \(pageNumber) vs \(self.pageNumber!)"); return }
                        folioLogger("bridgeFinished injectHighlights pageNumber=\(pageNumber)")

                        self.updatePageInfo() {
                            guard self.pageNumber == pageNumber else { folioLogger("bridgeFinished pageNumberMisMatch updatePageInfo \(pageNumber) vs \(self.pageNumber!)"); return }
                            folioLogger("bridgeFinished updatePageInfo pageNumber=\(pageNumber)")

                            self.updateStyleBackgroundPadding(delay: 0.2, tryShrinking: false) {
                                folioLogger("bridgeFinished updateStyleBackgroundPadding pageNumber=\(pageNumber)")
                                
                                guard self.pageNumber == pageNumber else { folioLogger("bridgeFinished pageNumberMisMatch beforeShow \(pageNumber) vs \(self.pageNumber!)"); return }
                                
                                self.layoutAdapting = false
                                webView.isHidden = false
                                
                                self.delegate?.pageDidLoad?(self)
                            }
                        }
                    }
                }
            }
        }
    
        // Add the custom class based onClick listener
        self.setupClassBasedOnClickListeners()

        refreshPageMode()

        if self.readerConfig.enableTTS && !self.book.hasAudio {
            webView.js("wrappingSentencesWithinPTags()")

            if let audioPlayer = self.folioReader.readerAudioPlayer, (audioPlayer.isPlaying() == true) {
                audioPlayer.readCurrentSentence()
            }
        }

        let direction: ScrollDirection = self.folioReader.needsRTLChange ? .positive(withConfiguration: self.readerConfig) : .negative(withConfiguration: self.readerConfig)

//        For what purpose?
//        if (self.folioReader.readerCenter?.pageScrollDirection == direction &&
//            self.folioReader.readerCenter?.isScrolling == true &&
//            self.readerConfig.scrollDirection != .horizontalWithVerticalContent) {
//            scrollPageToBottom()
//        }

        UIView.animate(withDuration: 0.2, animations: {webView.alpha = 1}, completion: { finished in
            webView.isColors = false
            self.webView?.createMenu(onHighlight: false)
        })
//        webView.js("document.readyState") { _ in
//            self.delegate?.pageDidLoad?(self)
//        }
        
        let overlayColor = readerConfig.mediaOverlayColor!
        let colors = "\"\(overlayColor.hexString(false))\", \"\(overlayColor.highlightColor().hexString(false))\""
        webView.js("setMediaOverlayStyleColors(\(colors))")
    }

    func updatePageInfo(completion: (() -> Void)? = nil) {
        if readerConfig.debug.contains(.functionTrace) {
            folioLogger("ENTER");
        }

        self.webView?.js("getReadingTime(\"\(book.metadata.language)\")") { readingTime in
            self.totalMinutes = Int(readingTime ?? "0") ?? 0
            
            self.updatePageIdOffsets {
                self.updatePages()
                
                defer {
                    completion?()
                }
                guard let readerCenter = self.folioReader.readerCenter,
                      readerCenter.currentPageNumber == self.pageNumber else { return }
                
                readerCenter.scrollScrubber?.setSliderVal()
                readerCenter.delegate?.pageDidAppear?(self)
                readerCenter.delegate?.pageItemChanged?(self.currentPage)
            }
        }
    }
    
    func updatePageIdOffsets(completion: (() -> Void)? = nil) {
        let isHorizontal: Bool = self.folioReader.readerConfig?.isDirection(false, true, false) ?? false
        self.webView?.js("getOffsetsOfElementsWithID(\(isHorizontal))") { result in
            defer {
                completion?()
            }
            
            guard let data = result?.data(using: .utf8),
                  let offsets = try? JSONDecoder().decode([String:Int].self, from: data) else { return }
            
            //print("\(#function) \(offsets)")
            self.idOffsets = offsets
        }
    }
    
    func updatePages() {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        guard let readerCenter = self.folioReader.readerCenter, let webView = self.webView else { return }

        let pageSize = self.byWritingMode(
            self.readerConfig.isDirection(readerCenter.pageHeight, readerCenter.pageWidth, readerCenter.pageHeight),
            webView.frame.width
        )
        let contentSize = self.byWritingMode(
            webView.scrollView.contentSize.forDirection(withConfiguration: self.readerConfig),
            webView.scrollView.contentSize.width
        )
        self.totalPages = ((pageSize != 0) ? Int(ceil(contentSize / pageSize)) : 0)
        
        let pageOffSet = self.byWritingMode(
            webView.scrollView.contentOffset.forDirection(withConfiguration: self.readerConfig),
            webView.scrollView.contentOffset.x //+ webView.frame.width
        )
        
        folioLogger("updatePages pageNumber=\(self.pageNumber!) totalPages=\(self.totalPages!) contentSize=\(contentSize) pageSize=\(pageSize)")
//        if self.byWritingMode(pageOffSet + pageSize <= contentSize, pageOffSet >= 0) {
        self.currentPage = readerCenter.pageForOffset(pageOffSet, pageHeight: pageSize)
            
//        if (self.readerConfig.scrollDirection == .horizontalWithVerticalContent) {
        let currentIndexPathRow = (self.pageNumber - 1)
            
            // if the cell reload doesn't save the top position offset
//            if let oldOffSet = readerCenter.currentWebViewScrollPositions[currentIndexPathRow], (abs((oldOffSet["pageOffsetY"] as? CGFloat ?? 0) - webView.scrollView.contentOffset.y) > 100) {
//                // Do nothing
//                // MARK: - FIXME
//            } else {
        guard !(webView.isHidden || layoutAdapting) else { return }
        getWebViewScrollPosition { position in
            readerCenter.currentWebViewScrollPositions[currentIndexPathRow] = position
        }
//            }
//        }
            
//        }
    }
    
    func getWebViewScrollPosition(completion: ((_ position: [String: Any]) -> Void)? = nil) {
        guard let webView = webView else {
            return
        }

        webView.js("getVisibleCFI()") { cfi in
            let position: [String : Any] = [
                "pageNumber": self.pageNumber ?? 0,
                "maxPage": self.readerContainer?.book.spine.spineReferences.count ?? 1,
                "pageOffsetX": webView.scrollView.contentOffset.x,
                "pageOffsetY": webView.scrollView.contentOffset.y,
                "chapterProgress": CGFloat(self.getPageProgress()),
                "chapterName": self.currentChapterName ?? "Untitled Chapter",
                "bookProgress": self.folioReader.readerCenter?.getBookProgress() ?? 0,
                "cfi": "/\((self.pageNumber ?? 0) * 2)\(cfi ?? "")"
                ]

            completion?(position)
        }
    }
    
    func getPageProgress() -> Double {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        guard let readerCenter = self.folioReader.readerCenter,
              let webView = webView else {
            return 0
        }
        
        let pageSize = self.byWritingMode(
            self.readerConfig.isDirection(readerCenter.pageHeight, readerCenter.pageWidth, readerCenter.pageHeight),
            webView.frame.width
        )
        let contentSize = self.byWritingMode(
            webView.scrollView.contentSize.forDirection(withConfiguration: self.readerConfig),
            webView.scrollView.contentSize.width
        )
        let totalPages = ((pageSize != 0) ? Int(ceil(contentSize / pageSize)) : 0)
        let currentPageItem = currentPage
        
        if totalPages > 0 {
            var progress = self.byWritingMode(
                Double(currentPageItem - 1) * 100.0 / Double(totalPages),
                100.0 - Double(currentPageItem) * 100.0 / Double(totalPages)
            )
            
            if progress < 0 { progress = 0 }
            if progress > 100 { progress = 100 }
            
            return progress
        }
        
        return 0
    }

    /// Get internal page offset before layout change.
    /// Represent upper-left point regardless of layout
    open func updatePageOffsetRate() {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        guard let webView = self.webView else { return }

        let pageScrollView = webView.scrollView
        let contentSize = byWritingMode(
            pageScrollView.contentSize.forDirection(withConfiguration: self.readerConfig),
            pageScrollView.contentSize.width
        )
        let contentOffset = byWritingMode(
            pageScrollView.contentOffset.forDirection(withConfiguration: self.readerConfig),
            pageScrollView.contentOffset.x
        )
        self.pageOffsetRate = (contentSize != 0 ? (contentOffset / contentSize) : 0)
    }

    open func updateScrollPosition(delay bySecond: Double = 0.1, completion: (() -> Void)?) {
        // After rotation fix internal page offset
        
//        self.updatePageOffsetRate()
        if self.pageOffsetRate > 0 {
            delay(bySecond) {
                self.scrollWebViewByPageOffsetRate()
                self.updatePageOffsetRate()
                completion?()
            }
        } else {
            completion?()
        }
    }
    
    open func scrollWebViewByPageOffsetRate(animated: Bool = true) {
        guard let webViewFrameSize = webView?.frame.size,
              webViewFrameSize.width > 0, webViewFrameSize.height > 0,
              let contentSize = webView?.scrollView.contentSize else { return }
        
        var pageOffset = byWritingMode(
            contentSize.forDirection(withConfiguration: self.readerConfig),
            contentSize.width
        ) * self.pageOffsetRate
        
        // Fix the offset for paged scroll
        if byWritingMode(self.readerConfig.scrollDirection == .horitonzalWithPagedContent, true) {
            let page = byWritingMode(
                floor( pageOffset / webViewFrameSize.width ),
                max(floor( (contentSize.width - pageOffset) / webViewFrameSize.width), 1)
            )
            pageOffset = byWritingMode(page * webViewFrameSize.width, contentSize.width - page * webViewFrameSize.width)
        }
        
        scrollPageToOffset(pageOffset, animated: animated, retry: 0)
    }
    
    open func setScrollViewContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        folioLogger("pageNumber=\(pageNumber!) contentOffset=\(contentOffset)")
        webView?.scrollView.setContentOffset(contentOffset, animated: animated)
//        if self.readerConfig.scrollDirection == .horizontalWithVerticalContent {
            let currentIndexPathRow = pageNumber - 1
            self.getWebViewScrollPosition { position in
                self.folioReader.readerCenter?.currentWebViewScrollPositions[currentIndexPathRow] = position
            }
//        }
    }
    
    open func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let handledAction = handlePolicy(for: navigationAction)
        let policy: WKNavigationActionPolicy = handledAction ? .allow : .cancel
        decisionHandler(policy)
    }

    // MARK: Change layout orientation
    func setScrollDirection(_ direction: FolioReaderScrollDirection) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        guard let readerCenter = self.folioReader.readerCenter, let webView = webView else { return }
        let currentPageNumber = readerCenter.currentPageNumber
        
        self.layoutAdapting = true

        // Get internal page offset before layout change
        self.updatePageOffsetRate()
        
        // Change layout
        self.readerConfig.scrollDirection = direction
        readerCenter.collectionViewLayout.scrollDirection = .direction(withConfiguration: self.readerConfig)
        self.setNeedsLayout()
        readerCenter.collectionView.collectionViewLayout.invalidateLayout()
        let frameForPage = readerCenter.frameForPage(currentPageNumber)
        readerCenter.collectionView.setContentOffset(frameForPage.origin, animated: false)

        // Page progressive direction
        readerCenter.setCollectionViewProgressiveDirection()
        delay(0.2) { readerCenter.setPageProgressiveDirection(self) }

        /**
         *  This delay is needed because the page will not be ready yet
         *  so the delay wait until layout finished the changes.
         */
        
        delay(delaySec()) {
            webView.setupScrollDirection()
            self.updateOverflowStyle(delay: self.delaySec()) {
                self.scrollWebViewByPageOffsetRate(animated: false)
                
                delay(self.delaySec() + 0.2) {
                    self.updatePageInfo() {
                        self.updateScrollPosition(delay: self.delaySec()) {
                            self.updateStyleBackgroundPadding(delay: self.delaySec()) {
                                self.layoutAdapting = false
                            }
                        }
                    }
                }
            }
        }
    }

    func updateOverflowStyle(delay bySecond: Double, completion: (() -> Void)? = nil) {
        guard let readerCenter = self.folioReader.readerCenter, let webView = webView else { return }
        
        self.layoutAdapting = true
        
        webView.js(
"""
writingMode = window.getComputedStyle(document.body).getPropertyValue("writing-mode")

{
    var viewport = document.querySelector("meta[name=viewport]");
    if (viewport) {
        if (writingMode == "vertical-rl") {
            viewport.setAttribute('content', 'height=device-height, initial-scale=1.0, maximum-scale=1.0, user-scalable=0');
        } else {
            viewport.setAttribute('content', 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=0');
        }
    } else {
        var metaTag=document.createElement('meta');
        metaTag.name = "viewport"
        if (writingMode == "vertical-rl") {
            metaTag.content = "height=device-height, initial-scale=1.0, maximum-scale=1.0, user-scalable=0"
        } else {
            metaTag.content = "width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=0"
        }
        document.head.appendChild(metaTag);
    }
}

{
    var overflow = "\(webView.cssOverflowProperty)"
    var head = document.head
    var style = document.getElementById("folio_style_overflow")
    if (style == null) {
        style = document.createElement('style')
        style.type = "text/css"
        style.id = "folio_style_overflow"
        head.appendChild(style)
    }
    while (style.firstChild) {
        style.removeChild(style.firstChild)
    }
    
    var cssText = "html { overflow: " + overflow + " !important; display: block !important; text-align: justify !important;}"
    if (overflow == "-webkit-paged-x") {
        if (writingMode == "vertical-rl") {
            cssText += " body { min-width: 100vw; margin: 0 0 !important; }"
        } else {
            cssText += " body { min-height: 100vh; margin: 0 0 !important; }"
        }
    }
    style.appendChild( document.createTextNode(cssText) )

    document.body.style.minHeight = null;
    document.body.style.minWidth = null;
}
/*window.webkit.messageHandlers.FolioReaderPage.postMessage("bridgeFinished " + getHTML())*/

writingMode
"""
        ) { writingMode in
            if let writingMode = writingMode {
                self.writingMode = writingMode
            }
            delay(bySecond) {
                self.layoutAdapting = false
                completion?()
            }
        }
    }
    
    func updateRuntimStyle(delay bySecond: Double, completion: (() -> Void)? = nil) {
        guard let readerCenter = self.folioReader.readerCenter, let webView = webView else { return }

        self.layoutAdapting = true
        self.updatePageOffsetRate()
        webView.js(
"""
{
    themeMode(\(folioReader.themeMode))

    var styleOverride = \(folioReader.styleOverride.rawValue)

    removeClasses(document.body, 'folioStyle\\\\w+')
    if (writingMode == 'vertical-rl') {
        addClass(document.body, 'folioStyleBodyPaddingTop\(folioReader.currentMarginTop/5)')
        addClass(document.body, 'folioStyleBodyPaddingBottom\(folioReader.currentMarginBottom/5)')
        document.body.style.minWidth = "100vw";
    } else {
        addClass(document.body, 'folioStyleBodyPaddingLeft\(folioReader.currentMarginLeft/5)')
        addClass(document.body, 'folioStyleBodyPaddingRight\(folioReader.currentMarginRight/5)')
        document.body.style.minHeight = "100vh";
    }
    while (styleOverride > 0) {
        var folioStyleLevel = 'folioStyleL' + styleOverride
        addClass(document.body, folioStyleLevel + 'FontFamily\(folioReader.currentFont.replacingOccurrences(of: " ", with: "_"))')
        addClass(document.body, folioStyleLevel + 'FontSize\(folioReader.currentFontSize.replacingOccurrences(of: ".", with: ""))')
        addClass(document.body, folioStyleLevel + 'FontWeight\(folioReader.currentFontWeight)')
        addClass(document.body, folioStyleLevel + 'LetterSpacing\(folioReader.currentLetterSpacing)')
        addClass(document.body, folioStyleLevel + 'LineHeight\(folioReader.currentLineHeight)')
        if (writingMode == 'vertical-rl') {
            addClass(document.body, folioStyleLevel + 'MarginV\(folioReader.currentLineHeight)')
        } else {
            addClass(document.body, folioStyleLevel + 'MarginH\(folioReader.currentLineHeight)')
        }
        addClass(document.body, folioStyleLevel + 'TextIndent\(folioReader.currentTextIndent+4)')
        styleOverride -= 1
    }
}

window.webkit.messageHandlers.FolioReaderPage.postMessage("bridgeFinished " + getHTML())

window.webkit.messageHandlers.FolioReaderPage.postMessage("getComputedStyle document.documentElement " + window.getComputedStyle(document.documentElement).cssText)
window.webkit.messageHandlers.FolioReaderPage.postMessage("getComputedStyle document.body" + window.getComputedStyle(document.body).cssText)

window.webkit.messageHandlers.FolioReaderPage.postMessage("writingMode " + writingMode)

writingMode
"""
        ) { _ in
            let delaySec = self.delaySec() + bySecond
            delay(delaySec) {
                self.updatePageInfo {
                    delay(delaySec) {
                        self.updateStyleBackgroundPadding(delay: delaySec, completion: completion != nil ? completion : {
                            self.updatePageInfo() {
                                self.scrollWebViewByPageOffsetRate()
                                delay(delaySec) {
                                    self.updatePageOffsetRate()
                                    self.layoutAdapting = false
                                    self.updatePageInfo()
                                }
                            }
                        })
                    }
                }
            }
        }
    }
    
    func updateStyleBackgroundPadding(delay bySecond: Double, tryShrinking: Bool = true, completion: (() -> Void)? = nil) {
        var minScreenCount = 1
        if self.byWritingMode(self.readerConfig.scrollDirection == .horitonzalWithPagedContent, true) {
            minScreenCount = self.totalPages ?? minScreenCount
            if minScreenCount < 1 {
                minScreenCount = 1
            }
        }
        
        // must set width instead of minWidth, otherwise there will be an extra blank page after calling scrollView.setContentOffset
        // could be a bug?
        // and shrinking by 100vw has no effect on totalPages
        self.webView?.js(
            """
            if (writingMode == 'vertical-rl') {
                document.body.style.width     = "\(minScreenCount * 100 - (tryShrinking ? 200 : 0))vw"
            } else {
                document.body.style.minHeight = "\(minScreenCount * 100 - (tryShrinking ? 100 : 0))vh"
            }
            """
        ) { _ in
            delay(bySecond) {
                self.updatePageInfo {
                    folioLogger("updateStyleBackgroundPadding pageNumber=\(self.pageNumber!) minScreenCount=\(minScreenCount) totalPages=\(self.totalPages ?? 0) tryShrinking=\(tryShrinking)")
                    if self.byWritingMode(self.readerConfig.scrollDirection == .horitonzalWithPagedContent, true) {
                        if tryShrinking {
                            if self.totalPages < minScreenCount {   //shrinked one page, try again
                                self.updateStyleBackgroundPadding(delay: bySecond, tryShrinking: true, completion: completion)
                            } else {  //stop shrinking
                                self.updateStyleBackgroundPadding(delay: bySecond, tryShrinking: false, completion: completion)
                            }
                        } else {
                            if self.totalPages > minScreenCount {
                                self.updateStyleBackgroundPadding(delay: bySecond, tryShrinking: true, completion: completion)
                            } else if self.totalPages < minScreenCount {
                                self.updateStyleBackgroundPadding(delay: bySecond, tryShrinking: false, completion: completion)
                            } else {
                                completion?()
                            }
                        }
                    } else {
                        completion?()
                    }
                }
            }
        }
    }
    
    func updateViewerLayout(delay bySecond: Double) {
        guard let readerCenter = self.folioReader.readerCenter else { return }
        
        self.layoutAdapting = true
        self.updatePageOffsetRate()
        
        webView?.js(
        """
            document.body.style.minHeight = null;
            document.body.style.minWidth = null;
        """) { _ in
            self.setNeedsLayout()
            
            delay(self.delaySec() + bySecond) {
                self.updatePageInfo {
                    self.updateStyleBackgroundPadding(delay: self.delaySec()) {
                        self.scrollWebViewByPageOffsetRate()
                        delay(0.2) {
                            self.updatePageOffsetRate()
                            self.layoutAdapting = false
                            self.updatePageInfo()
                        }
                    }
                }
            }
            
//            self.updateScrollPosition(delay: bySecond) {
//                self.updatePageInfo {
//                    self.updateStyleBackgroundPadding(delay: bySecond) {
//                        self.layoutAdapting = false
//                    }
//                }
//            }
        }
    }
    
    private func handlePolicy(for navigationAction: WKNavigationAction) -> Bool {
        let request = navigationAction.request
        
        guard
            let webView = webView,
            let scheme = request.url?.scheme else {
                return true
        }

        guard let url = request.url else { return false }

        if scheme == "highlight" || scheme == "highlight-with-note" {
            shouldShowBar = false

            guard let decoded = url.absoluteString.removingPercentEncoding else { return false }
            let index = decoded.index(decoded.startIndex, offsetBy: 12)
            let rect = NSCoder.cgRect(for: String(decoded[index...]))

            webView.createMenu(onHighlight: true)
            webView.setMenuVisible(true, andRect: rect)
            menuIsVisible = true

            return false
        } else if scheme == "play-audio" {
            guard let decoded = url.absoluteString.removingPercentEncoding else { return false }
            let index = decoded.index(decoded.startIndex, offsetBy: 13)
            let playID = String(decoded[index...])
            let chapter = self.folioReader.readerCenter?.getCurrentChapter()
            let href = chapter?.href ?? ""
            self.folioReader.readerAudioPlayer?.playAudio(href, fragmentID: playID)

            return false
        } else if scheme == "file" || (url.scheme == "http" && url.host == "localhost" && (url.port ?? 0) == readerConfig.serverPort) {
            
            if navigationAction.navigationType == .linkActivated,
                let currentPageNumber = self.pageNumber,
                let currentOffset = self.webView?.scrollView.contentOffset {
                self.folioReader.readerCenter?.navigateWebViewScrollPositions.append((currentPageNumber, currentOffset))
                self.folioReader.readerCenter?.navigationItem.leftBarButtonItems?[2].isEnabled = true
            }
            
            guard let anchorFromURL = url.fragment else { return true }

            // Handle internal url
            if !url.pathExtension.isEmpty {
                let pathComponent = (self.book.opfResource.href as NSString?)?.deletingLastPathComponent
                guard let base = ((pathComponent == nil || pathComponent?.isEmpty == true) ? self.book.name : pathComponent)?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                    return true
                }

                let path = url.path
                let splitedPath = path.components(separatedBy: base)

                // Return to avoid crash
                if (splitedPath.count <= 1 || splitedPath[1].isEmpty) {
                    return true
                }

                let href = splitedPath[1].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let hrefPage = (self.folioReader.readerCenter?.findPageByHref(href) ?? 0) + 1

                if (hrefPage == pageNumber) {
                    // Handle internal #anchor
                    self.webView?.js("getClickAnchorOffset('\(anchorFromURL)')") { offset in
                        print("getClickAnchorOffset offset=\(offset ?? "0")")
                        self.handleAnchor(anchorFromURL, offsetInWindow: CGFloat(truncating: NumberFormatter().number(from: offset ?? "0") ?? 0), avoidBeginningAnchors: false, animated: false)
                        
                    }
                } else {
                    // self.folioReader.readerCenter?.tempFragment = anchorFromURL
                    self.folioReader.readerCenter?.currentWebViewScrollPositions.removeValue(forKey: hrefPage - 1)
                    self.webView?.js("getClickAnchorOffset('\(anchorFromURL)')") { offset in
                        print("getClickAnchorOffset offset=\(offset ?? "0")")
                        self.folioReader.readerCenter?.changePageWith(href: href, animated: true) {
                            delay(0.2) {
                                guard self.folioReader.readerCenter?.currentPageNumber == hrefPage else { return }
                                self.folioReader.readerCenter?.currentPage?.waitForLayoutFinish {
                                    self.folioReader.readerCenter?.currentPage?.handleAnchor(anchorFromURL, offsetInWindow: CGFloat(truncating: NumberFormatter().number(from: offset ?? "0") ?? 0), avoidBeginningAnchors: false, animated: true)
                                }
                            }
                        }
                    }
                }
                return false
            }

            // Handle internal #anchor
            self.webView?.js("getClickAnchorOffset('\(anchorFromURL)')") { offset in
                print("getClickAnchorOffset offset=\(offset ?? "0")")
                self.handleAnchor(anchorFromURL, offsetInWindow: CGFloat(truncating: NumberFormatter().number(from: offset ?? "0") ?? 0), avoidBeginningAnchors: false, animated: false)
            }
            return false
        } else if scheme == "mailto" {
            print("Email")
            return true
        } else if url.absoluteString != "about:blank" && scheme.contains("http") && navigationAction.navigationType == .linkActivated {
            let safariVC = SFSafariViewController(url: request.url!)
            safariVC.view.tintColor = self.readerConfig.tintColor
            self.folioReader.readerCenter?.present(safariVC, animated: true, completion: nil)
            return false
        } else {
            // Check if the url is a custom class based onClick listerner
            var isClassBasedOnClickListenerScheme = false
            for listener in self.readerConfig.classBasedOnClickListeners {

                if scheme == listener.schemeName,
                    let absoluteURLString = request.url?.absoluteString,
                    let range = absoluteURLString.range(of: "/clientX=") {
                    let baseURL = String(absoluteURLString[..<range.lowerBound])
                    let positionString = String(absoluteURLString[range.lowerBound...])
                    if let point = getEventTouchPoint(fromPositionParameterString: positionString) {
                        let attributeContentString = (baseURL.replacingOccurrences(of: "\(scheme)://", with: "").removingPercentEncoding)
                        // Call the on click action block
                        listener.onClickAction(attributeContentString, point)
                        // Mark the scheme as class based click listener scheme
                        isClassBasedOnClickListenerScheme = true
                    }
                }
            }

            if isClassBasedOnClickListenerScheme == false {
                // Try to open the url with the system if it wasn't a custom class based click listener
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                    return false
                }
            } else {
                return false
            }
        }

        return true
    }

    fileprivate func getEventTouchPoint(fromPositionParameterString positionParameterString: String) -> CGPoint? {
        // Remove the parameter names: "/clientX=188&clientY=292" -> "188&292"
        var positionParameterString = positionParameterString.replacingOccurrences(of: "/clientX=", with: "")
        positionParameterString = positionParameterString.replacingOccurrences(of: "clientY=", with: "")
        // Separate both position values into an array: "188&292" -> [188],[292]
        let positionStringValues = positionParameterString.components(separatedBy: "&")
        // Multiply the raw positions with the screen scale and return them as CGPoint
        if
            positionStringValues.count == 2,
            let xPos = Int(positionStringValues[0]),
            let yPos = Int(positionStringValues[1]) {
            return CGPoint(x: xPos, y: yPos)
        }
        return nil
    }

    // MARK: WKScriptMessageHandler
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        //This function handles the events coming from javascript. We'll configure the javascript side of this later.
        //We can access properties through the message body, like this:
        guard let response = message.body as? String else { return }
        if self.readerConfig.debug.contains(.htmlStyling) {
            print("userContentController response\n\(response)")
        }
        if response.starts(with: "bridgeFinished") {
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent(self.book.spine.spineReferences[self.pageNumber-1].resource.href.lastPathComponent)
            print("\(#function) tempDir=\(tempDir.absoluteString) tempFile=\(tempFile.absoluteString)")
            try? FileManager.default.removeItem(atPath: tempFile.path)
            FileManager.default.createFile(atPath: tempFile.path, contents: response.suffix(response.count - "bridgeFinished ".count).data(using: .utf8), attributes: nil)
        }
    }
    
    func injectHighlights(completion: (() -> Void)? = nil) {
        guard let bookId = (self.book.name as NSString?)?.deletingPathExtension,
              let highlights = self.folioReader.delegate?.folioReaderHighlightProvider?(self.folioReader).folioReaderHighlight(self.folioReader, allByBookId: bookId, andPage: pageNumber as NSNumber?),
              highlights.isEmpty == false
        else {
            completion?()
            return
        }
        let encodedData = ((try? JSONEncoder().encode(highlights)) ?? .init()).base64EncodedString()
        
        self.webView?.js("injectHighlights('\(encodedData)')") {_ in
            completion?()
        }
    }
    
    // MARK: Gesture recognizer

    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer.view is FolioReaderWebView {
            if otherGestureRecognizer is UILongPressGestureRecognizer || otherGestureRecognizer is UITapGestureRecognizer {
                if UIMenuController.shared.isMenuVisible {
                    webView?.setMenuVisible(false)
                }
                return false
            }
            return true
        }
        return false
    }

    @objc open func handleTapGesture(_ recognizer: UITapGestureRecognizer) {
        self.delegate?.pageTap?(recognizer)
        
        if let _navigationController = self.folioReader.readerCenter?.navigationController, (_navigationController.isNavigationBarHidden == true) {
            webView?.js("getSelectedText()") { selected in
                guard (selected == nil || selected?.isEmpty == true) else {
                    return
                }
            
                let delay = 0.4 * Double(NSEC_PER_SEC) // 0.4 seconds * nanoseconds per seconds
                let dispatchTime = (DispatchTime.now() + (Double(Int64(delay)) / Double(NSEC_PER_SEC)))
                
                DispatchQueue.main.asyncAfter(deadline: dispatchTime, execute: {
                    if (self.shouldShowBar == true && self.menuIsVisible == false) {
                        self.folioReader.readerCenter?.toggleBars()
                    }
                })
            }
        } else if (self.readerConfig.shouldHideNavigationOnTap == true) {
            self.folioReader.readerCenter?.hideBars()
            self.menuIsVisible = false
        }
    }

    // MARK: - Public scroll postion setter

    /**
     Scrolls the page to a given offset

     - parameter offset:   The offset to scroll
     - parameter animated: Enable or not scrolling animation
     */
    open func scrollPageToOffset(_ offset: CGFloat, animated: Bool, retry: Int = 5, completion: (() -> Void)? = nil) {
        guard let webView = webView else {
            return
        }

        let pageOffsetPoint = byWritingMode(
            self.readerConfig.isDirection(CGPoint(x: 0, y: offset), CGPoint(x: offset, y: 0), CGPoint(x: 0, y: offset)),
            CGPoint(x: offset, y: 0)
        )
        setScrollViewContentOffset(pageOffsetPoint, animated: animated)
        
        if retry > 0 {
            delay(0.1 * Double(retry)) {
                if pageOffsetPoint != webView.scrollView.contentOffset {
                    self.scrollPageToOffset(offset, animated: animated, retry: retry - 1, completion: completion)
                } else {
                    completion?()
                }
            }
        } else {
            completion?()
        }
    }

    /**
     Scrolls the page to bottom
     */
    open func scrollPageToBottom() {
        guard let webView = webView else { return }
        let bottomOffset = self.readerConfig.isDirection(
            CGPoint(x: 0, y: webView.scrollView.contentSize.height - webView.scrollView.bounds.height),
            CGPoint(x: webView.scrollView.contentSize.width - webView.scrollView.bounds.width, y: 0),
            CGPoint(x: webView.scrollView.contentSize.width - webView.scrollView.bounds.width, y: 0)
        )

        if bottomOffset.forDirection(withConfiguration: self.readerConfig) >= 0 {
            DispatchQueue.main.async {
                self.setScrollViewContentOffset(bottomOffset, animated: false)
            }
        }
    }

    /**
     Handdle #anchors in html, get the offset and scroll to it

     - parameter anchor:                The #anchor
     - parameter avoidBeginningAnchors: Sometimes the anchor is on the beggining of the text, there is not need to scroll
     - parameter animated:              Enable or not scrolling animation
     */
    open func handleAnchor(_ anchor: String, offsetInWindow: CGFloat, avoidBeginningAnchors: Bool, animated: Bool) {
        guard !anchor.isEmpty else { return }
        
        guard let webView = webView, webView.isHidden == false, self.layoutAdapting == false else {
            delay(0.1) {
                self.handleAnchor(anchor, offsetInWindow: offsetInWindow, avoidBeginningAnchors: avoidBeginningAnchors, animated: animated)
            }
            return
        }
        
        getAnchorOffset(anchor) { offset in
            self.byWritingMode {
                switch self.readerConfig.scrollDirection {
                case .horitonzalWithPagedContent:
                    self.scrollPageToOffset(offset, animated: animated)
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
                case .horitonzalWithPagedContent:
                    let page = ceil((webView.scrollView.contentSize.width - offset) / webView.frame.width)
                    self.scrollPageToOffset(webView.scrollView.contentSize.width - page * webView.frame.width, animated: true)
                default:
                    self.scrollPageToOffset(offset + webView.frame.width, animated: animated)
                }
            }

            
            
            self.folioReader.readerCenter?.currentWebViewScrollPositions.removeValue(forKey: self.pageNumber - 1)
            
            self.webView?.js("highlightAnchorText('\(anchor)', 'highlight-yellow', 3)")
        }
    }

    // MARK: Helper

    /**
     Get the #anchor offset in the page

     - parameter anchor: The #anchor id
     - returns: The element offset ready to scroll
     */
    func getAnchorOffset(_ anchor: String, completion: @escaping ((CGFloat) -> ())) {
        let horizontal = self.readerConfig.scrollDirection == .horitonzalWithPagedContent
        self.webView?.js("getAnchorOffset(\"\(anchor)\", \(horizontal.description))") { strOffset in
            guard let strOffset = strOffset else {
                completion(CGFloat(0))
                return
            }
            completion(CGFloat((strOffset as NSString).floatValue))
        }
    }

    // MARK: Mark ID

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

    // MARK: UIMenu visibility

    override open func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard let webView = webView else { return false }

        if UIMenuController.shared.menuItems?.count == 0 {
            webView.isColors = false
            webView.createMenu(onHighlight: false)
        }

        return super.canPerformAction(action, withSender: sender)
    }

    // MARK: ColorView fix for horizontal layout
    @objc func refreshPageMode() {
        guard webView != nil else { return }

        if (self.folioReader.nightMode == true) {
            // omit create webView and colorView
            // let script = "document.documentElement.offsetHeight"
            // let contentHeight = webView.stringByEvaluatingJavaScript(from: script)
            // let frameHeight = webView.frame.height
            // let lastPageHeight = frameHeight * CGFloat(webView.pageCount) - CGFloat(Double(contentHeight!)!)
            // colorView.frame = CGRect(x: webView.frame.width * CGFloat(webView.pageCount-1), y: webView.frame.height - lastPageHeight, width: webView.frame.width, height: lastPageHeight)
            colorView.frame = CGRect.zero
        } else {
            colorView.frame = CGRect.zero
        }
    }
    
    // MARK: - Class based click listener
    
    fileprivate func setupClassBasedOnClickListeners() {
        for listener in self.readerConfig.classBasedOnClickListeners {
            self.webView?.js("addClassBasedOnClickListener(\"\(listener.schemeName)\", \"\(listener.querySelector)\", \"\(listener.attributeName)\", \"\(listener.selectAll)\")")
        }
    }
    
    // MARK: - Deadzone Pan Gesture
    open override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer.view == panDeadZoneTop || gestureRecognizer.view == panDeadZoneBot || gestureRecognizer.view == panDeadZoneLeft || gestureRecognizer.view == panDeadZoneRight {
            return true
        }
        return false
    }
    
}

extension FolioReaderPage {
    func byWritingMode<T> (_ horizontal: T, _ vertical: T) -> T {
        if writingMode == "vertical-rl" {
            return vertical
        } else {
            return horizontal
        }
    }
    
    func byWritingMode (horizontal: () -> Void, vertical: () -> Void) {
        if writingMode == "vertical-rl" {
            vertical()
        } else {
            horizontal()
        }
    }
    
    func waitForLayoutFinish(completion: @escaping () -> Void, retry: Int = 99) {
        if layoutAdapting, retry > 0 {
            delay(0.1) {
                self.waitForLayoutFinish(completion: completion, retry: retry - 1)
            }
        } else {
            completion()
        }
    }
    
    func delaySec(_ max: Double = 1.0) -> Double {
        let fileSize = self.book.spine.spineReferences[safe: pageNumber-1]?.resource.size ?? 102400
        let delaySec = min(0.2 + 0.2 * Double(fileSize / 51200), max)
        return delaySec
    }
}
