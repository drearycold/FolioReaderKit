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

    /// `PageLoad` signpost for the current web view load; ended when the page is shown, or when that
    /// load (`loadNavigation`) fails.
    var loadInterval: FolioSignpost.Interval?
    var loadNavigation: WKNavigation?
    
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

    /// A position the page was just restored to (rotation, scroll-direction switch), kept as the
    /// recorded one until the reader moves. A restore shows the line, column or page that holds the
    /// position, which starts before it; recording what is then on screen moved the position back on
    /// every relayout (two lines per portrait/landscape round trip in scroll mode). Cleared by
    /// dragging, page-item turns, the back button, the scrubber, anchor links and cell reuse.
    var pinnedPosition: FolioReaderReadPosition?

    /// The resource server port the chapter was loaded from.
    var loadedPort: UInt = 0
    /// The width from which the chapter shows two pages side by side in landscape, or nil for one
    /// page (`FolioReaderCenter.spreadMinimumWidth`, as it was when the chapter was loaded).
    var spreadMinimumWidth: CGFloat?
    /// The chapter's pages run top to bottom: vertical writing in `.vertical` ("Tiered",
    /// `FolioReaderCSSBuilder.tieredRules`). It is measured and scrolled in y, a web view high a page.
    /// Set with the overflow style (`updateOverflowStyle`), so it describes the layout the page has:
    /// a page laid out before a scroll-direction change is still measured on its own axis.
    var pagesDown = false {
        didSet { webView?.pagesDown = pagesDown }
    }
    /// The scroll direction the chapter is laid out for (`recordLayout`).
    var layoutScrollDirection: FolioReaderScrollDirection?
    /// The spread setting the chapter is laid out for (`recordLayout`). The web view's frame follows
    /// it, as a spread's outer margins are partly outside the web view: it changes with the overflow
    /// style, not when the setting does, which is before the position is recorded.
    var layoutSpreadMinimumWidth: CGFloat? {
        didSet {
            if layoutSpreadMinimumWidth != oldValue { setNeedsLayout() }
        }
    }
    /// The web view size (`webViewFrame()`) the chapter is laid out for, which its background
    /// padding and content offset fit (`recordLayout`, `updateStyleBackgroundPadding`).
    var layoutSize = CGSize.zero
    /// The style settings the chapter was last styled with (`recordStyle`), or nil while it loads.
    var styleState: FolioReaderStyleState?
    /// The theme the chapter was last given (`recordStyle`, `applyTheme`), or nil while it loads.
    var styledThemeMode: Int?
    /// Counts the chapter loads started in this page. A reload of the same chapter keeps the page
    /// number, so the load chain checks this too before acting on the page.
    var loadGeneration = 0
    /// The web content process died; the chapter must be loaded again (`FolioReaderCenter.reloadPages`).
    var needsReload = false
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
    
    /// Set while the page loads or is laid out again; `activityView` covers it meanwhile.
    var layoutAdapting: PageLayoutStage? = nil {
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
            panDeadZoneRight?.isOpaque = false
            
            let panGeature = UIPanGestureRecognizer(target: self, action: nil)
            panGeature.delegate = self
            panDeadZoneRight?.addGestureRecognizer(panGeature)
            
            if let panDeadZoneRight = panDeadZoneRight {
                self.contentView.addSubview(panDeadZoneRight)
            }
        }
        // Every time: a reused cell kept the theme it was created with around the web view.
        applyThemeBackground(folioReader.themeMode)

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
        loadInterval?.end("closed")
        webView?.scrollView.delegate = nil
        webView?.navigationDelegate = nil
        NotificationCenter.default.removeObserver(self)
    }

    /// The collection view has just applied the layout attributes, whose transform is the identity:
    /// mirror a right-to-left book's page again. It applies them whenever they change, so after a
    /// rotation (which mirrors only the current page itself) a chapter kept next to the current one
    /// came back with mirrored text. Setting the transform before it is shown
    /// (`willDisplay`, `cellForItemAt`) isn't enough: a reused cell gets its attributes after both.
    override open func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        readerContainer?.centerViewController?.setPageProgressiveDirection(self)
    }

    override open func layoutSubviews() {
        super.layoutSubviews()

        webView?.setupScrollDirection()
        let webViewFrame = self.webViewFrame()
        webView?.frame = webViewFrame
        
        // The zones cover the margins around the web view, the corners with the top and bottom ones.
        let panDeadZoneTopFrame = CGRect(x: 0, y: 0, width: frame.width, height: webViewFrame.minY)
        panDeadZoneTop?.frame = panDeadZoneTopFrame
        
        let panDeadZoneBotFrame = CGRect(x: 0, y: webViewFrame.maxY, width: frame.width, height: frame.height - webViewFrame.maxY)
        panDeadZoneBot?.frame = panDeadZoneBotFrame
        
        let panDeadZoneLeftFrame = CGRect(x: 0, y: webViewFrame.minY, width: webViewFrame.minX, height: webViewFrame.height)
        panDeadZoneLeft?.frame = panDeadZoneLeftFrame
        
        let panDeadZoneRightFrame = CGRect(x: webViewFrame.maxX, y: webViewFrame.minY, width: frame.width - webViewFrame.maxX, height: webViewFrame.height)
        panDeadZoneRight?.frame = panDeadZoneRightFrame
        
        print("\(#function) frame=\(frame) webViewFrame=\(webViewFrame)  panDeadZoneLeftFrame=\(panDeadZoneLeftFrame) panDeadZoneRightFrame=\(panDeadZoneRightFrame)")
//        loadingView.center = contentView.center
    }

    func webViewFrame() -> CGRect {
        FolioReaderPageFrameCalculator.webViewFrame(input: pageFrameInput)
    }
    
    /// Whether the page, in horizontal writing in paged mode, is wide enough for a spread at
    /// `minimumWidth` (`FolioReaderPageFrameCalculator.fitsSpread`).
    func fitsSpread(minimumWidth: CGFloat) -> Bool {
        FolioReaderPageFrameCalculator.fitsSpread(input: pageFrameInput, minimumWidth: minimumWidth)
    }

    func anchorBoundsFrame() -> CGRect {
        FolioReaderPageFrameCalculator.anchorBoundsFrame(input: pageFrameInput)
    }

    /// A swipe that starts in the outer margins of a spread or of tiers, outside the web view, turns
    /// the page as one on the text does: the margins' pan dead zones would swallow it.
    override open func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        guard let webView = webView, let superview = webView.superview, let hit = view,
              [panDeadZoneTop, panDeadZoneBot, panDeadZoneLeft, panDeadZoneRight].contains(where: { $0 === hit }) else { return view }
        let insets = FolioReaderPageFrameCalculator.outerMarginInsets(input: pageFrameInput)
        let margins = webView.frame.inset(by: UIEdgeInsets(top: -insets.top, left: -insets.left, bottom: -insets.bottom, right: -insets.right))
        return margins.contains(convert(point, to: superview)) ? webView.scrollView : view
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

    /// Gives the chapter the theme (`themeMode` in `Bridge.js`) and the page's views around the web
    /// view its background, and records it (`FolioReaderCenter.hasOtherTheme`).
    func applyTheme(_ themeMode: Int) {
        styledThemeMode = themeMode
        webView?.js("themeMode(\(themeMode))")
        applyThemeBackground(themeMode)
    }

    /// The theme's background around the web view: the page margins in paged mode.
    func applyThemeBackground(_ themeMode: Int) {
        guard let color = readerConfig.themeModeBackground[safe: themeMode] else { return }
        contentView.backgroundColor = color
        for zone in [panDeadZoneTop, panDeadZoneBot, panDeadZoneLeft, panDeadZoneRight] {
            zone?.backgroundColor = color
        }
    }
}

