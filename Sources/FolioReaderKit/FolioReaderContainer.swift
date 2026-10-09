//
//  FolioReaderContainer.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 15/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import FolioEPUBCore
import FontBlaster
import ReadiumZIPFoundation
import ReadiumGCDWebServer

/// Reader container
open class FolioReaderContainer: UIViewController {
    var shouldHideStatusBar = true
    
    // Mark those property as public so they can accessed from other classes/subclasses.
    public var epubPath: String
    public var book: FRBook
    
    public var centerNavigationController: FolioReaderNavigationController?
    public var centerViewController: FolioReaderCenter?
    public var audioPlayer: FolioReaderAudioPlayer?
    
    public var readerConfig: FolioReaderConfig
    public var folioReader: FolioReader

    fileprivate var errorOnLoad = false
    /// The book that has been (or is being) loaded, so reappearing doesn't parse it again.
    private var loadedEpubPath: String?
    
    var webServer: ReadiumGCDWebServer
    private var resourceServer: EpubResourceServer?
    private var didBecomeActiveObserver: NSObjectProtocol?

    /// The port pages load from. Stable while the server is suspended in the background, when
    /// `webServer.port` reads 0.
    var pagePort: UInt {
        resourceServer?.port ?? webServer.port
    }
    /// Open until the first page is shown; ended by `FolioReaderCenter.pageDidLoad`.
    var firstPageInterval: FolioSignpost.Interval?

    // MARK: - Init

    /// Init a Folio Reader Container
    ///
    /// - Parameters:
    ///   - config: Current Folio Reader configuration
    ///   - folioReader: Current instance of the FolioReader kit.
    ///   - path: The ePub path on system. Must not be nil nor empty string.
	///   - unzipPath: Path to unzip the compressed epub.
    ///   - removeEpub: Should delete the original file after unzip? Default to `true` so the ePub will be unziped only once.
    public init(withConfig config: FolioReaderConfig, folioReader: FolioReader, epubPath path: String, webServer: ReadiumGCDWebServer) {
        self.readerConfig = config
        self.folioReader = folioReader
        self.epubPath = path
        self.book = FRBook()
        self.webServer = webServer

        super.init(nibName: nil, bundle: Bundle.frameworkBundle())

        finishInit()
    }

    /// Init a Folio Reader Container from a storyboard, with an injected web server.
    ///
    /// A storyboard can only call `init?(coder:)`, so create the container from an
    /// `@IBSegueAction` or `UIStoryboard.instantiateViewController(identifier:creator:)` and call this
    /// initializer there. The storyboard scene's class must be `FolioReaderContainer` (or this subclass).
    ///
    ///     @IBSegueAction func makeReader(_ coder: NSCoder) -> FolioReaderContainer? {
    ///         FolioReaderContainer(coder: coder, config: config, folioReader: FolioReader(),
    ///                              epubPath: path, webServer: ReadiumGCDWebServer())
    ///     }
    public init?(coder: NSCoder, config: FolioReaderConfig, folioReader: FolioReader, epubPath path: String, webServer: ReadiumGCDWebServer) {
        self.readerConfig = config
        self.folioReader = folioReader
        self.epubPath = path
        self.book = FRBook()
        self.webServer = webServer

        super.init(coder: coder)

        finishInit()
    }

    /// Shared by the designated initializers that receive the configuration up front.
    private func finishInit() {
        self.resourceServer = EpubResourceServer(webServer: webServer, container: self)

        // Configure the folio reader.
        self.folioReader.readerContainer = self

        // Initialize the default reader options.
        if self.epubPath != "" {
            self.initialization()
        }
    }

    /// Called when a storyboard creates the container without an `@IBSegueAction` or creator.
    ///
    /// The container then creates its own `ReadiumGCDWebServer`, and `setupConfig(_:epubPath:)`
    /// must be called afterwards. Prefer `init?(coder:config:folioReader:epubPath:webServer:)`,
    /// which lets the app inject the web server like the other initializers.
    required public init?(coder aDecoder: NSCoder) {
        self.readerConfig = FolioReaderConfig()
        self.folioReader = FolioReader()
        self.epubPath = ""
        self.book = FRBook()
        self.webServer = ReadiumGCDWebServer()

        super.init(coder: aDecoder)

        self.resourceServer = EpubResourceServer(webServer: self.webServer, container: self)

        // Configure the folio reader.
        self.folioReader.readerContainer = self
    }

