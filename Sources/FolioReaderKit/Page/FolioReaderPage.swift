//
//  FolioReaderPage.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 10/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import FolioEPUBCore
import SafariServices
import MenuItemKit
import OSLog
import WebKit

open class FolioReaderPage: UICollectionViewCell, WKNavigationDelegate, UIGestureRecognizerDelegate, EpubJSBridgeDelegate {
    weak var delegate: FolioReaderPageDelegate?
    weak var readerContainer: FolioReaderContainer?

    lazy var jsBridge: EpubJSBridge = {
        let bridge = EpubJSBridge()
        bridge.delegate = self
        return bridge
    }()

    /// The index of the current page. Note: The index start at 1!
    open var pageNumber: Int = -1 {
        didSet {
            self.pageChapterTocReferences = self.folioReader.readerCenter?.getChapterNames(pageNumber: self.pageNumber)
        }
    }
    open var webView: FolioReaderWebView?
    open var panDeadZoneTop: UIView?
    open var panDeadZoneBot: UIView?
    open var panDeadZoneLeft: UIView?
    open var panDeadZoneRight: UIView?
    
    var activityView: FolioReaderPageActivity?
    
    open var writingMode = "horizontal-tb"
    
    open var pageOffsetRate: CGFloat = 0 {
        didSet {
            FolioLogger.log("SET pageOffsetRate=\(pageOffsetRate) pageNumber=\(pageNumber) currentPage=\(currentPage) totalPages=\(totalPages ?? -1)")
        }
    }

    var totalMinutes: Int?
    var totalPages: Int?
    var currentPage: Int = -1 {
        didSet {
            guard currentPage != oldValue, currentPage >= 0 else { return }
            
            updateCurrentChapterName()
            
            guard layoutAdapting == nil else { return }       //FIXME: prevent overriding last known good position
            
            getAndRecordScrollPosition()
        }
    }
    var currentChapterName: String?
    var pageChapterTocReferences: [FRTocReference]?
    var idOffsets: [String: Int]?
    
    var colorView: UIView?
    var tapStartLocation: CGPoint?
    var tapStartPageNumber: Int?
    var tapStartedWhileScrolling = false
    var menuIsVisible = false
    var firstLoadReloaded = false
    
    static var cachedStatusBarHeight: CGFloat = 0
    var statusbarHeight: CGFloat {
        // 1. Fast path: Use window insets (available 99% of the time during layout)
        if let safeTop = self.window?.safeAreaInsets.top, safeTop > 0 {
            FolioReaderPage.cachedStatusBarHeight = safeTop
            return safeTop
        }
        
        // 2. Medium path: Use own insets
        if self.safeAreaInsets.top > 0 {
            FolioReaderPage.cachedStatusBarHeight = self.safeAreaInsets.top
            return self.safeAreaInsets.top
        }
        
        // 3. Fallback to cache or simple status bar frame (only for very early layout)
        if FolioReaderPage.cachedStatusBarHeight > 0 {
            return FolioReaderPage.cachedStatusBarHeight
        }
        
        return self.window?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0
    }
    
     var layoutAdapting: String? = nil {
        didSet {
            if let layoutAdapting = layoutAdapting {
                if pageNumber != 1 {
                    if activityView?.adView == nil {
                        activityView?.adView = self.folioReader.delegate?.folioReaderAdView?(self.folioReader)
                    }
                    
                    activityView?.activate(layoutAdapting, activityView?.adView != nil)
                    
                } else {
                    activityView?.activate(layoutAdapting, false)
                }
            } else {
                activityView?.deactivate()
            }
            
        }
    }
    var readerConfig: FolioReaderConfig {
        guard let readerContainer = readerContainer else { return FolioReaderConfig() }
        return readerContainer.readerConfig
    }

    var book: FRBook {
        guard let readerContainer = readerContainer else { return FRBook() }
        return readerContainer.book
    }

    var folioReader: FolioReader {
        guard let readerContainer = readerContainer else { return FolioReader() }
        return readerContainer.folioReader
    }

    // MARK: - View life cicle

