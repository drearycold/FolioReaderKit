//
//  FolioReaderKit.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 08/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import Foundation
import FolioEPUBCore
import UIKit
import ReadiumGCDWebServer

// MARK: - Internal constants

internal let kApplicationDocumentsDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]

internal let kHighlightRange = 30
internal let kReuseCellIdentifier = "com.folioreader.Cell.ReuseIdentifier"
internal let kReusePrologueCellIdentifier = "com.folioreader.Cell.Prologue.ReuseIdentifier"
internal let kReuseHeaderFooterIdentifier = "com.folioreader.HeaderFooter.ReuseIdentifier"

/// Defines the media overlay and TTS selection
///
/// - `default`: The background is colored
/// - underline: The underlined is colored
/// - textColor: The text is colored
public enum MediaOverlayStyle: Int {
    case `default`
    case underline
    case textColor

    init() {
        self = .default
    }

    func className() -> String {
        return "mediaOverlayStyle\(self.rawValue)"
    }
}

struct FontFamilyInfo {
    let familyName: String
    let localizedName: String?
    let regularFont: UIFont
}

public enum StyleOverrideTypes: Int, CaseIterable {
    case None           //0
    case PNode          //1
    case PlusTD         //2
    case PlusSPAN       //3
    case AllText        //4
    
    var description: String {
        get {
            switch(self) {
            case .None:
                return "none"
            case .PNode:
                return "only <p>"
            case .PlusTD:
                return "+ <td>"
            case .PlusSPAN:
                return "+ <span>"
            case .AllText:
                return "all text"
            }
        }
    }
}

public enum NavigationMenuBookListStyle: Int, CaseIterable {
    case Grid = 0
    case List = 1
}

/// FolioReader actions delegate
@objc public protocol FolioReaderDelegate: AnyObject {
    
    /// Did finished loading book.
    ///
    /// - Parameters:
    ///   - folioReader: The FolioReader instance
    ///   - book: The Book instance
    @objc optional func folioReader(_ folioReader: FolioReader, didFinishedLoading book: FRBook)
    
    /// Called when reader did closed.
    ///
    /// - Parameter folioReader: The FolioReader instance
    @objc optional func folioReaderDidClose(_ folioReader: FolioReader)
    
    /// AD
    @objc optional func folioReaderAdView(_ folioReader: FolioReader) -> UIView?
    
    @objc optional func folioReaderAdPresent(_ folioReader: FolioReader)
    
    /// Providers
    @objc optional func folioReaderHighlightProvider(_ folioReader: FolioReader) -> FolioReaderHighlightProvider
    
    @objc optional func folioReaderBookmarkProvider(_ folioReader: FolioReader) -> FolioReaderBookmarkProvider
    
    @objc optional func folioReaderPreferenceProvider(_ folioReader: FolioReader) -> FolioReaderPreferenceProvider
    
    @objc optional func folioReaderReadPositionProvider(_ folioReader: FolioReader) -> FolioReaderReadPositionProvider
}

/// Main Library class with some useful constants and methods
public class FolioReader: NSObject {

    public static let FontSizes = ["15.5px", "17px", "18.5px", "20px", "22px", "24px", "26px", "28px", "30.5px", "33px", "35.5px"]
    public static let DefaultFontSize = FolioReader.FontSizes[3]
    public static let DefaultFontWeight = "500"
    public static let DefaultLetterSpacing = 2
    public static let DefaultLineHeight = 3
    public static let DefaultTextIndent = 2

    public override init() { }

    public lazy var preferences = ReaderPreferences(folioReader: self)

    /// Read-position saves run here one at a time, in order, off the main thread.
    let readPositionSaveQueue = DispatchQueue(label: "FolioReaderKit.readPositionSave", qos: .utility)

    deinit {
        removeObservers()
    }

    /// FolioReaderDelegate
    open weak var delegate: FolioReaderDelegate?
    
    var readerContainer: FolioReaderContainer?
    open weak var readerAudioPlayer: FolioReaderAudioPlayer?
    open weak var readerCenter: FolioReaderCenter? {
        return self.readerContainer?.centerViewController
    }
    open weak var readerConfig: FolioReaderConfig? {
        return self.readerContainer?.readerConfig
    }
    