    deinit {
        // Closed before any page was shown.
        firstPageInterval?.end("closed")
        if let didBecomeActiveObserver = didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
    }

    /// Applies `ReaderPreferences.resolveScrollDirection` to `readerConfig`; returns whether the
    /// direction changed. The user's saved choice only counts while they may change the direction.
    @discardableResult
    func applyResolvedScrollDirection(isRtl: Bool) -> Bool {
        let direction = ReaderPreferences.resolveScrollDirection(
            saved: readerConfig.canChangeScrollDirection ? folioReader.preferences.savedScrollDirection : nil,
            configured: readerConfig.configuredScrollDirection,
            isRtl: isRtl
        )
        guard direction != readerConfig.scrollDirection else { return false }
        readerConfig.applyEffectiveScrollDirection(direction)
        return true
    }

    /// Common Initialization
    open func initialization() {
        // Register custom fonts
        FontBlaster.blast(bundle: Bundle.frameworkBundle())
    }

    /// Set the `FolioReaderConfig` and epubPath.
    ///
    /// - Parameters:
    ///   - config: Current Folio Reader configuration
    ///   - path: The ePub path on system. Must not be nil nor empty string.
	///   - unzipPath: Path to unzip the compressed epub.
    ///   - removeEpub: Should delete the original file after unzip? Default to `true` so the ePub will be unziped only once.
    open func setupConfig(_ config: FolioReaderConfig, epubPath path: String) {
        self.readerConfig = config
        self.folioReader = FolioReader()
        self.folioReader.readerContainer = self
        self.epubPath = path
        self.resourceServer = EpubResourceServer(webServer: self.webServer, container: self)
    }

    // MARK: - View life cicle

    override open func viewDidLoad() {
        super.viewDidLoad()
        observeApplicationDidBecomeActive()

        //let canChangeScrollDirection = self.readerConfig.canChangeScrollDirection
        //self.readerConfig.canChangeScrollDirection = self.readerConfig.isDirection(canChangeScrollDirection, canChangeScrollDirection, false)

        // The book isn't parsed yet; this is re-resolved with the real `isRtl` once it is.
        applyResolvedScrollDirection(isRtl: false)

        let hideBars = readerConfig.hideBars
        self.readerConfig.shouldHideNavigationOnTap = ((hideBars == true) ? true : self.readerConfig.shouldHideNavigationOnTap)

        let rootViewController = FolioReaderCenter(withContainer: self)
        let centerNavigationController = FolioReaderNavigationController(rootViewController: rootViewController)
        
        if readerConfig.debug.contains(.borderHighlight) {
            rootViewController.view.layer.borderWidth = 6
            rootViewController.view.layer.borderColor = UIColor.green.cgColor
        }
        self.centerViewController = rootViewController

        centerNavigationController.setNavigationBarHidden(false, animated: false)
        self.view.addSubview(centerNavigationController.view)
        self.addChild(centerNavigationController)
        if readerConfig.debug.contains(.borderHighlight) {
            centerNavigationController.view.layer.borderWidth = 4
            centerNavigationController.view.layer.borderColor = UIColor.blue.cgColor
            centerNavigationController.navigationBar.layer.borderWidth = 6
            centerNavigationController.navigationBar.layer.borderColor = UIColor.yellow.cgColor
        }
        centerNavigationController.didMove(toParent: self)
        
        self.centerNavigationController = centerNavigationController

        if (self.readerConfig.hideBars == true) {
            self.readerConfig.shouldHideNavigationOnTap = false
            self.centerNavigationController?.setNavigationBarHidden(true, animated: false)
            self.centerViewController?.pageIndicatorHeight = 0
        }

        // Read async book
        guard (self.epubPath.isEmpty == false) else {
            print("Epub path is nil.")
            self.errorOnLoad = true
            return
        }
        
        if readerConfig.debug.contains(.borderHighlight) {
            self.view.layer.borderWidth = 2
            self.view.layer.borderColor = UIColor.red.cgColor
        }
    }