    public override init(frame: CGRect) {
        // Init explicit attributes with a default value. The `setup` function MUST be called to configure the current object with valid attributes.
        // self.readerContainer = FolioReaderContainer(withConfig: FolioReaderConfig(), folioReader: FolioReader(), epubPath: "")
        super.init(frame: frame)
        self.backgroundColor = UIColor.clear
    }

    public func setup(withReaderContainer readerContainer: FolioReaderContainer) {
        self.readerContainer = readerContainer
        guard let readerContainer = self.readerContainer else { return }

        NotificationCenter.default.removeObserver(self, name: .folioReaderNeedRefreshPageMode, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshPageMode), name: .folioReaderNeedRefreshPageMode, object: readerContainer.folioReader)

        self.pageNumber = -1     //guard against webView didFinish handler
        self.currentChapterName = nil
        
        let themeBackgroundColor = self.readerContainer?.readerConfig.themeModeBackground[self.folioReader.themeMode]
        self.backgroundColor = themeBackgroundColor
        self.contentView.backgroundColor = themeBackgroundColor
        
        if webView == nil {
            webView = FolioReaderWebView(frame: webViewFrame(), readerContainer: readerContainer)
            webView?.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            webView?.scrollView.showsVerticalScrollIndicator = false
            webView?.scrollView.showsHorizontalScrollIndicator = false
            webView?.scrollView.scrollsToTop = false
            webView?.backgroundColor = .clear
            webView?.configuration.userContentController.add(self.jsBridge, name: "FolioReaderPage")
            if let webView = webView {
                self.contentView.addSubview(webView)
            }
            if readerConfig.debug.contains(.borderHighlight) {
                webView?.layer.borderWidth = 10
                webView?.layer.borderColor = UIColor.magenta.cgColor
            }
        }
        webView?.backgroundColor = .clear
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
            
            if let panDeadZoneTop = panDeadZoneTop {
                self.contentView.addSubview(panDeadZoneTop)
            }
        }
        
        if panDeadZoneBot == nil {
            panDeadZoneBot = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
            panDeadZoneBot?.autoresizingMask = []
            panDeadZoneBot?.backgroundColor = self.readerContainer?.readerConfig.themeModeBackground[self.folioReader.themeMode]
            panDeadZoneBot?.isOpaque = false
            
            let panGeature = UIPanGestureRecognizer(target: self, action: nil)
            panGeature.delegate = self
            panDeadZoneBot?.addGestureRecognizer(panGeature)
            
            if let panDeadZoneBot = panDeadZoneBot {
                self.contentView.addSubview(panDeadZoneBot)
            }
        }
        
        if panDeadZoneLeft == nil {
            panDeadZoneLeft = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
            panDeadZoneLeft?.autoresizingMask = []
            panDeadZoneLeft?.backgroundColor = self.readerContainer?.readerConfig.themeModeBackground[self.folioReader.themeMode]
            panDeadZoneLeft?.isOpaque = false
            
            let panGeature = UIPanGestureRecognizer(target: self, action: nil)
            panGeature.delegate = self
            panDeadZoneLeft?.addGestureRecognizer(panGeature)
            
            if let panDeadZoneLeft = panDeadZoneLeft {
                self.contentView.addSubview(panDeadZoneLeft)
            }
        }
        
        if panDeadZoneRight == nil {
            panDeadZoneRight = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
            panDeadZoneRight?.autoresizingMask = []
            panDeadZoneRight?.backgroundColor = self.readerContainer?.readerConfig.themeModeBackground[self.folioReader.themeMode]
            panDeadZoneRight?.isOpaque = false
            
            let panGeature = UIPanGestureRecognizer(target: self, action: nil)
            panGeature.delegate = self
            panDeadZoneRight?.addGestureRecognizer(panGeature)
            
            if let panDeadZoneRight = panDeadZoneRight {
                self.contentView.addSubview(panDeadZoneRight)
            }
        }
        
        if colorView == nil {
            let view = UIView()
            view.backgroundColor = self.readerConfig.nightModeBackground
            webView?.scrollView.addSubview(view)
            colorView = view
        }
        
        // Remove all gestures before adding new one
        webView?.gestureRecognizers?.forEach({ gesture in
            if gesture is UITapGestureRecognizer {
                webView?.removeGestureRecognizer(gesture)
            }
        })
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        tapGestureRecognizer.numberOfTapsRequired = 1
        tapGestureRecognizer.cancelsTouchesInView = false
        tapGestureRecognizer.delegate = self
        webView?.addGestureRecognizer(tapGestureRecognizer)
        
        if activityView == nil {
            let view = FolioReaderPageActivity(folioReader: readerContainer.folioReader)
            view.translatesAutoresizingMaskIntoConstraints = false
            self.contentView.addSubview(view)
            NSLayoutConstraint.activate([
                view.centerXAnchor.constraint(equalTo: self.contentView.centerXAnchor),
                view.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor),
                view.widthAnchor.constraint(equalTo: self.contentView.widthAnchor),
                view.heightAnchor.constraint(equalTo: self.contentView.heightAnchor)
            ])
            activityView = view
        }
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
//        loadingView.center = contentView.center
    }

    func webViewFrame() -> CGRect {
        FolioReaderPageFrameCalculator.webViewFrame(input: pageFrameInput)
    }
    
    func anchorBoundsFrame() -> CGRect {
        FolioReaderPageFrameCalculator.anchorBoundsFrame(input: pageFrameInput)
    }
    
    func loadHTMLString(_ htmlContent: String, baseURL: URL?) {
        // Load the html into the webview
        webView?.alpha = 0
        webView?.loadHTMLString(htmlContent, baseURL: baseURL)
    }

    // MARK: UIMenu visibility

    override open func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard let webView = webView else { return false }

        if #available(iOS 16.0, *) {
            if !webView.isColors && !webView.isSharingHighlight {
                webView.createMenu(onHighlight: false)
            }
        } else {
            if UIMenuController.shared.menuItems?.count == 0 {
                webView.isColors = false
                webView.createMenu(onHighlight: false)
            }
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
            colorView?.frame = CGRect.zero
        } else {
            colorView?.frame = CGRect.zero
        }
    }
}