    /// Check if reader is open
    var isReaderOpen = false

    /// Check if reader is open and ready
    var isReaderReady = false

    /// Check if layout needs to change to fit Right To Left
    var needsRTLChange: Bool {
        return (self.readerContainer?.book.spine.isRtl == true && (true || self.readerContainer?.readerConfig.scrollDirection == .horizontalWithPagedContent))
    }

    open func isNight<T>(_ f: T, _ l: T) -> T {
        return (self.nightMode == true ? f : l)
    }

    // Add necessary observers
    fileprivate func addObservers() {
        removeObservers()
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillLeaveForeground(_:)), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillLeaveForeground(_:)), name: UIApplication.willTerminateNotification, object: nil)
    }

    /// Saves the reader state when the app leaves the foreground. A handler of its own: with
    /// `saveReaderState(completion:)` as the selector, the notification arrived where the closure
    /// goes and was called and released as one, which crashed the app.
    @objc private func applicationWillLeaveForeground(_ notification: Notification) {
        saveReaderState()
    }

    /// Remove necessary observers
    fileprivate func removeObservers() {
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willTerminateNotification, object: nil)
    }
}

// MARK: - Present FolioReader

extension FolioReader {

    /// Present a Folio Reader Container modally on a Parent View Controller.
    ///
    /// - Parameters:
    ///   - parentViewController: View Controller that will present the reader container.
    ///   - epubPath: String representing the path on the disk of the ePub file. Must not be nil nor empty string.
    ///   - config: FolioReader configuration.
    ///   - animated: Pass true to animate the presentation; otherwise, pass false.
    ///   - webServer: Local server for this reader instance. Use a distinct `ReadiumGCDWebServer` per concurrent reader.
    ///
    /// For concurrent readers, also use distinct `FolioReaderConfig.identifier` values and identifier-aware
    /// persistence providers so settings, highlights, bookmarks, and positions do not overwrite each other.
    public func presentReader(parentViewController: UIViewController, withEpubPath epubPath: String, andConfig config: FolioReaderConfig, animated: Bool = true, folioReaderCenterDelegate: FolioReaderCenterDelegate?, webServer: ReadiumGCDWebServer) {
        let readerContainer = FolioReaderContainer(withConfig: config, folioReader: self, epubPath: epubPath, webServer: webServer)
        readerContainer.modalPresentationStyle = .fullScreen
        self.readerContainer = readerContainer
        
        parentViewController.present(readerContainer, animated: animated, completion: nil)
        addObservers()
    }
    
    /// Prepares a reader container without presenting it. Use a distinct `ReadiumGCDWebServer` per concurrent reader.
    public func prepareReader(parentViewController: UIViewController, withEpubPath epubPath: String, andConfig config: FolioReaderConfig, animated: Bool = true, folioReaderCenterDelegate: FolioReaderCenterDelegate?, webServer: ReadiumGCDWebServer) {
        let readerContainer = FolioReaderContainer(withConfig: config, folioReader: self, epubPath: epubPath, webServer: webServer)
        self.readerContainer = readerContainer
        
        addObservers()
    }
}

// MARK: -  Getters and setters for stored values

extension FolioReader {

    @available(*, deprecated, message: "Use preferences instead")
    public var nightMode: Bool {
        get { return preferences.nightMode }
        set { preferences.nightMode = newValue }
    }
    
    @available(*, deprecated, message: "Use preferences instead")
    public var themeMode: Int {
        get { return preferences.themeMode }
        set { preferences.themeMode = newValue }
    }

    @available(*, deprecated, message: "Use preferences instead")
    public var currentFont: String {
        get { return preferences.currentFont }
        set { preferences.currentFont = newValue }
    }

    @available(*, deprecated, message: "Use preferences instead")
    public var currentFontSize: String {
        get { return preferences.currentFontSize }
        set { preferences.currentFontSize = newValue }
    }
    
    @available(*, deprecated, message: "Use preferences instead")
    public var currentFontSizeOnly: Int {
        return preferences.currentFontSizeOnly
    }

    @available(*, deprecated, message: "Use preferences instead")
    public var currentFontWeight: String {
        get { return preferences.currentFontWeight }
        set { preferences.currentFontWeight = newValue }
    }
    