private extension FolioReaderPage {
    var pageFrameInput: FolioReaderPageFrameInput {
        FolioReaderPageFrameInput(
            bounds: bounds,
            writingMode: writingMode,
            scrollDirection: readerConfig.scrollDirection,
            pagesDown: pagesDown,
            spreadMinimumWidth: layoutSpreadMinimumWidth,
            tiersMinimumHeight: readerConfig.tiersMinimumHeight,
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
    /// Vertical writing in `.vertical`, paged down (`FolioReaderPage.pagesDown`).
    var pagesDown = false
    /// The spread setting the page is laid out for (`FolioReaderPage.layoutSpreadMinimumWidth`).
    var spreadMinimumWidth: CGFloat? = nil
    /// The height from which pages that run down show two tiers (`FolioReaderConfig.tiersMinimumHeight`).
    var tiersMinimumHeight: CGFloat? = nil
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
    /// The web view's frame, in whole points: WebKit's viewport is whole CSS pixels. In vertical
    /// writing the viewport is set by the view's height (`height=device-height`) and its width
    /// follows the aspect ratio, so a 780 × 751.5 view (a host's toolbar of 54.5 pt) laid out 781 px
    /// wide pages. They outgrew the 780 pt screens a pixel a page, the page count never matched the
    /// screens, and `updateStyleBackgroundPadding` never finished.
    static func webViewFrame(input: FolioReaderPageFrameInput) -> CGRect {
        let metrics = FrameMetrics(input: input)
        return metrics.pageFrame.inset(by: metrics.outerMarginInsets)
    }

    /// A spread's or tiers' outer margins outside the web view (`FrameMetrics.outerMarginInsets`),
    /// else zero.
    static func outerMarginInsets(input: FolioReaderPageFrameInput) -> UIEdgeInsets {
        FrameMetrics(input: input).outerMarginInsets
    }

    /// Whether the page shows a spread at `minimumWidth`, in horizontal writing in paged mode: its
    /// web view, before a spread's outer margins, is landscape and at least that wide.
    static func fitsSpread(input: FolioReaderPageFrameInput, minimumWidth: CGFloat) -> Bool {
        FrameMetrics(input: input).fitsSpread(minimumWidth: minimumWidth)
    }

    /// The text area in the page's coordinates, where `FolioReaderAnchorPreview` places itself. In
    /// horizontal writing its top is the web view's top, which the anchor offset counts from.
    static func anchorBoundsFrame(input: FolioReaderPageFrameInput) -> CGRect {
        let metrics = FrameMetrics(input: input)
        let paged = metrics.pagedPadding

        return metrics.byWritingMode(
            horizontal: input.bounds
                .inset(by: metrics.reserved)
                .inset(by: UIEdgeInsets(top: paged.top, left: metrics.padding.left, bottom: paged.bottom, right: metrics.padding.right))
                .clampedToNonNegativeSize,
            vertical: input.bounds
                .inset(by: metrics.reserved)
                .inset(by: metrics.padding)
                .clampedToNonNegativeSize
        )
    }
}

private struct FrameMetrics {
    let input: FolioReaderPageFrameInput

    /// Status bar and page indicator space kept inside the page frame.
    var reserved: UIEdgeInsets {
        let showsPageIndicator = input.reservePageIndicatorInsidePageFrame && !input.hidePageIndicator
        return UIEdgeInsets(
            top: input.reserveSafeAreaInsidePageFrame ? input.statusbarHeight : 0,
            left: 0,
            bottom: showsPageIndicator ? input.pageIndicatorHeight : 0,
            right: 0
        )
    }

    /// User margins; each margin level is 1/200 of the page size.
    var padding: UIEdgeInsets {
        UIEdgeInsets(
            top: floor(CGFloat(input.currentMarginTop) / 200 * input.pageHeight),
            left: floor(CGFloat(input.currentMarginLeft) / 200 * input.pageWidth),
            bottom: floor(CGFloat(input.currentMarginBottom) / 200 * input.pageHeight),
            right: floor(CGFloat(input.currentMarginRight) / 200 * input.pageWidth)
        )
    }

    /// Only paged content puts the user margins into the frame (in vertical writing, its left and
    /// right ones, which `<body>` padding would give only at the chapter's ends); the other scroll
    /// directions leave them to the CSS body padding.
    var pagedPadding: UIEdgeInsets {
        input.scrollDirection == .horizontalWithPagedContent || input.pagesDown ? padding : .zero
    }

    /// The web view's frame without a spread's outer margins.
    var pageFrame: CGRect {
        let paged = pagedPadding
        return input.bounds
            .inset(by: reserved)
            .inset(by: byWritingMode(
                horizontal: UIEdgeInsets(top: paged.top, left: 0, bottom: paged.bottom, right: 0),
                vertical: UIEdgeInsets(top: 0, left: paged.left, bottom: 0, right: paged.right)
            ))
            .clampedToNonNegativeSize
            .flooredSize
    }

    /// As `FolioReaderCSSBuilder.spreadRules`' media query asks, before the outer margins.
    func fitsSpread(minimumWidth: CGFloat) -> Bool {
        let size = pageFrame.size
        return input.scrollDirection == .horizontalWithPagedContent && input.writingMode != "vertical-rl"
            && size.width > size.height && size.width >= minimumWidth
    }

    /// As `FolioReaderCSSBuilder.tieredRules`' media query asks, before the outer margins: pages that
    /// run down, portrait and at least `minimumHeight` tall.
    func fitsTiers(minimumHeight: CGFloat) -> Bool {
        let size = pageFrame.size
        return input.pagesDown && input.writingMode == "vertical-rl"
            && size.height >= size.width && size.height >= minimumHeight
    }

    /// The outer margins of two pages to a screen that are outside the web view: a spread's beside
    /// it, tiers' above and below it. `<body>`'s padding repeats in both pages, so the gutter between
    /// them is two pages' padding; each outer margin gets as much again as a page's padding outside
    /// the web view, so the gutter is as wide as an outer margin. The web view stays as large as the
    /// media query asks (`FolioReaderCSSBuilder.spreadRules`, `tieredRules`), so near the minimum
    /// size the outer margins are narrower.
    var outerMarginInsets: UIEdgeInsets {
        let page = pageFrame.size
        if let minimumWidth = input.spreadMinimumWidth, fitsSpread(minimumWidth: minimumWidth) {
            // Landscape: wider than high.
            let (left, right) = Self.outerMargins(along: page.width, margins: (input.currentMarginLeft, input.currentMarginRight), minimum: max(minimumWidth, page.height + 1))
            return UIEdgeInsets(top: 0, left: left, bottom: 0, right: right)
        }
        if let minimumHeight = input.tiersMinimumHeight, fitsTiers(minimumHeight: minimumHeight) {
            // Portrait: at least as high as wide.
            let (top, bottom) = Self.outerMargins(along: page.height, margins: (input.currentMarginTop, input.currentMarginBottom), minimum: max(minimumHeight, page.width))
            return UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
        }
        return .zero
    }

    /// The outer margins outside a web view that is at most `length` long and at least `minimum`:
    /// each one a page's padding for its margin setting (`FolioReaderCSSBuilder.columnPaddingDivisor`),
    /// a share of the web view's length.
    private static func outerMargins(along length: CGFloat, margins: (Int, Int), minimum: CGFloat) -> (CGFloat, CGFloat) {
        let divisor = 100 * Double(FolioReaderCSSBuilder.columnPaddingDivisor)
        let before = CGFloat(FolioReaderCSSBuilder.paddingPercent(margin: margins.0) / divisor)
        let after = CGFloat(FolioReaderCSSBuilder.paddingPercent(margin: margins.1) / divisor)
        guard before + after > 0 else { return (0, 0) }
        // A web view l long leaves (before + after) * l outside it.
        let inside = min(max(length / (1 + before + after), minimum), length)
        let outside = length - inside
        return (floor(outside * before / (before + after)), floor(outside * after / (before + after)))
    }

    func byWritingMode<T>(horizontal: T, vertical: T) -> T {
        input.writingMode == "vertical-rl" ? vertical : horizontal
    }
}

private extension CGRect {
    /// Reads `size` directly, because `width` and `height` return standardized (absolute) values.
    var clampedToNonNegativeSize: CGRect {
        CGRect(origin: origin, size: CGSize(width: max(size.width, 0), height: max(size.height, 0)))
    }

    /// The size rounded down to whole points, so it stays inside the page.
    var flooredSize: CGRect {
        CGRect(origin: origin, size: CGSize(width: floor(size.width), height: floor(size.height)))
    }
}