private extension FolioReaderPage {
    var pageFrameInput: FolioReaderPageFrameInput {
        FolioReaderPageFrameInput(
            bounds: bounds,
            writingMode: writingMode,
            scrollDirection: readerConfig.scrollDirection,
            currentMarginTop: folioReader.currentMarginTop,
            currentMarginBottom: folioReader.currentMarginBottom,
            currentMarginLeft: folioReader.currentMarginLeft,
            currentMarginRight: folioReader.currentMarginRight,
            pageWidth: folioReader.readerCenter?.pageWidth ?? 0,
            pageHeight: folioReader.readerCenter?.pageHeight ?? 0,
            statusbarHeight: statusbarHeight,
            pageIndicatorHeight: folioReader.readerCenter?.pageIndicatorHeight ?? 0,
            hidePageIndicator: readerConfig.hidePageIndicator,
            reserveSafeAreaInsidePageFrame: readerConfig.reserveSafeAreaInsidePageFrame,
            reservePageIndicatorInsidePageFrame: readerConfig.reservePageIndicatorInsidePageFrame
        )
    }
}

struct FolioReaderPageFrameInput {
    let bounds: CGRect
    let writingMode: String
    let scrollDirection: FolioReaderScrollDirection
    let currentMarginTop: Int
    let currentMarginBottom: Int
    let currentMarginLeft: Int
    let currentMarginRight: Int
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let statusbarHeight: CGFloat
    let pageIndicatorHeight: CGFloat
    let hidePageIndicator: Bool
    let reserveSafeAreaInsidePageFrame: Bool
    let reservePageIndicatorInsidePageFrame: Bool
}