    @available(*, deprecated, message: "Use preferences instead")
    public var currentAudioRate: Int {
        get { return preferences.currentAudioRate }
        set { preferences.currentAudioRate = newValue }
    }

    @available(*, deprecated, message: "Use preferences instead")
    public var currentHighlightStyle: Int {
        get { return preferences.currentHighlightStyle }
        set { preferences.currentHighlightStyle = newValue }
    }

    @available(*, deprecated, message: "Use preferences instead")
    public var currentMediaOverlayStyle: MediaOverlayStyle {
        get { return preferences.currentMediaOverlayStyle }
        set { preferences.currentMediaOverlayStyle = newValue }
    }

    @available(*, deprecated, message: "Use preferences instead")
    public var defaultScrollDirection: FolioReaderScrollDirection {
        return preferences.defaultScrollDirection
    }

    @available(*, deprecated, message: "Use preferences instead")
    public var currentScrollDirection: Int {
        get { return preferences.currentScrollDirection }
        set { preferences.currentScrollDirection = newValue }
    }

    @available(*, deprecated, message: "Use preferences instead")
    public var currentNavigationMenuIndex: Int {
        get { return preferences.currentNavigationMenuIndex }
        set { preferences.currentNavigationMenuIndex = newValue }
    }
    
    @available(*, deprecated, message: "Use preferences instead")
    public var currentAnnotationMenuIndex: Int {
        get { return preferences.currentAnnotationMenuIndex }
        set { preferences.currentAnnotationMenuIndex = newValue }
    }
    
    @available(*, deprecated, message: "Use preferences instead")
    public var currentNavigationMenuBookListStyle: NavigationMenuBookListStyle {
        get { return preferences.currentNavigationMenuBookListStyle }
        set { preferences.currentNavigationMenuBookListStyle = newValue }
    }
    
    @available(*, deprecated, message: "Use preferences instead")
    public var currentVMarginLinked: Bool {
        get { return preferences.currentVMarginLinked }
        set { preferences.currentVMarginLinked = newValue }
    }
    
    @available(*, deprecated, message: "Use preferences instead")
    public var defaultMarginTop: Int {
        return preferences.defaultMarginTop
    }

    @available(*, deprecated, message: "Use preferences instead")
    public var currentMarginTop: Int {
        get { return preferences.currentMarginTop }
        set { preferences.currentMarginTop = newValue }
    }

    @available(*, deprecated, message: "Use preferences instead")
    public var defaultMarginBottom: Int {
        return preferences.defaultMarginBottom
    }

    @available(*, deprecated, message: "Use preferences instead")
    public var currentMarginBottom: Int {
        get { return preferences.currentMarginBottom }
        set { preferences.currentMarginBottom = newValue }
    }

    @available(*, deprecated, message: "Use preferences instead")
    public var currentHMarginLinked: Bool {
        get { return preferences.currentHMarginLinked }
        set { preferences.currentHMarginLinked = newValue }
    }
    
    @available(*, deprecated, message: "Use preferences instead")
    public var defaultMarginLeft: Int {
        return preferences.defaultMarginLeft
    }

    @available(*, deprecated, message: "Use preferences instead")
    public var currentMarginLeft: Int {
        get { return preferences.currentMarginLeft }
        set { preferences.currentMarginLeft = newValue }
    }

    @available(*, deprecated, message: "Use preferences instead")
    public var defaultMarginRight: Int {
        return preferences.defaultMarginRight
    }

    @available(*, deprecated, message: "Use preferences instead")
    public var currentMarginRight: Int {
        get { return preferences.currentMarginRight }
        set { preferences.currentMarginRight = newValue }
    }
    
    @available(*, deprecated, message: "Use preferences instead")
    public var currentLetterSpacing: Int {
        get { return preferences.currentLetterSpacing }
        set { preferences.currentLetterSpacing = newValue }
    }
    
    @available(*, deprecated, message: "Use preferences instead")
    public var currentLineHeight: Int {
        get { return preferences.currentLineHeight }
        set { preferences.currentLineHeight = newValue }
    }

    @available(*, deprecated, message: "Use preferences instead")
    public var currentTextIndent: Int {
        get { return preferences.currentTextIndent }
        set { preferences.currentTextIndent = newValue }
    }
    
