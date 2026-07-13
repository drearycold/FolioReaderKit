//
//  FolioReaderCenter.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 08/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import FolioEPUBCore
import WebKit


/// The base reader class
open class FolioReaderCenter: UIViewController {

    /// This delegate receives the events from the current `FolioReaderPage`s delegate.
    open var delegate: FolioReaderCenterDelegate?

    /// This delegate receives the events from current page
    open weak var pageDelegate: FolioReaderPageDelegate?

    /// The base reader container
    open weak var readerContainer: FolioReaderContainer?

    /// The current visible page on reader
//    open var currentPage: FolioReaderPage?

    /// The collection view with pages
    open var collectionView: UICollectionView!
    
    let collectionViewLayout = FolioReaderCenterLayout()
    var loadingView: UIActivityIndicatorView?
    var totalPages: Int = 0
    var tempFragment: String?
    var tempOffset: CGPoint?
    var animator: FolioModalTransitionAnimator?
    var pageIndicatorView: FolioReaderPageIndicator?
    var pageIndicatorHeight: CGFloat = 20
    var recentlyScrolled = false
    var recentlyScrolledDelay = 2.0 // 2 second delay until we clear recentlyScrolled
    var recentlyScrolledTimer: Timer?
    var scrollScrubber: ScrollScrubber?
    var activityIndicator = UIActivityIndicatorView()
    var isScrolling = false
    var pendingBarRevealWorkItem: DispatchWorkItem?
    var pendingBarRevealToken: UInt = 0
    var pageScrollDirection = ScrollDirection()
    let wkProcessorPool = WKProcessPool()
    
    var nextPageNumber: Int {
        self.currentPageNumber + 1
    }
    var previousPageNumber: Int {
        self.currentPageNumber - 1
    }
//    var currentPageNumber: Int = 0 {
//        didSet {
//            print("currentPageNumber \(oldValue) -> \(currentPageNumber)")
//        }
//        
//    }
    
    open var currentPage: FolioReaderPage? {
        self.collectionView.cellForItem(at: self.getCurrentIndexPath()) as? FolioReaderPage
    }
    
    var currentPageNumber: Int {
        self.getCurrentIndexPath().item + 1
    }
    
    var isLastPage: Bool {
        currentPageNumber == nextPageNumber
    }
    
    var pageWidth: CGFloat = 0.0
    var pageHeight: CGFloat = 0.0
    
    var lastMenuSelectedIndex = 0

    var screenBounds = CGRect.zero
    var pointNow = CGPoint.zero
    var tempReference: FRTocReference?
//    var isFirstLoad = true
    
    /**
     key: IndexPath.row
     */
    var currentWebViewScrollPositions = [Int: FolioReaderReadPosition]()
    var navigateWebViewScrollPositions = Array<(Int, CGPoint)>()

    var tempCollectionViewInset: CGFloat = 0.0
    
    var menuBarController = UITabBarController()
    var menuTabs = [FolioReaderMenu]()
    
    var highlightErrors: [String: String] = [:]
    
    var bookmarkErrors: [String: String] = [:]
    var tempRefText: String?
    var tempRefCFI: String?
    let searchSession = FolioReaderSearchSession()
    
    var readerConfig: FolioReaderConfig {
        guard let readerContainer = readerContainer else { return FolioReaderConfig() }
        return readerContainer.readerConfig
    }

    var barHostingNavigationController: UINavigationController? {
        readerContainer?.centerNavigationController ?? navigationController
    }

    lazy var paginationEngine: ReaderPaginationEngine = {
        return ReaderPaginationEngine(center: self)
    }()

    lazy var scrollHandler: ReaderScrollDelegateHandler = {
        return ReaderScrollDelegateHandler(center: self)
    }()

    var book: FRBook {
        guard let readerContainer = readerContainer else { return FRBook() }
        return readerContainer.book
    }

    lazy var textLocator: FolioReaderTextLocator = {
        FolioReaderTextLocator(book: book)
    }()

    var currentSearchAnchor: FolioReaderSearchAnchor? {
        let page = currentPageNumber
        guard page > 0, page <= totalPages else { return nil }
        return FolioReaderSearchAnchor(page: page,
                                       cfi: currentWebViewScrollPositions[page - 1]?.cfi)
    }

    var folioReader: FolioReader {
        guard let readerContainer = readerContainer else { return FolioReader() }
        return readerContainer.folioReader
    }

    // MARK: - Init

    init(withContainer readerContainer: FolioReaderContainer) {
        self.readerContainer = readerContainer
        super.init(nibName: nil, bundle: Bundle.frameworkBundle())

        self.initialization()
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("This class doesn't support NSCoding.")
    }

    /**
     Common Initialization
     */
    func initialization() {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        if (self.readerConfig.hideBars == true) {
            self.pageIndicatorHeight = 0
        }
        
        self.totalPages = book.spine.spineReferences.count

        // Loading indicator
        let style: UIActivityIndicatorView.Style = folioReader.isNight(.white, .gray)
        let indicator = UIActivityIndicatorView(style: style)
        indicator.hidesWhenStopped = true
        indicator.startAnimating()
        self.view.addSubview(indicator)
        loadingView = indicator

        self.folioReader.readerAudioPlayer?.delegate = self
    }