enum FolioReaderPageFrameCalculator {
    static func webViewFrame(input: FolioReaderPageFrameInput) -> CGRect {
        let metrics = FrameMetrics(input: input)

        return metrics.byWritingMode(
            horizontal: CGRect(
                x: input.bounds.origin.x,
                y: metrics.isDirection(
                    input.bounds.origin.y + metrics.topComponentTotal,
                    input.bounds.origin.y + metrics.topComponentTotal + metrics.paddingTop,
                    input.bounds.origin.y + metrics.topComponentTotal
                ),
                width: input.bounds.width,
                height: max(metrics.isDirection(
                    input.bounds.height - metrics.topComponentTotal - metrics.bottomComponentTotal,
                    input.bounds.height - metrics.topComponentTotal - metrics.bottomComponentTotal - metrics.paddingTop - metrics.paddingBottom,
                    input.bounds.height - metrics.topComponentTotal - metrics.bottomComponentTotal
                ), 0)
            ),
            vertical: CGRect(
                x: metrics.isDirection(
                    input.bounds.origin.x,
                    input.bounds.origin.x + metrics.paddingLeft,
                    input.bounds.origin.x
                ),
                y: input.bounds.origin.y + metrics.topComponentTotal,
                width: metrics.isDirection(
                    input.bounds.width,
                    input.bounds.width - metrics.paddingLeft - metrics.paddingRight,
                    input.bounds.width
                ),
                height: input.bounds.height - metrics.topComponentTotal - metrics.bottomComponentTotal
            )
        )
    }

    static func anchorBoundsFrame(input: FolioReaderPageFrameInput) -> CGRect {
        let metrics = FrameMetrics(input: input)
        let verticalAnchorStatusbarOffset = input.reserveSafeAreaInsidePageFrame ? input.statusbarHeight : 0

        return metrics.byWritingMode(
            horizontal: CGRect(
                x: input.bounds.origin.x + metrics.paddingLeft,
                y: metrics.isDirection(
                    input.bounds.origin.y + metrics.topComponentTotal,
                    input.bounds.origin.y + metrics.topComponentTotal + metrics.paddingTop,
                    input.bounds.origin.y + metrics.topComponentTotal
                ) + verticalAnchorStatusbarOffset,
                width: input.bounds.width - metrics.paddingLeft - metrics.paddingRight,
                height: max(metrics.isDirection(
                    input.bounds.height - metrics.topComponentTotal - metrics.bottomComponentTotal,
                    input.bounds.height - metrics.topComponentTotal - metrics.bottomComponentTotal - metrics.paddingTop - metrics.paddingBottom,
                    input.bounds.height - metrics.topComponentTotal - metrics.bottomComponentTotal
                ), 0)
            ),
            vertical: CGRect(
                x: input.bounds.origin.x + metrics.paddingLeft,
                y: input.bounds.origin.y + metrics.topComponentTotal + metrics.paddingTop,
                width: input.bounds.width - metrics.paddingLeft - metrics.paddingRight,
                height: max(input.bounds.height - metrics.topComponentTotal - metrics.bottomComponentTotal - metrics.paddingTop - metrics.paddingBottom, 0)
            )
        )
    }
}

private struct FrameMetrics {
    let input: FolioReaderPageFrameInput

    var topComponentTotal: CGFloat {
        input.reserveSafeAreaInsidePageFrame ? input.statusbarHeight : 0
    }

    var bottomComponentTotal: CGFloat {
        guard input.reservePageIndicatorInsidePageFrame, !input.hidePageIndicator else { return 0 }
        return input.pageIndicatorHeight
    }

    var paddingTop: CGFloat {
        floor(CGFloat(input.currentMarginTop) / 200 * input.pageHeight)
    }

    var paddingBottom: CGFloat {
        floor(CGFloat(input.currentMarginBottom) / 200 * input.pageHeight)
    }

    var paddingLeft: CGFloat {
        floor(CGFloat(input.currentMarginLeft) / 200 * input.pageWidth)
    }

    var paddingRight: CGFloat {
        floor(CGFloat(input.currentMarginRight) / 200 * input.pageWidth)
    }

    func isDirection<T>(_ vertical: T, _ horizontalContentPaged: T, _ horizontalContentScroll: T) -> T {
        switch input.scrollDirection {
        case .vertical, .defaultVertical:
            return vertical
        case .horizontalWithPagedContent:
            return horizontalContentPaged
        case .horizontalWithScrollContent:
            return horizontalContentScroll
        }
    }

    func byWritingMode<T>(horizontal: T, vertical: T) -> T {
        input.writingMode == "vertical-rl" ? vertical : horizontal
    }
}