    @available(*, deprecated, message: "Use preferences instead")
    public var doWrapPara: Bool {
        get { return preferences.doWrapPara }
        set { preferences.doWrapPara = newValue }
    }
    
    @available(*, deprecated, message: "Use preferences instead")
    public var doClearClass: Bool {
        get { return preferences.doClearClass }
        set { preferences.doClearClass = newValue }
    }
    
    @available(*, deprecated, message: "Use preferences instead")
    public var styleOverride: StyleOverrideTypes {
        get { return preferences.styleOverride }
        set { preferences.styleOverride = newValue }
    }
    
    @available(*, deprecated, message: "use delegate")
    @objc dynamic open var savedPositionForCurrentBook: FolioReaderReadPosition? {
        get { return preferences.savedPositionForCurrentBook }
        set { preferences.savedPositionForCurrentBook = newValue }
    }
    
    @available(*, deprecated, message: "Use preferences instead")
    public var structuralStyle: FolioReaderStructuralStyle {
        get { return preferences.structuralStyle }
        set { preferences.structuralStyle = newValue }
    }
    
    @available(*, deprecated, message: "Use preferences instead")
    public var structuralTrackingTocLevel: FolioReaderPositionTrackingStyle {
        get { return preferences.structuralTrackingTocLevel }
        set { preferences.structuralTrackingTocLevel = newValue }
    }
}

// MARK: - Exit, save and close FolioReader

extension FolioReader {

    /// Centralizes the persistence logic of read positions safely.
    ///
    /// Saves are serialized: each clears the other positions' `takePrecedence` and then stores its
    /// own, so with saves in flight at once the last one called wins and only it keeps precedence.
    public func save(readPosition position: FolioReaderReadPosition, for bookId: String) {
        guard let provider = self.delegate?.folioReaderReadPositionProvider?(self) else { return }
        
        readPositionSaveQueue.async { [weak self, provider, position] in
            guard let self = self else { return }
            let positions = provider.folioReaderReadPosition(self, allByBookId: bookId)
            for pos in positions where pos.takePrecedence {
                pos.takePrecedence = false
                provider.folioReaderReadPosition(self, bookId: bookId, set: pos, completion: nil)
            }
            provider.folioReaderReadPosition(self, bookId: bookId, set: position, completion: nil)
        }
    }

    /// Save Reader state, book, page and scroll offset.
    @objc open func saveReaderState(completion: (() -> Void)? = nil) {
        guard isReaderOpen,
              let readerCenter = self.readerCenter,
              let currentPage = readerCenter.currentPage,
              let webView = currentPage.webView,
              currentPage.layoutAdapting == nil,
              webView.isHidden == false
        else {
            //haven't finished loading, do not overwrite position
            completion?()
            return
        }

        // Measuring now would record the start of the restored line or page, before the position.
        if let pinned = currentPage.pinnedPosition {
            if let bookId = readerCenter.book.name?.deletingPathExtension {
                save(readPosition: pinned, for: bookId)
            }
            completion?()
            return
        }

        print("saveReaderState before getVisibleCFI \(Date())")
        
        currentPage.getWebViewScrollPosition() { position in
            print("saveReaderState after getVisibleCFI \(Date())")

            print("saveReaderState position cfi=\(position.cfi)")
            
            if let bookId = self.readerCenter?.book.name?.deletingPathExtension {
                self.save(readPosition: position, for: bookId)
            }

            completion?()
        }
    }

    /// Closes and save the reader current instance.
    public func close() {
        self.saveReaderState() {
            self.isReaderOpen = false
            self.isReaderReady = false
            self.readerAudioPlayer?.stop(immediate: true)
            self.delegate?.folioReaderDidClose?(self)
        }
    }
}

// MARK: - Providers

extension FolioReader {

    public var highlightProvider: FolioReaderHighlightProviding? {
        guard let provider = self.delegate?.folioReaderHighlightProvider?(self) else { return nil }
        return FolioReaderHighlightProviderWrapper(provider)
    }

    public var bookmarkProvider: FolioReaderBookmarkProviding? {
        guard let provider = self.delegate?.folioReaderBookmarkProvider?(self) else { return nil }
        return FolioReaderBookmarkProviderWrapper(provider)
    }
}