    // MARK: - View life cicle

    override open func viewDidLoad() {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }
        
        super.viewDidLoad()

        screenBounds = self.getScreenBounds()
        
        // Layout
        collectionViewLayout.scrollDirection = .direction(withConfiguration: self.readerConfig)
        
        //let background = folioReader.isNight(self.readerConfig.nightModeBackground, UIColor.white)
        let background = self.readerConfig.themeModeBackground[folioReader.themeMode]
        view.backgroundColor = background

        //CollectionView
        let collectionViewFrame = frameForCollectionView(outerBounds: screenBounds)
        collectionView = UICollectionView(frame: collectionViewFrame, collectionViewLayout: collectionViewLayout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.delegate = self.scrollHandler
        collectionView.dataSource = self

        collectionView.isPagingEnabled = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.backgroundColor = background
        collectionView.decelerationRate = UIScrollView.DecelerationRate.fast
        collectionView.isPrefetchingEnabled = false
        
        // Register cell classes
        collectionView.register(FolioReaderPage.self, forCellWithReuseIdentifier: kReuseCellIdentifier)
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: kReusePrologueCellIdentifier)

        enableScrollBetweenChapters(scrollEnabled: true)
        if readerConfig.debug.contains(.borderHighlight) {
            collectionView.layer.borderWidth = 8
            collectionView.layer.borderColor = UIColor.purple.cgColor
        }
        view.addSubview(collectionView)
        
        // Activity Indicator
        self.activityIndicator = UIActivityIndicatorView(frame: CGRect(x: screenBounds.size.width/2, y: screenBounds.size.height/2, width: 30, height: 30))
        self.activityIndicator.style = .medium
        self.activityIndicator.hidesWhenStopped = true
        self.activityIndicator.backgroundColor = UIColor.gray
        self.view.addSubview(self.activityIndicator)
        self.view.bringSubviewToFront(self.activityIndicator)
        
        // Configure navigation bar and layout
        collectionView.contentInsetAdjustmentBehavior = .never
        extendedLayoutIncludesOpaqueBars = true
        configureNavBar()

        // Page indicator view
        if (self.readerConfig.hidePageIndicator == false) {
            let frame = self.frameForPageIndicatorView(outerBounds: screenBounds)
            pageIndicatorView = FolioReaderPageIndicator(frame: frame, readerConfig: readerConfig, folioReader: folioReader)
            if let pageIndicatorView = pageIndicatorView {
                view.addSubview(pageIndicatorView)
            }
        }

        guard let readerContainer = readerContainer else { return }
        self.scrollScrubber = ScrollScrubber(frame: frameForScrollScrubber(outerBounds: screenBounds), withReaderContainer: readerContainer)
        self.scrollScrubber?.delegate = self
        if let scrollScrubber = scrollScrubber {
            view.addSubview(scrollScrubber.slider)
        }
        
    }

    override open func viewWillAppear(_ animated: Bool) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        super.viewWillAppear(animated)

        configureNavBar()

        // Update pages
        currentPage?.updatePages()
        pageIndicatorView?.reloadView(updateShadow: true)
    }

    override open func viewWillDisappear(_ animated: Bool) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        folioReader.saveReaderState()
    }
    
    override open func viewWillLayoutSubviews() {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        super.viewWillLayoutSubviews()
        
        
    }
    
    override open func viewDidLayoutSubviews() {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        super.viewDidLayoutSubviews()

        screenBounds = self.getScreenBounds()
        loadingView?.center = view.center

        updateSubviewFrames()
    }

    // MARK: Layout

    /**
     Enable or disable the scrolling between chapters (`FolioReaderPage`s). If this is enabled it's only possible to read the current chapter. If another chapter should be displayed is has to be triggered programmatically with `changePageWith`.

     - parameter scrollEnabled: `Bool` which enables or disables the scrolling between `FolioReaderPage`s.
     */
    open func enableScrollBetweenChapters(scrollEnabled: Bool) {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        self.collectionView.isScrollEnabled = scrollEnabled
    }

    func reloadData() {
        if readerConfig.debug.contains(.functionTrace) { FolioLogger.log("ENTER") }

        self.loadingView?.stopAnimating()
        self.totalPages = book.spine.spineReferences.count

        self.collectionView.reloadData()
        self.configureNavBarButtons()
        self.setCollectionViewProgressiveDirection()

        let bookId = self.book.name?.deletingPathExtension
        let position = bookId.flatMap { self.folioReader.delegate?.folioReaderReadPositionProvider?(self.folioReader).folioReaderReadPosition(self.folioReader, bookId: $0) }

        if self.readerConfig.loadSavedPositionForCurrentBook,
           let position = position,
           position.pageNumber > 0 {
            self.changePageWith(page: position.pageNumber)
        }
    }

    
    
}
