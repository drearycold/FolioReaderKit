//
//  FolioReaderCenter.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 08/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import WebKit
import ZFDragableModalTransition


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
    var loadingView: UIActivityIndicatorView!
    var totalPages: Int = 0
    var tempFragment: String?
    var tempOffset: CGPoint?
    var animator: ZFModalTransitionAnimator!
    var pageIndicatorView: FolioReaderPageIndicator?
    var pageIndicatorHeight: CGFloat = 20
    var recentlyScrolled = false
    var recentlyScrolledDelay = 2.0 // 2 second delay until we clear recentlyScrolled
    var recentlyScrolledTimer: Timer!
    var scrollScrubber: ScrollScrubber?
    var activityIndicator = UIActivityIndicatorView()
    var isScrolling = false
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

    var screenBounds: CGRect!
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
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        if (self.readerConfig.hideBars == true) {
            self.pageIndicatorHeight = 0
        }
        
        self.totalPages = book.spine.spineReferences.count

        // Loading indicator
        let style: UIActivityIndicatorView.Style = folioReader.isNight(.white, .gray)
        loadingView = UIActivityIndicatorView(style: style)
        loadingView.hidesWhenStopped = true
        loadingView.startAnimating()
        self.view.addSubview(loadingView)
    }

    // MARK: - View life cicle

    override open func viewDidLoad() {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }
        
        super.viewDidLoad()

        screenBounds = self.getScreenBounds()
        
        // Layout
        collectionViewLayout.scrollDirection = .direction(withConfiguration: self.readerConfig)
        
        //let background = folioReader.isNight(self.readerConfig.nightModeBackground, UIColor.white)
        let background = self.readerConfig.themeModeBackground[folioReader.themeMode]
        view.backgroundColor = background

        // CollectionView
        let collectionViewFrame = frameForCollectionView(outerBounds: screenBounds)
        collectionView = UICollectionView(frame: collectionViewFrame, collectionViewLayout: collectionViewLayout)
        //collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.autoresizingMask = .init(rawValue: 0)
        collectionView.delegate = self
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
        self.activityIndicator.style = .gray
        self.activityIndicator.hidesWhenStopped = true
        self.activityIndicator = UIActivityIndicatorView(frame: CGRect(x: screenBounds.size.width/2, y: screenBounds.size.height/2, width: 30, height: 30))
        self.activityIndicator.backgroundColor = UIColor.gray
        self.view.addSubview(self.activityIndicator)
        self.view.bringSubviewToFront(self.activityIndicator)
        
        // Configure navigation bar and layout
        if #available(iOS 11.0, *) {
            collectionView.contentInsetAdjustmentBehavior = .never
        } else {
            automaticallyAdjustsScrollViewInsets = false
        }
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
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        super.viewWillAppear(animated)

        configureNavBar()

        // Update pages
        currentPage?.updatePages()
        pageIndicatorView?.reloadView(updateShadow: true)
    }

    override open func viewWillDisappear(_ animated: Bool) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        folioReader.saveReaderState()
    }
    
    override open func viewWillLayoutSubviews() {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        super.viewWillLayoutSubviews()
        
        
    }
    
    override open func viewDidLayoutSubviews() {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        super.viewDidLayoutSubviews()

        screenBounds = self.getScreenBounds()
        loadingView.center = view.center

        updateSubviewFrames()
    }

    // MARK: Layout

    /**
     Enable or disable the scrolling between chapters (`FolioReaderPage`s). If this is enabled it's only possible to read the current chapter. If another chapter should be displayed is has to be triggered programmatically with `changePageWith`.

     - parameter scrollEnabled: `Bool` which enables or disables the scrolling between `FolioReaderPage`s.
     */
    open func enableScrollBetweenChapters(scrollEnabled: Bool) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        self.collectionView.isScrollEnabled = scrollEnabled
    }

    func reloadData() {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        self.loadingView.stopAnimating()
        self.totalPages = book.spine.spineReferences.count

        self.collectionView.reloadData()
        self.configureNavBarButtons()
        self.setCollectionViewProgressiveDirection()

        if self.readerConfig.loadSavedPositionForCurrentBook,
           let position = folioReader.savedPositionForCurrentBook,
           position.pageNumber > 0 {
            self.changePageWith(page: position.pageNumber)
        }
    }

    
    
    // MARK: - View Transition
    override open func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        if readerConfig.debug.contains(.viewTransition) {
            print("BEGINTRANSROTATE fromBounds=\(collectionView.bounds) fromContentSize=\(collectionView.contentSize) fromItemSize=\(collectionViewLayout.itemSize) to=\(size) \(String(describing: coordinator.debugDescription))")
        }
        
        guard folioReader.isReaderReady else { return }

        if readerConfig.debug.contains(.viewTransition) {
            self.collectionView.indexPathsForVisibleItems.forEach {
                print("BEGIN2TRANSROTATE \($0.debugDescription)")
            }
        }
        
        //compute new screen bounds
        if readerConfig.debug.contains(.viewTransition) {
            self.collectionView.indexPathsForVisibleItems.forEach {
                print("BEGIN2TRANSROTATE \($0.debugDescription)")
            }
        }
        
        var bounds = view.frame
        bounds.size = size
        if #available(iOS 11.0, *) {
            bounds.size.height = bounds.size.height - view.safeAreaInsets.bottom
        }
        if readerConfig.debug.contains(.viewTransition) {
            folioLogger("size=\(size) newBounds=\(bounds) screenBounds=\(String(describing: screenBounds)) collectionViewFrame=\(collectionView.frame)")
        }
        
        guard let currentPage = self.currentPage else { return }
        
        let currentIndexPath = getCurrentIndexPath()
        
        if currentPage.layoutAdapting == nil {
            currentPage.layoutAdapting = "Transitioning..."
            currentPage.updatePageOffsetRate()
        }
        let pageOffsetRate = currentPage.pageOffsetRate
        
        folioLogger("TRANS1 pageOffsetRate=\(currentPage.pageOffsetRate) contentSize=\(currentPage.webView?.scrollView.contentSize ?? .zero) contentOffset=\(currentPage.webView?.scrollView.contentOffset ?? .zero)")
        
        coordinator.animate { _ in
            
        } completion: { [self] _ in
            self.changePageWith(indexPath: currentIndexPath, animated: false) {
                guard let currentPage = self.currentPage else { return }
                
                setPageProgressiveDirection(currentPage)

                // After rotation fix internal page offset
                delay(currentPage.delaySec()) {    //wait for webView finish resizing
                    folioLogger("TRANS2 pageOffsetRate=\(currentPage.pageOffsetRate) contentSize=\(currentPage.webView?.scrollView.contentSize ?? .zero) contentOffset=\(currentPage.webView?.scrollView.contentOffset ?? .zero)")
                    
    //                currentPage.scrollPageToOffset(
    //                    currentPage.byWritingMode(
    //                        0.0,
    //                        (currentPage.webView?.scrollView.contentSize.width ?? 0.0) - (currentPage.webView?.scrollView.frame.width ?? 0.0)
    //                    ), animated: false
    //                )
                    
                    currentPage.webView?.js(
                    """
                        document.body.style.minHeight = null;
                        document.body.style.minWidth = null;
                    """) { _ in
                        currentPage.setNeedsLayout()
                        
                        delay(currentPage.delaySec() + 0.5) {   //need some time for webView finishing paging
                            currentPage.updatePageInfo() {
                                currentPage.updateStyleBackgroundPadding(delay: 0.2) {
                                    currentPage.pageOffsetRate = pageOffsetRate
                                    currentPage.scrollWebViewByPageOffsetRate(animated: false)
                                    delay(0.2) {
                                        folioLogger("TRANS3 pageOffsetRate=\(currentPage.pageOffsetRate) contentSize=\(currentPage.webView?.scrollView.contentSize ?? .zero) contentOffset=\(currentPage.webView?.scrollView.contentOffset ?? .zero)")
                                        currentPage.updatePageOffsetRate()
                                        currentPage.layoutAdapting = nil
                                        folioLogger("TRANS4 pageOffsetRate=\(currentPage.pageOffsetRate) contentSize=\(currentPage.webView?.scrollView.contentSize ?? .zero) contentOffset=\(currentPage.webView?.scrollView.contentOffset ?? .zero)")
                                        currentPage.updatePageInfo()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        
    }
    
    // MARK: NavigationBar Actions

    @objc func closeReader(_ sender: UIBarButtonItem) {
        if readerConfig.debug.contains(.functionTrace) { folioLogger("ENTER") }

        dismiss()
        folioReader.close()
    }
    
    @objc func logoButtonAction(_ sender: UIBarButtonItem) {
        print("\(#function) \(self.navigateWebViewScrollPositions)")
        
        guard let position = self.navigateWebViewScrollPositions.popLast() else { return }
        self.navigationItem.rightBarButtonItems?.last?.isEnabled = !self.navigateWebViewScrollPositions.isEmpty
        if position.0 == currentPageNumber {
            self.currentPage?.setScrollViewContentOffset(position.1, animated: true)
        } else {
            self.changePageWith(page: position.0) {     //depends on `currentWebViewScrollPositions` to in page reposition
                self.currentPage?.updatePages()
            }
        }
    }
}