    override open func viewWillAppear(_ animated: Bool) {
        defer {
            super.viewWillAppear(animated)
        }

        // Hosts can show the reader again without recreating it (tab switches, full-screen sheets).
        // Loading again would re-parse the book and re-apply the position it was opened at; the
        // server, stopped when the reader disappeared, starts again. A page whose web content process
        // died while the reader was hidden reloads now: becoming active skipped it, off screen.
        guard loadedEpubPath != epubPath else {
            restartResourceServer()
            centerViewController?.reloadPages(all: false)
            return
        }
        loadedEpubPath = epubPath

        Task {
            let bookName = (self.epubPath as NSString).lastPathComponent
            let openInterval = FolioSignpost.begin("BookOpen", bookName, log: FolioSignpost.milestones)
            self.firstPageInterval = FolioSignpost.begin("OpenToFirstPage", bookName, log: FolioSignpost.milestones)
            do {
                let archive: Archive
                do {
                    archive = try await Archive(url: URL(fileURLWithPath: self.epubPath), accessMode: .read, pathEncoding: .utf8)
                } catch {
                    throw FolioReaderError.errorInContainer
                }
                
                FolioLogger.log("BEFORE readEpub")
                let parseInterval = FolioSignpost.begin("ParseEpub", bookName, log: FolioSignpost.milestones)
                let parsedBook = try await FREpubParserArchive(book: self.book, archive: archive).readEpub(epubPath: self.epubPath)
                parseInterval.end()
                FolioLogger.log("AFTER readEpub")

                self.book = parsedBook
                
                self.folioReader.isReaderOpen = true
                
                // Reload data
                await MainActor.run {
                    if let position = self.readerConfig.savedPositionForCurrentBook {
                        self.folioReader.structuralStyle = position.structuralStyle
                        self.folioReader.structuralTrackingTocLevel = position.positionTrackingStyle
                        self.folioReader.readerCenter?.currentWebViewScrollPositions[position.pageNumber - 1] = position
                        
                        if let bookId = self.book.name?.deletingPathExtension {
                            position.takePrecedence = true
                            self.folioReader.save(readPosition: position, for: bookId)
                        }
                    }

                    if self.applyResolvedScrollDirection(isRtl: self.book.spine.isRtl) {
                        self.centerViewController?.collectionViewLayout.scrollDirection = .direction(withConfiguration: self.readerConfig)
                        self.centerViewController?.collectionViewLayout.invalidateLayout()
                    }

                    let structuralTrackingTocLevel = self.folioReader.structuralTrackingTocLevel
                    self.book.updateBundleInfo(rootTocLevel: structuralTrackingTocLevel.rawValue)
                    
                    //FIXME: temp fix for highlights
                    self.tempFixForHighlights()
                    
                    // Add audio player if needed
                    if self.book.hasAudio || self.readerConfig.enableTTS {
                        self.addAudioPlayer()
                    }
                    
                    self.folioReader.delegate?.folioReader?(self.folioReader, didFinishedLoading: self.book)
                    
                    self.resourceServer?.start()

                    self.centerViewController?.reloadData()
                    self.folioReader.isReaderReady = true
                    openInterval.end()
                }
            } catch {
                openInterval.end("error")
                self.firstPageInterval?.end("error")
                self.firstPageInterval = nil
                await MainActor.run {
                    self.errorOnLoad = true
                    self.alert(message: error.localizedDescription)
                }
            }
            
            if (self.errorOnLoad == true) {
                await MainActor.run {
                    self.dismiss()
                }
            }
        }
    }
    
