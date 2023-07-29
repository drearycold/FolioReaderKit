//
//  FolioReaderContainer.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 15/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import FontBlaster
import ZIPFoundation

/// Reader container
open class FolioReaderContainer: UIViewController {
    var shouldHideStatusBar = true
    
    // Mark those property as public so they can accessed from other classes/subclasses.
    public var epubPath: String
    public var book: FRBook
    
    public var centerNavigationController: UINavigationController!
    public var centerViewController: FolioReaderCenter!
    public var audioPlayer: FolioReaderAudioPlayer?
    
    public var readerConfig: FolioReaderConfig
    public var folioReader: FolioReader

    fileprivate var errorOnLoad = false

    // MARK: - Init

    /// Init a Folio Reader Container
    ///
    /// - Parameters:
    ///   - config: Current Folio Reader configuration
    ///   - folioReader: Current instance of the FolioReader kit.
    ///   - path: The ePub path on system. Must not be nil nor empty string.
	///   - unzipPath: Path to unzip the compressed epub.
    ///   - removeEpub: Should delete the original file after unzip? Default to `true` so the ePub will be unziped only once.
    public init(withConfig config: FolioReaderConfig, folioReader: FolioReader, epubPath path: String) {
        self.readerConfig = config
        self.folioReader = folioReader
        self.epubPath = path
        self.book = FRBook()

        super.init(nibName: nil, bundle: Bundle.frameworkBundle())

        // Configure the folio reader.
        self.folioReader.readerContainer = self

        // Initialize the default reader options.
        if self.epubPath != "" {
            self.initialization()
        }
    }

    required public init?(coder aDecoder: NSCoder) {
        // When a FolioReaderContainer object is instantiated from the storyboard this function is called before.
        // At this moment, we need to initialize all non-optional objects with default values.
        // The function `setupConfig(config:epubPath:removeEpub:)` MUST be called afterward.
        // See the ExampleFolioReaderContainer.swift for more information?
        self.readerConfig = FolioReaderConfig()
        self.folioReader = FolioReader()
        self.epubPath = ""
        self.book = FRBook()

        super.init(coder: aDecoder)

        // Configure the folio reader.
        self.folioReader.readerContainer = self
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
    }

    // MARK: - View life cicle

    override open func viewDidLoad() {
        super.viewDidLoad()

        //let canChangeScrollDirection = self.readerConfig.canChangeScrollDirection
        //self.readerConfig.canChangeScrollDirection = self.readerConfig.isDirection(canChangeScrollDirection, canChangeScrollDirection, false)

        // If user can change scroll direction use the last saved
        if self.readerConfig.canChangeScrollDirection == true {
            var scrollDirection = FolioReaderScrollDirection(rawValue: self.folioReader.currentScrollDirection) ?? .horizontalWithScrollContent
            if (scrollDirection == .defaultVertical && self.readerConfig.scrollDirection != .defaultVertical) {
                scrollDirection = self.readerConfig.scrollDirection
            }

            self.readerConfig.scrollDirection = scrollDirection
        }

        let hideBars = readerConfig.hideBars
        self.readerConfig.shouldHideNavigationOnTap = ((hideBars == true) ? true : self.readerConfig.shouldHideNavigationOnTap)

        let rootViewController = FolioReaderCenter(withContainer: self)
        let centerNavigationController = UINavigationController(rootViewController: rootViewController)
        
        if readerConfig.debug.contains(.borderHighlight) {
            rootViewController.view.layer.borderWidth = 6
            rootViewController.view.layer.borderColor = UIColor.green.cgColor
        }
        self.centerViewController = rootViewController

        centerNavigationController.setNavigationBarHidden(self.readerConfig.shouldHideNavigationOnTap, animated: false)
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
            self.navigationController?.navigationBar.isHidden = true
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
        
        DispatchQueue.global(qos: .userInitiated).async {

//                do {
//                    guard let archive = Archive(url: URL(fileURLWithPath: self.epubPath), accessMode: .read, preferredEncoding: .utf8) else { throw FolioReaderError.errorInContainer }
//                    folioLogger("BEFORE readEpub")
//                    let parsedBook = try FREpubParserArchive(book: FRBook(), archive: archive).readEpubLight(epubPath: self.epubPath)
//                    folioLogger("AFTER readEpub")
//
//                    self.book = parsedBook
//                } catch {
//                    self.errorOnLoad = true
//                }
            
            do {
                guard let archive = Archive(url: URL(fileURLWithPath: self.epubPath), accessMode: .read, preferredEncoding: .utf8) else { throw FolioReaderError.errorInContainer }
                
//                    guard let archive = self.book.epubArchive else { throw FolioReaderError.errorInContainer }
                
                folioLogger("BEFORE readEpub")
                let parsedBook = try FREpubParserArchive(book: self.book, archive: archive).readEpub(epubPath: self.epubPath)
                folioLogger("AFTER readEpub")

                self.book = parsedBook
                
                self.folioReader.isReaderOpen = true
                
                // Reload data
                DispatchQueue.main.async {
                    if let position = self.readerConfig.savedPositionForCurrentBook {
                        self.folioReader.structuralStyle = position.structuralStyle
                        self.folioReader.structuralTrackingTocLevel = position.positionTrackingStyle
                        self.folioReader.readerCenter?.currentWebViewScrollPositions[position.pageNumber - 1] = position
                        position.takePrecedence = true
                        self.folioReader.savedPositionForCurrentBook = position
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
                    
                    self.centerViewController.reloadData()
                    self.folioReader.isReaderReady = true
                }
            } catch {
                self.errorOnLoad = true
                self.alert(message: error.localizedDescription)
            }
            
            if (self.errorOnLoad == true) {
                self.dismiss()
            }
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
        guard let highlightProvider = self.folioReader.delegate?.folioReaderHighlightProvider?(self.folioReader),
           let bookId = (self.book.name as NSString?)?.deletingPathExtension
        else {
            return
        }
        
        highlightProvider.folioReaderHighlight(self.folioReader, allByBookId: bookId, andPage: nil)
            .filter {
                $0.spineName == nil || $0.spineName.isEmpty || $0.spineName == "TODO" || $0.cfiStart?.hasPrefix("/2") == false || $0.cfiEnd?.hasPrefix("/2") == false
            }.forEach { highlight in
                if highlight.spineName == "TODO", highlight.page > 1 {
                    highlight.page -= 1
                }
                if let resHref = self.book.spine.spineReferences[safe: highlight.page - 1]?.resource.href,
                   let opfUrl = URL(string: self.book.opfResource.href),
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
                print("\(#function) fixHighlight \(highlight.page) \(highlight.spineName) \(highlight.cfiStart) \(highlight.cfiEnd) \(highlight.style) \(highlight.content.prefix(10))")
                highlightProvider.folioReaderHighlight(self.folioReader, added: highlight, completion: nil)
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
        return (self.readerConfig.shouldHideNavigationOnTap == false ? false : self.shouldHideStatusBar)
    }

    override open var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return UIStatusBarAnimation.slide
    }

    override open var preferredStatusBarStyle: UIStatusBarStyle {
        return self.folioReader.isNight(.lightContent, .default)
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
