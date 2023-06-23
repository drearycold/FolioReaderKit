//
//  FolioReaderKit.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 08/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import Foundation
import UIKit

// MARK: - Internal constants

internal let kApplicationDocumentsDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]

internal let kHighlightRange = 30
internal let kReuseCellIdentifier = "com.folioreader.Cell.ReuseIdentifier"
internal let kReuseHeaderFooterIdentifier = "com.folioreader.HeaderFooter.ReuseIdentifier"

public enum FolioReaderError: Error, LocalizedError {
    case bookNotAvailable
    case errorInContainer
    case errorInOpf
    case authorNameNotAvailable
    case coverNotAvailable
    case invalidImage(path: String)
    case titleNotAvailable
    case fullPathEmpty

    public var errorDescription: String? {
        switch self {
        case .bookNotAvailable:
            return "Book not found"
        case .errorInContainer, .errorInOpf:
            return "Invalid book format"
        case .authorNameNotAvailable:
            return "Author name not available"
        case .coverNotAvailable:
            return "Cover image not available"
        case let .invalidImage(path):
            return "Invalid image at path: " + path
        case .titleNotAvailable:
            return "Book title not available"
        case .fullPathEmpty:
            return "Book corrupted"
        }
    }
}

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

    public override init() { }

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
        return (self.readerContainer?.book.spine.isRtl == true && (true || self.readerContainer?.readerConfig.scrollDirection == .horitonzalWithPagedContent))
    }

    func isNight<T>(_ f: T, _ l: T) -> T {
        return (self.nightMode == true ? f : l)
    }

    // Add necessary observers
    fileprivate func addObservers() {
        removeObservers()
        NotificationCenter.default.addObserver(self, selector: #selector(saveReaderState), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(saveReaderState), name: UIApplication.willTerminateNotification, object: nil)
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
	///   - unzipPath: Path to unzip the compressed epub.
    ///   - config: FolioReader configuration.
    ///   - shouldRemoveEpub: Boolean to remove the epub or not. Default true.
    ///   - animated: Pass true to animate the presentation; otherwise, pass false.
    open func presentReader(parentViewController: UIViewController, withEpubPath epubPath: String, andConfig config: FolioReaderConfig, animated: Bool = true, folioReaderCenterDelegate: FolioReaderCenterDelegate?) {
        let readerContainer = FolioReaderContainer(withConfig: config, folioReader: self, epubPath: epubPath)
        readerContainer.modalPresentationStyle = .fullScreen
        self.readerContainer = readerContainer
        
        parentViewController.present(readerContainer, animated: animated, completion: nil)
        addObservers()
    }
    
    open func prepareReader(parentViewController: UIViewController, withEpubPath epubPath: String, andConfig config: FolioReaderConfig, animated: Bool = true, folioReaderCenterDelegate: FolioReaderCenterDelegate?) {
        let readerContainer = FolioReaderContainer(withConfig: config, folioReader: self, epubPath: epubPath)
        self.readerContainer = readerContainer
        
        addObservers()
    }
}

// MARK: -  Getters and setters for stored values

extension FolioReader {

    /// Check if current theme is Night mode
    open var nightMode: Bool {
        get {
            delegate?.folioReaderPreferenceProvider?(self).preference(nightMode: false) ?? false
        }
        set (value) {
            delegate?.folioReaderPreferenceProvider?(self).preference(setNightMode: value)

            if let readerCenter = self.readerCenter {
                UIView.animate(withDuration: 0.6, animations: {
                    // _ = readerCenter.currentPage?.webView?.js("nightMode(\(self.nightMode))")
                    readerCenter.pageIndicatorView?.reloadColors()
                    readerCenter.configureNavBar()
                    readerCenter.scrollScrubber?.reloadColors()
                    readerCenter.collectionView.backgroundColor = (self.nightMode == true ? self.readerContainer?.readerConfig.nightModeBackground : UIColor.white)
                }, completion: { (finished: Bool) in
                    NotificationCenter.default.post(name: Notification.Name(rawValue: "needRefreshPageMode"), object: nil)
                })
            }
        }
    }
    
    open var themeMode: Int {
        get {
            return delegate?.folioReaderPreferenceProvider?(self).preference(themeMode: 1) ?? 1
        }
        set (value) {
            delegate?.folioReaderPreferenceProvider?(self).preference(setThemeMode: value)
            
            guard let readerCenter = self.readerCenter,
                  let backgroundColor = self.readerConfig?.themeModeBackground[self.themeMode] else { return }
            
            UIView.transition(
                with: readerCenter.menuBarController.tabBar,
                duration: 0.6,
                options: .beginFromCurrentState.union(.transitionCrossDissolve),
                animations: { () -> Void in
                    readerCenter.menuBarController.tabBar.barTintColor = backgroundColor
                },
                completion: nil
            )
            
            readerCenter.menuTabs.forEach { menu in
                UIView.transition(
                    with: menu.view,
                    duration: 0.6,
                    options: .beginFromCurrentState.union(.transitionCrossDissolve),
                    animations: { () -> Void in
                        menu.reloadColors()
                    },
                    completion: nil
                )
            }
            
            UIView.animate(withDuration: 0.6, animations: {
                _ = readerCenter.currentPage?.webView?.js("themeMode(\(self.themeMode))")
                readerCenter.pageIndicatorView?.reloadColors()
                readerCenter.configureNavBar()
                readerCenter.scrollScrubber?.reloadColors()
                readerCenter.navigationItem.titleView?.subviews.forEach {
                    if let label = $0 as? UILabel {
                        label.textColor = self.readerConfig?.themeModeTextColor[self.themeMode]
                    }
                }
                
                readerCenter.collectionView.backgroundColor = backgroundColor
                
                if let page = readerCenter.currentPage {
                    page.panDeadZoneTop?.backgroundColor = backgroundColor
                    page.panDeadZoneBot?.backgroundColor = backgroundColor
                    page.panDeadZoneLeft?.backgroundColor = backgroundColor
                    page.panDeadZoneRight?.backgroundColor = backgroundColor
                }
            }, completion: { (finished: Bool) in
                NotificationCenter.default.post(name: Notification.Name(rawValue: "needRefreshPageMode"), object: nil)
            })
        }
    }

    open var currentFont: String {
        get {
            return delegate?.folioReaderPreferenceProvider?(self).preference(currentFont: "Georgia") ?? "Georgia"
        }
        set (fontFamilyName) {
            delegate?.folioReaderPreferenceProvider?(self).preference(setCurrentFont: fontFamilyName)
            readerCenter?.currentPage?.updateRuntimStyle(delay: 0.4)
        }
    }

    static let FontSizes = ["15.5px", "17px", "18.5px", "20px", "22px", "24px", "26px", "28px", "30.5px", "33px", "35.5px"]
    public static let DefaultFontSize = FolioReader.FontSizes[3]
    
    /// Check current font size. Default .m
    open var currentFontSize: String {
        get {
            return delegate?.folioReaderPreferenceProvider?(self).preference(currentFontSize: FolioReader.DefaultFontSize) ?? FolioReader.DefaultFontSize
        }
        set (fontSize) {
            delegate?.folioReaderPreferenceProvider?(self).preference(setCurrentFontSize: fontSize)
            readerCenter?.currentPage?.updateRuntimStyle(delay: 0.4)
        }
    }
    
    open var currentFontSizeOnly: Int {
        return Int(Double(currentFontSize.replacingOccurrences(of: "px", with: "")) ?? 20)
    }

    public static let DefaultFontWeight = "500"
    open var currentFontWeight: String {
        get {
            return delegate?.folioReaderPreferenceProvider?(self).preference(currentFontWeight: "500") ?? "500"
        }
        set (fontWeight) {
            delegate?.folioReaderPreferenceProvider?(self).preference(setCurrentFontWeight: fontWeight)
            readerCenter?.currentPage?.updateRuntimStyle(delay: 0.4)
        }
    }
    
    /// Check current audio rate, the speed of speech voice. Default 0
    open var currentAudioRate: Int {
        get {
            delegate?.folioReaderPreferenceProvider?(self).preference(currentAudioRate: 1) ?? 1
        }
        set (value) {
            delegate?.folioReaderPreferenceProvider?(self).preference(setCurrentAudioRate: value)
        }
    }

    /// Check the current highlight style.Default 0
    open var currentHighlightStyle: Int {
        get {
            return delegate?.folioReaderPreferenceProvider?(self)
                .preference(currentHighlightStyle: FolioReaderHighlightStyle.yellow.rawValue)
                ?? FolioReaderHighlightStyle.yellow.rawValue
        }
        set (value) {
            delegate?.folioReaderPreferenceProvider?(self).preference(setCurrentHighlightStyle: value)
        }
    }

    /// Check the current Media Overlay or TTS style
    open var currentMediaOverlayStyle: MediaOverlayStyle {
        get {
            guard let rawValue = delegate?.folioReaderPreferenceProvider?(self).preference(currentMediaOverlayStyle: MediaOverlayStyle.default.rawValue),
                let style = MediaOverlayStyle(rawValue: rawValue) else {
                return MediaOverlayStyle.default
            }
            return style
        }
        set (value) {
            delegate?.folioReaderPreferenceProvider?(self).preference(setCurrentMediaOverlayStyle: value.rawValue)
        }
    }

    open var defaultScrollDirection: FolioReaderScrollDirection {
        self.readerContainer?.book.spine.isRtl == true ? .horitonzalWithPagedContent : .horizontalWithScrollContent
    }
    /// Check the current scroll direction. Default .defaultVertical
    open var currentScrollDirection: Int {
        get {
            return delegate?.folioReaderPreferenceProvider?(self)
                .preference(currentScrollDirection: defaultScrollDirection.rawValue)
                ?? defaultScrollDirection.rawValue
        }
        set (value) {
            delegate?.folioReaderPreferenceProvider?(self).preference(setCurrentScrollDirection: value)

            let direction = FolioReaderScrollDirection(rawValue: currentScrollDirection) ?? defaultScrollDirection
            readerCenter?.currentPage?.setScrollDirection(direction)
        }
    }

    open var currentNavigationMenuIndex: Int {
        get {
            return delegate?.folioReaderPreferenceProvider?(self).preference(currentNavigationMenuIndex: 0) ?? 0
        }
        set (value) {
            delegate?.folioReaderPreferenceProvider?(self).preference(setCurrentNavigationMenuIndex: value)
        }
    }
    
    open var currentAnnotationMenuIndex: Int {
        get {
            return delegate?.folioReaderPreferenceProvider?(self).preference(currentAnnotationMenuIndex: 0) ?? 0
        }
        set (value) {
            delegate?.folioReaderPreferenceProvider?(self).preference(setCurrentAnnotationMenuIndex: value)
        }
    }
    
    /**
     0: Grid
     1: List
     */
    open var currentNavigationMenuBookListSyle: NavigationMenuBookListStyle {
        get {
            guard self.structuralStyle == .bundle else {
                return .List
            }
            let defaults: NavigationMenuBookListStyle = self.structuralTrackingTocLevel == .level1 ? .Grid : .List
            guard let rawValue = delegate?.folioReaderPreferenceProvider?(self).preference(currentNavigationMenuBookListSyle: defaults.rawValue),
                  let style = NavigationMenuBookListStyle(rawValue: rawValue)
            else { return defaults }
            return style
        }
        set (value) {
            delegate?.folioReaderPreferenceProvider?(self).preference(setCurrentNavigationMenuBookListStyle: value.rawValue)
        }
    }
    
    open var currentVMarginLinked: Bool {
        get {
            delegate?.folioReaderPreferenceProvider?(self).preference(currentVMarginLinked: true) ?? true
        }
        set (value) {
            delegate?.folioReaderPreferenceProvider?(self).preference(setCurrentVMarginLinked: value)
        }
    }
    
    public var defaultMarginTop: Int {
        (self.readerCenter?.traitCollection ?? UIScreen.main.traitCollection).verticalSizeClass == .regular ? 10 : 5    //5% for regular size, otherwise 2.5%
    }
    open var currentMarginTop: Int {
        get {
            let defaults = self.defaultMarginTop
            return delegate?.folioReaderPreferenceProvider?(self).preference(currentMarginTop: defaults) ?? defaults
        }
        set (value) {
            let newValue = max(0, min(50, value))
            delegate?.folioReaderPreferenceProvider?(self).preference(setCurrentMarginTop: newValue)
            guard currentVMarginLinked == false else { return }
            readerCenter?.currentPage?.byWritingMode(
                horizontal: { self.readerCenter?.currentPage?.updateViewerLayout(delay: 0.2) },
                vertical: { self.readerCenter?.currentPage?.updateRuntimStyle(delay: 0.4) }
            )
        }
    }

    public var defaultMarginBottom: Int {
        (self.readerCenter?.traitCollection ?? UIScreen.main.traitCollection).verticalSizeClass == .regular ? 10 : 5    //5% for regular size, otherwise 2.5%
    }
    open var currentMarginBottom: Int {
        get {
            let defaults = defaultMarginBottom
            return delegate?.folioReaderPreferenceProvider?(self).preference(currentMarginBottom: defaults) ?? defaults
        }
        set (value) {
            let newValue = max(0, min(50, value))
            delegate?.folioReaderPreferenceProvider?(self).preference(setCurrentMarginBottom: newValue)
            guard currentVMarginLinked == false else { return }
            readerCenter?.currentPage?.byWritingMode(
                horizontal: { self.readerCenter?.currentPage?.updateViewerLayout(delay: 0.2) },
                vertical: { self.readerCenter?.currentPage?.updateRuntimStyle(delay: 0.4) }
            )
        }
    }

    open var currentHMarginLinked: Bool {
        get {
            delegate?.folioReaderPreferenceProvider?(self).preference(currentHMarginLinked: true) ?? true
        }
        set (value) {
            delegate?.folioReaderPreferenceProvider?(self).preference(setCurrentHMarginLinked: value)
        }
    }
    
    public var defaultMarginLeft: Int {
        (self.readerCenter?.traitCollection ?? UIScreen.main.traitCollection).horizontalSizeClass == .regular ? 30 : 5    //15% for regular size, otherwise 2.5%
    }
    open var currentMarginLeft: Int {
        get {
            let defaults = self.defaultMarginLeft
            return delegate?.folioReaderPreferenceProvider?(self).preference(currentMarginLeft: defaults) ?? defaults
        }
        set (value) {
            let newValue = max(0, min(50, value))
            delegate?.folioReaderPreferenceProvider?(self).preference(setCurrentMarginLeft: newValue)
            guard currentHMarginLinked == false else { return }
            readerCenter?.currentPage?.byWritingMode(
                horizontal: { self.readerCenter?.currentPage?.updateRuntimStyle(delay: 0.4) },
                vertical: { self.readerCenter?.currentPage?.updateViewerLayout(delay: 0.2) }
            )
        }
    }

    public var defaultMarginRight: Int {
        (self.readerCenter?.traitCollection ?? UIScreen.main.traitCollection).horizontalSizeClass == .regular ? 30 : 5     //15% for regular size, otherwise 2.5%
    }
    open var currentMarginRight: Int {
        get {
            let defaults = self.defaultMarginRight
            return delegate?.folioReaderPreferenceProvider?(self).preference(currentMarginRight: defaults) ?? defaults
        }
        set (value) {
            let newValue = max(0, min(50, value))
            delegate?.folioReaderPreferenceProvider?(self).preference(setCurrentMarginRight: newValue)
            guard currentHMarginLinked == false else { return }
            readerCenter?.currentPage?.byWritingMode(
                horizontal: { self.readerCenter?.currentPage?.updateRuntimStyle(delay: 0.4) },
                vertical: { self.readerCenter?.currentPage?.updateViewerLayout(delay: 0.2) }
            )
        }
    }
    
    public static let DefaultLetterSpacing = 2
    open var currentLetterSpacing: Int {
        get {
            delegate?.folioReaderPreferenceProvider?(self).preference(currentLetterSpacing: 2) ?? 2
        }
        set (value) {
            delegate?.folioReaderPreferenceProvider?(self).preference(setCurrentLetterSpacing: value)
            readerCenter?.currentPage?.updateRuntimStyle(delay: 0.4)
        }
    }
    
    public static let DefaultLineHeight = 3
    open var currentLineHeight: Int {
        get {
            delegate?.folioReaderPreferenceProvider?(self).preference(currentLineHeight: 3) ?? 3
        }
        set (value) {
            delegate?.folioReaderPreferenceProvider?(self).preference(setCurrentLineHeight: value)
            readerCenter?.currentPage?.updateRuntimStyle(delay: 0.4)
        }
    }

    //in em
    public static let DefaultTextIndent = 2
    open var currentTextIndent: Int {
        get {
            delegate?.folioReaderPreferenceProvider?(self).preference(currentTextIndent: 2) ?? 2
        }
        set (value) {
            delegate?.folioReaderPreferenceProvider?(self).preference(setCurrentTextIndent: value)
            readerCenter?.currentPage?.updateRuntimStyle(delay: 0.4)
        }
    }
    
    open var doWrapPara: Bool {
        get {
            delegate?.folioReaderPreferenceProvider?(self).preference(doWrapPara: false) ?? false
        }
        set (value) {
            delegate?.folioReaderPreferenceProvider?(self).preference(setDoWrapPara: value)
        }
    }
    
    open var doClearClass: Bool {
        get {
            delegate?.folioReaderPreferenceProvider?(self).preference(doClearClass: true) ?? true
        }
        set (value) {
            delegate?.folioReaderPreferenceProvider?(self).preference(setDoClearClass: value)
        }
    }
    
    open var styleOverride: StyleOverrideTypes {
        get {
            guard let rawValue = delegate?.folioReaderPreferenceProvider?(self).preference(styleOverride: StyleOverrideTypes.PNode.rawValue),
                  let value = StyleOverrideTypes(rawValue: rawValue) else {
                return StyleOverrideTypes.PNode
            }
            return value
        }
        set (value) {
            delegate?.folioReaderPreferenceProvider?(self).preference(setStyleOverride: value.rawValue)
            readerCenter?.currentPage?.updateRuntimStyle(delay: 0.2)
        }
    }
    
    @available(*, deprecated, message: "use delegate")
    @objc dynamic open var savedPositionForCurrentBook: FolioReaderReadPosition? {
        get {
            guard let bookId = self.readerCenter?.book.name?.deletingPathExtension else { return nil }
            folioLogger("savedPositionForCurrentBook get")
            return delegate?.folioReaderReadPositionProvider?(self).folioReaderReadPosition(self, bookId: bookId)
        }
        set {
            guard let position = newValue,
                  let bookId = self.readerCenter?.book.name?.deletingPathExtension,
                  let provider = delegate?.folioReaderReadPositionProvider?(self) else { return }
            
            guard self.isReaderReady || position.takePrecedence else { return }
            
            if let debug = readerConfig?.debug, debug.contains(.functionTrace) {
                Thread.callStackSymbols.forEach {
                    folioLogger($0)
                }
                if position.bookProgress < 5.0 {
                    folioLogger(position.bookProgress.description)
                }
            }
            
            DispatchQueue.global().async {
                provider.folioReaderReadPosition(self, allByBookId: bookId)
                    .forEach {
                        guard $0.takePrecedence else { return }
                        folioLogger("savedPositionForCurrentBook clear")
                        $0.takePrecedence = false
                        provider.folioReaderReadPosition(self, bookId: bookId, set: $0, completion: nil)
                    }
                
                provider.folioReaderReadPosition(self, bookId: bookId, set: position, completion: nil)
            }
        }
    }
    
    open var structuralStyle: FolioReaderStructuralStyle {
        get {
            guard let rawValue = delegate?.folioReaderPreferenceProvider?(self).preference(structuralStyle: FolioReaderStructuralStyle.atom.rawValue),
                  let value = FolioReaderStructuralStyle(rawValue: rawValue) else {
                      return FolioReaderStructuralStyle.atom
                  }
            return value
        }
        set {
            delegate?.folioReaderPreferenceProvider?(self).preference(setStructuralStyle: newValue.rawValue)
        }
    }
    
    open var structuralTrackingTocLevel: FolioReaderPositionTrackingStyle {
        get {
            guard let rawValue = delegate?.folioReaderPreferenceProvider?(self).preference(structuralTocLevel: FolioReaderPositionTrackingStyle.linear.rawValue),
                  let value = FolioReaderPositionTrackingStyle(rawValue: rawValue) else {
                      return FolioReaderPositionTrackingStyle.linear
                  }
            return value
        }
        set {
            delegate?.folioReaderPreferenceProvider?(self).preference(setStructuralTocLevel: newValue.rawValue)
        }
    }
}

// MARK: - Exit, save and close FolioReader

extension FolioReader {

    /// Save Reader state, book, page and scroll offset.
    @objc open func saveReaderState(completion: (() -> Void)? = nil) {
        guard isReaderOpen,
              let readerCenter = self.readerCenter,
              let currentPage = readerCenter.currentPage,
              let webView = currentPage.webView,
              currentPage.layoutAdapting == false,
              webView.isHidden == false
        else {
            //haven't finished loading, do not overwrite position
            completion?()
            return
        }

        print("saveReaderState before getVisibleCFI \(Date())")
        
        currentPage.getWebViewScrollPosition() { position in
            print("saveReaderState after getVisibleCFI \(Date())")

            print("saveReaderState position cfi=\(position.cfi)")
            
            self.savedPositionForCurrentBook = position

            completion?()
        }
    }

    /// Closes and save the reader current instance.
    open func close() {
        self.saveReaderState() {
            self.isReaderOpen = false
            self.isReaderReady = false
            self.readerAudioPlayer?.stop(immediate: true)
            self.delegate?.folioReaderDidClose?(self)
        }
    }
}

// MARK: - CSS Style


extension FolioReader {
    
    
    func generateRuntimeStyle() -> String {
        let letterSpacing = Float(currentLetterSpacing * 2 * currentFontSizeOnly) / Float(100)
        let lineHeight = Decimal((currentLineHeight + 10) * 5) / 100 + 1    //1.5 ~ 2.05
        let textIndent = (letterSpacing + Float(currentFontSizeOnly)) * Float(currentTextIndent)
        let marginTopEm = Decimal(1)
        let marginBottonEm = lineHeight - 1
        
        
        var style = ""
        if styleOverride != .None {
            var tagSelector = "p"
            if styleOverride.rawValue >= StyleOverrideTypes.PlusTD.rawValue {
                tagSelector += ", td"
            }
            if styleOverride.rawValue >= StyleOverrideTypes.PlusSPAN.rawValue {
                tagSelector += ", td, span"
            }
            
        style += """
            \(tagSelector) {
                /*font-family: \(currentFont) !important;*/
                /*font-size: \(currentFontSize) !important;*/
                /*font-weight: \(currentFontWeight) !important;*/
                /*letter-spacing: \(letterSpacing)px !important;*/
                /*line-height: \(lineHeight) !important;*/
                /*text-indent: \(textIndent)px !important;*/
                /*text-align: justify !important;*/
                /*margin: \(marginTopEm)em 0 \(marginBottonEm)em 0 !important;*/
                /*-webkit-hyphens: auto !important;*/
            }
            
            span {
                /*letter-spacing: \(letterSpacing)px !important;*/
                /*line-height: \(lineHeight) !important;*/
            }
            
            """
        }
        if let pageWidth = readerCenter?.pageWidth/*, let pageHeight = readerCenter?.pageHeight*/ {
            let marginTop = 0 //CGFloat(currentMarginTop) / 200 * pageHeight
            let marginBottom = 0 //CGFloat(currentMarginBottom) / 200 * pageHeight
            let marginLeft = CGFloat(currentMarginLeft) / 200 * pageWidth
            let marginRight = CGFloat(currentMarginRight) / 200 * pageWidth
            
            style += """
            
            /*body {
                padding: \(marginTop)px \(marginRight)px \(marginBottom)px \(marginLeft)px !important;
                overflow: hidden !important;
            }
            
            @page {
                margin: \(marginTop)px \(marginRight)px \(marginBottom)px \(marginLeft)px !important;
            }*/
            
            """
        }
        
        
        for fontName in UIFont.fontNames(forFamilyName: currentFont) {
            continue
//            if let fontURL = readerCenter?.userFonts[fontName] {
            guard let fontDescriptor = readerConfig?.userFontDescriptors[fontName] else {
                continue
            }
//                let ctFont = CTFontCreateWithName(fontName as CFString, CGFloat(currentFontSizeOnly), nil)
//                let ctFontSymbolicTrait = CTFontGetSymbolicTraits(ctFont)
//                let ctFontTraits = CTFontCopyTraits(ctFont)
//                let ctFontURL = unsafeBitCast(CTFontDescriptorCopyAttribute(fontDescriptor, kCTFontURLAttribute), to: CFURL.self)
            guard let ctFontURL = CTFontDescriptorCopyAttribute(fontDescriptor, kCTFontURLAttribute),
                  CFGetTypeID(ctFontURL) == CFURLGetTypeID(),
                  let fontURL = ctFontURL as? URL else {
                continue
            }
            var isItalic = false
            var isBold = false
            
            var cssFontWeight = "normal"
            
            if let ctFontTraits = CTFontDescriptorCopyAttribute(fontDescriptor, kCTFontTraitsAttribute), CFGetTypeID(ctFontTraits) == CFDictionaryGetTypeID() {
                if let ctFontSymbolicTrait = CFDictionaryGetValue(
                    (ctFontTraits as! CFDictionary),
                    unsafeBitCast(kCTFontSymbolicTrait, to: UnsafeRawPointer.self))  {
                    
                    var symTraitVal = UInt32()
                    CFNumberGetValue(unsafeBitCast(ctFontSymbolicTrait, to: CFNumber.self), CFNumberType.intType, &symTraitVal)
                    
                    isItalic = symTraitVal & CTFontSymbolicTraits.traitItalic.rawValue > 0
                    isBold = symTraitVal & CTFontSymbolicTraits.traitBold.rawValue > 0
                    
                    cssFontWeight = isBold ? "bold" : "normal"
                }
//                let isItalic = ctFontSymbolicTrait.contains(.traitItalic)
//                let isBold = ctFontSymbolicTrait.contains(.traitBold)
                
                
                if let weightRef = CFDictionaryGetValue(
                    (ctFontTraits as! CFDictionary),
                    unsafeBitCast(kCTFontWeightTrait, to: UnsafeRawPointer.self)) {
                    
                    var weightValue = Float()
                    CFNumberGetValue(unsafeBitCast(weightRef, to: CFNumber.self), CFNumberType.floatType, &weightValue)
                    if weightValue < -0.49 {
                        cssFontWeight = "100"   //thin
                    } else if weightValue < -0.29 {
                        cssFontWeight = "200"   //extralight
                    } else if weightValue < -0.19 {
                        cssFontWeight = "300"   //light
                    } else if weightValue < 0.01 {
                        cssFontWeight = "400"   //normal
                    } else if weightValue < 0.21 {
                        cssFontWeight = "500"   //medium
                    } else if weightValue < 0.31 {
                        cssFontWeight = "600"   //semibold
                    } else if weightValue < 0.41 {
                        cssFontWeight = "700"   //bold
                    } else if weightValue < 0.61 {
                        cssFontWeight = "800"   //extrabold
                    } else {
                        cssFontWeight = "900"   //heavy
                    }
                }
            }
            
            //prepare font hardlink
            guard let resourceBasePath = self.readerContainer?.book.smils.basePath else {
                continue
            }
            if self.readerContainer?.readerConfig.debug.contains(.htmlStyling) ?? false {
                print("generateRuntimeStyle \(resourceBasePath)")
            }
            
            let folioResPath = resourceBasePath.appendingPathComponent("_folio_res")

            let toFontPath = folioResPath.appendingPathComponent(fontURL.lastPathComponent)

            do {
                if !FileManager.default.fileExists(atPath: folioResPath) {
                    try FileManager.default.createDirectory(atPath: folioResPath, withIntermediateDirectories: false, attributes: nil)
                }
                
                if self.readerContainer?.readerConfig.debug.contains(.htmlStyling) ?? false  {
                    print("generateRuntimeStyle linkItem \(fontURL.path) \(toFontPath)")
                }

                if FileManager.default.fileExists(atPath: toFontPath) {
                    try FileManager.default.removeItem(atPath: toFontPath)
                }
                try FileManager.default.linkItem(atPath: fontURL.path, toPath: toFontPath)
            } catch {
                continue
            }
            
            style += """
            
            @font-face {
                font-family: \(currentFont);
                font-style: \(isItalic ? "italic" : "normal");
                font-weight: \(cssFontWeight);
                src: url('\(toFontPath)');
            }
            
            """
        }
        
        return style
    }
    
    static let CssLevelTags : [StyleOverrideTypes: String] = [.PNode: "p", .PlusTD: "td", .PlusSPAN: "span", .AllText: " "]
    static func CssLevels(type: String, def: String) -> [String] {
        CssLevelTags.map {
            ".folioStyleL\($0.rawValue)\(type) \($1) { \(def) }"
        }.sorted()
    }
    
    static func CssImgLevels(type: String, def: String) -> [String] {
        CssLevelTags.map {
            ".folioStyleL\($0.rawValue)\(type) \($1) img.folioImg { \(def) }"
        }.sorted()
    }
    
    func cssFontFamilies() -> String {
        UIFont.familyNames.map {
            FolioReader.CssLevels(type: "FontFamily\($0.replacingOccurrences(of: " ", with: "_"))", def: "font-family: \"\($0)\" !important;")
        }.flatMap { $0 }.joined(separator: "\n")
    }
    
    func cssUserFontFaces() -> String {
        guard let readerConfig = readerConfig else { return "" }
        
        return readerConfig.userFontDescriptors.compactMap { fontName, fontDescriptor -> String? in
//                let ctFont = CTFontCreateWithName(fontName as CFString, CGFloat(currentFontSizeOnly), nil)
//                let ctFontSymbolicTrait = CTFontGetSymbolicTraits(ctFont)
//                let ctFontTraits = CTFontCopyTraits(ctFont)
//                let ctFontURL = unsafeBitCast(CTFontDescriptorCopyAttribute(fontDescriptor, kCTFontURLAttribute), to: CFURL.self)
            guard let ctFontURL = CTFontDescriptorCopyAttribute(fontDescriptor, kCTFontURLAttribute),
                  CFGetTypeID(ctFontURL) == CFURLGetTypeID(),
                  let fontURL = ctFontURL as? URL else {
                      return nil
                  }
            
            guard let ctFontFamilyName = CTFontDescriptorCopyAttribute(fontDescriptor, kCTFontFamilyNameAttribute),
                  CFGetTypeID(ctFontFamilyName) == CFStringGetTypeID(),
                  let fontFamilyName = ctFontFamilyName as? String else {
                      return nil
                  }
            
            var isItalic = false
            var isBold = false
            
            var cssFontWeight = "normal"
            
            if let ctFontTraits = CTFontDescriptorCopyAttribute(fontDescriptor, kCTFontTraitsAttribute), CFGetTypeID(ctFontTraits) == CFDictionaryGetTypeID() {
                if let ctFontSymbolicTrait = CFDictionaryGetValue(
                    (ctFontTraits as! CFDictionary),
                    unsafeBitCast(kCTFontSymbolicTrait, to: UnsafeRawPointer.self))  {
                    
                    var symTraitVal = UInt32()
                    CFNumberGetValue(unsafeBitCast(ctFontSymbolicTrait, to: CFNumber.self), CFNumberType.intType, &symTraitVal)
                    
                    isItalic = symTraitVal & CTFontSymbolicTraits.traitItalic.rawValue > 0
                    isBold = symTraitVal & CTFontSymbolicTraits.traitBold.rawValue > 0
                    
                    cssFontWeight = isBold ? "bold" : "normal"
                }
//                let isItalic = ctFontSymbolicTrait.contains(.traitItalic)
//                let isBold = ctFontSymbolicTrait.contains(.traitBold)
                
                
                if let weightRef = CFDictionaryGetValue(
                    (ctFontTraits as! CFDictionary),
                    unsafeBitCast(kCTFontWeightTrait, to: UnsafeRawPointer.self)) {
                    
                    var weightValue = Float()
                    CFNumberGetValue(unsafeBitCast(weightRef, to: CFNumber.self), CFNumberType.floatType, &weightValue)
                    if weightValue < -0.49 {
                        cssFontWeight = "100"   //thin
                    } else if weightValue < -0.29 {
                        cssFontWeight = "200"   //extralight
                    } else if weightValue < -0.19 {
                        cssFontWeight = "300"   //light
                    } else if weightValue < 0.01 {
                        cssFontWeight = "400"   //normal
                    } else if weightValue < 0.21 {
                        cssFontWeight = "500"   //medium
                    } else if weightValue < 0.31 {
                        cssFontWeight = "600"   //semibold
                    } else if weightValue < 0.41 {
                        cssFontWeight = "700"   //bold
                    } else if weightValue < 0.61 {
                        cssFontWeight = "800"   //extrabold
                    } else {
                        cssFontWeight = "900"   //heavy
                    }
                }
            }
            
            if false {
                //prepare font hardlink
                guard let resourceBasePath = self.readerContainer?.book.smils.basePath else {
                    return nil
                }
                if self.readerContainer?.readerConfig.debug.contains(.htmlStyling) ?? false {
                    print("generateRuntimeStyle \(resourceBasePath)")
                }
                
                let folioResPath = resourceBasePath.appendingPathComponent("_folio_res")
                
                let toFontPath = folioResPath.appendingPathComponent(fontURL.lastPathComponent)
                
                do {
                    if !FileManager.default.fileExists(atPath: folioResPath) {
                        try FileManager.default.createDirectory(atPath: folioResPath, withIntermediateDirectories: false, attributes: nil)
                    }
                    
                    if self.readerContainer?.readerConfig.debug.contains(.htmlStyling) ?? false  {
                        print("generateRuntimeStyle linkItem \(fontURL.path) \(toFontPath)")
                    }
                    
                    if FileManager.default.fileExists(atPath: toFontPath) {
                        try FileManager.default.removeItem(atPath: toFontPath)
                    }
                    try FileManager.default.linkItem(atPath: fontURL.path, toPath: toFontPath)
                } catch {
                    return ""
                }
            }
            
            return "@font-face { font-family: \"\(fontFamilyName)\"; font-style: \(isItalic ? "italic" : "normal"); font-weight: \(cssFontWeight); src: url(\"/_fonts/\(fontURL.lastPathComponent)\");} "
            
        }.joined(separator: " ")
    }
}