    override open func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        resourceServer?.stop()
    }

    /// Starts the resource server again if it doesn't listen, on the pages' port if it can, and
    /// reloads the pages if it had to move.
    func restartResourceServer() {
        guard folioReader.isReaderReady, let resourceServer = resourceServer, !resourceServer.isListening else { return }
        if resourceServer.start() {
            centerViewController?.reloadPages(all: true)
        }
    }

    /// Returning from the background: the server's own restart may have failed to bind (it is
    /// ignored), and a page whose web content process was reclaimed waits to be reloaded.
    private func observeApplicationDidBecomeActive() {
        guard didBecomeActiveObserver == nil else { return }
        didBecomeActiveObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.viewIfLoaded?.window != nil else { return }
            self.restartResourceServer()
            self.centerViewController?.reloadPages(all: false)
        }
    }

    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !self.folioReader.isReaderOpen {
        }
        
//        if (self.errorOnLoad == true) {
//            self.dismiss()
//        }
    }

    func tempFixForHighlights() {
        guard let bookId = (self.book.name as NSString?)?.deletingPathExtension else {
            return
        }
        
        let provider = self.folioReader.highlightProvider
        let reader = self.folioReader
        let book = self.book
        Task {
            let highlights = await provider?.highlights(bookId: bookId, page: nil, for: reader) ?? []
            for highlight in highlights {
                if highlight.spineName.isEmpty || highlight.spineName == "TODO" || highlight.cfiStart?.hasPrefix("/2") == false || highlight.cfiEnd?.hasPrefix("/2") == false {
                    if highlight.spineName == "TODO", highlight.page > 1 {
                        highlight.page -= 1
                    }
                    if let resHref = book.spine.spineReferences[safe: highlight.page - 1]?.resource.href,
                       let opfResource = book.opfResource,
                       let opfUrl = URL(string: opfResource.href),
                       let resUrl = URL(string: resHref, relativeTo: opfUrl) {
                        highlight.spineName = resUrl.absoluteString.replacingOccurrences(of: "//", with: "")
                        while highlight.spineName.hasPrefix("/") {
                            highlight.spineName.removeFirst()
                        }
                        if let cfiStart = highlight.cfiStart, cfiStart.hasPrefix("/2") == false {
                            highlight.cfiStart = "/2\(cfiStart)"
                        }
                        if let cfiEnd = highlight.cfiEnd, cfiEnd.hasPrefix("/2") == false {
                            highlight.cfiEnd = "/2\(cfiEnd)"
                        }
                        highlight.date += 0.001
                    }
                    print("\(#function) fixHighlight \(highlight.page) \(highlight.spineName) \(highlight.cfiStart ?? "Nil") \(highlight.cfiEnd ?? "Nil") \(highlight.style) \(highlight.content.prefix(10))")
                    _ = try? await provider?.addHighlight(highlight, for: reader)
                }
            }
        }
    }
    
    /**
     Initialize the media player
     */
    func addAudioPlayer() {
        self.audioPlayer = FolioReaderAudioPlayer(withFolioReader: self.folioReader, book: self.book)
        self.folioReader.readerAudioPlayer = audioPlayer
    }

    // MARK: - Status Bar

    override open var prefersStatusBarHidden: Bool {
        return false
    }

    override open var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return UIStatusBarAnimation.slide
    }

    override open var preferredStatusBarStyle: UIStatusBarStyle {
        return self.folioReader.isNight(.lightContent, .default)
    }

    override open var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return self.centerNavigationController?.supportedInterfaceOrientations ?? .all
    }
    
    override open var shouldAutorotate: Bool {
        return self.centerNavigationController?.shouldAutorotate ?? false
    }

}

extension FolioReaderContainer {
    func alert(message: String) {
        let alertController = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: UIAlertController.Style.alert
        )
        let action = UIAlertAction(title: "Close", style: UIAlertAction.Style.destructive) { [weak self]
            (result : UIAlertAction) -> Void in
            self?.dismiss()
        }
        alertController.addAction(action)
        
        let ignoreAction = UIAlertAction(title: "Ignore", style: .default) { action in
            alertController.dismiss()
        }
        alertController.addAction(ignoreAction)
        
        self.present(alertController, animated: true, completion: nil)
    }
}
