//
//  ReaderPreferences.swift
//  FolioReaderKit
//
//  Created by DeepMind Antigravity on 7/4/26.
//  Copyright © 2026 FolioReader. All rights reserved.
//

import UIKit

/// 封装所有阅读器偏好的读写，从 FolioReader God Object 中提取
public class ReaderPreferences {
    private weak var folioReader: FolioReader?
    
    init(folioReader: FolioReader) {
        self.folioReader = folioReader
    }
    
    var preferenceProvider: FolioReaderPreferenceProvider? {
        return folioReader?.delegate?.folioReaderPreferenceProvider?(folioReader!)
    }
    
    func pref(boolFor key: ReaderPreferenceKey, default defaultValue: Bool) -> Bool {
        guard let folioReader = folioReader else { return defaultValue }
        return preferenceProvider?.preference(boolFor: key.rawKey, default: defaultValue) ?? defaultValue
    }
    
    func pref(intFor key: ReaderPreferenceKey, default defaultValue: Int) -> Int {
        guard let folioReader = folioReader else { return defaultValue }
        return preferenceProvider?.preference(intFor: key.rawKey, default: defaultValue) ?? defaultValue
    }
    
    func pref(stringFor key: ReaderPreferenceKey, default defaultValue: String) -> String {
        guard let folioReader = folioReader else { return defaultValue }
        return preferenceProvider?.preference(stringFor: key.rawKey, default: defaultValue) ?? defaultValue
    }
    
    func pref(setBool value: Bool, for key: ReaderPreferenceKey) {
        preferenceProvider?.preference(setBool: value, for: key.rawKey)
    }
    
    func pref(setInt value: Int, for key: ReaderPreferenceKey) {
        preferenceProvider?.preference(setInt: value, for: key.rawKey)
    }
    
    func pref(setString value: String, for key: ReaderPreferenceKey) {
        preferenceProvider?.preference(setString: value, for: key.rawKey)
    }

    func postPageModeRefresh() {
        NotificationCenter.default.post(name: .folioReaderNeedRefreshPageMode, object: folioReader)
    }

    // MARK: - Properties

    /// Check if current theme is Night mode
    public var nightMode: Bool {
        get {
            pref(boolFor: .nightMode, default: false)
        }
        set (value) {
            pref(setBool: value, for: .nightMode)

            if let readerCenter = folioReader?.readerCenter {
                UIView.animate(withDuration: 0.6, animations: {
                    readerCenter.pageIndicatorView?.reloadColors()
                    readerCenter.configureNavBar()
                    readerCenter.scrollScrubber?.reloadColors()
                    readerCenter.collectionView.backgroundColor = (value == true ? self.folioReader?.readerContainer?.readerConfig.nightModeBackground : UIColor.white)
                }, completion: { (finished: Bool) in
                    self.postPageModeRefresh()
                })
            }
        }
    }
    
    public var themeMode: Int {
        get {
            pref(intFor: .themeMode, default: 1)
        }
        set (value) {
            pref(setInt: value, for: .themeMode)
            
            guard let readerCenter = folioReader?.readerCenter,
                  let backgroundColor = folioReader?.readerConfig?.themeModeBackground[value] else { return }
            
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
                _ = readerCenter.currentPage?.webView?.js("themeMode(\(value))")
                readerCenter.pageIndicatorView?.reloadColors()
                readerCenter.configureNavBar()
                readerCenter.scrollScrubber?.reloadColors()
                readerCenter.navigationItem.titleView?.subviews.forEach {
                    if let label = $0 as? UILabel {
                        label.textColor = self.folioReader?.readerConfig?.themeModeTextColor[value]
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
                self.postPageModeRefresh()
            })
        }
    }

    public var currentFont: String {
        get {
            pref(stringFor: .currentFont, default: "Georgia")
        }
        set (fontFamilyName) {
            pref(setString: fontFamilyName, for: .currentFont)
            folioReader?.readerCenter?.currentPage?.updateRuntimeStyle(delay: 0.4)
        }
    }
    
    /// Check current font size. Default .m
    public var currentFontSize: String {
        get {
            pref(stringFor: .currentFontSize, default: FolioReader.DefaultFontSize)
        }
        set (fontSize) {
            pref(setString: fontSize, for: .currentFontSize)
            folioReader?.readerCenter?.currentPage?.updateRuntimeStyle(delay: 0.4)
        }
    }
    
    public var currentFontSizeOnly: Int {
        return Int(Double(currentFontSize.replacingOccurrences(of: "px", with: "")) ?? 20)
    }

    public var currentFontWeight: String {
        get {
            pref(stringFor: .currentFontWeight, default: "500")
        }
        set (fontWeight) {
            pref(setString: fontWeight, for: .currentFontWeight)
            folioReader?.readerCenter?.currentPage?.updateRuntimeStyle(delay: 0.4)
        }
    }
    
    /// Check current audio rate, the speed of speech voice. Default 0
    public var currentAudioRate: Int {
        get {
            pref(intFor: .currentAudioRate, default: 1)
        }
        set (value) {
            pref(setInt: value, for: .currentAudioRate)
        }
    }

    /// Check the current highlight style.Default 0
    public var currentHighlightStyle: Int {
        get {
            pref(intFor: .currentHighlightStyle, default: FolioReaderHighlightStyle.yellow.rawValue)
        }
        set (value) {
            pref(setInt: value, for: .currentHighlightStyle)
        }
    }

    /// Check the current Media Overlay or TTS style
    public var currentMediaOverlayStyle: MediaOverlayStyle {
        get {
            let rawValue = pref(intFor: .currentMediaOverlayStyle, default: MediaOverlayStyle.default.rawValue)
            return MediaOverlayStyle(rawValue: rawValue) ?? .default
        }
        set (value) {
            pref(setInt: value.rawValue, for: .currentMediaOverlayStyle)
        }
    }

    public var defaultScrollDirection: FolioReaderScrollDirection {
        folioReader?.readerContainer?.book.spine.isRtl == true ? .horizontalWithPagedContent : .horizontalWithScrollContent
    }
    /// Check the current scroll direction. When nothing has been saved, defaults to the reader
    /// config's `scrollDirection` (so a host app's configured direction is honoured), or to
    /// `defaultScrollDirection` when no container is attached.
    public var currentScrollDirection: Int {
        get {
            let fallback = folioReader?.readerConfig?.scrollDirection ?? defaultScrollDirection
            return pref(intFor: .currentScrollDirection, default: fallback.rawValue)
        }
        set (value) {
            pref(setInt: value, for: .currentScrollDirection)

            let direction = FolioReaderScrollDirection(rawValue: value) ?? defaultScrollDirection
            folioReader?.readerCenter?.currentPage?.setScrollDirection(direction)
        }
    }

    public var currentNavigationMenuIndex: Int {
        get {
            pref(intFor: .currentNavigationMenuIndex, default: 0)
        }
        set (value) {
            pref(setInt: value, for: .currentNavigationMenuIndex)
        }
    }
    
    public var currentAnnotationMenuIndex: Int {
        get {
            pref(intFor: .currentAnnotationMenuIndex, default: 0)
        }
        set (value) {
            pref(setInt: value, for: .currentAnnotationMenuIndex)
        }
    }
    
    /**
     0: Grid
     1: List
     */
    public var currentNavigationMenuBookListStyle: NavigationMenuBookListStyle {
        get {
            guard self.structuralStyle == .bundle else {
                return .List
            }
            let defaults: NavigationMenuBookListStyle = self.structuralTrackingTocLevel == .level1 ? .Grid : .List
            let rawValue = pref(intFor: .currentNavigationMenuBookListStyle, default: defaults.rawValue)
            return NavigationMenuBookListStyle(rawValue: rawValue) ?? defaults
        }
        set (value) {
            pref(setInt: value.rawValue, for: .currentNavigationMenuBookListStyle)
        }
    }
    
    public var currentVMarginLinked: Bool {
        get {
            pref(boolFor: .currentVMarginLinked, default: true)
        }
        set (value) {
            pref(setBool: value, for: .currentVMarginLinked)
        }
    }
    
    public var defaultMarginTop: Int {
        (folioReader?.readerCenter?.traitCollection ?? UIScreen.main.traitCollection).verticalSizeClass == .regular ? 10 : 5    //5% for regular size, otherwise 2.5%
    }
    public var currentMarginTop: Int {
        get {
            let defaults = self.defaultMarginTop
            return pref(intFor: .currentMarginTop, default: defaults)
        }
        set (value) {
            let newValue = max(0, min(50, value))
            pref(setInt: newValue, for: .currentMarginTop)
            guard currentVMarginLinked == false else { return }
            folioReader?.readerCenter?.currentPage?.byWritingMode(
                horizontal: { self.folioReader?.readerCenter?.currentPage?.updateViewerLayout(delay: 0.2) },
                vertical: { self.folioReader?.readerCenter?.currentPage?.updateRuntimeStyle(delay: 0.4) }
            )
        }
    }

    public var defaultMarginBottom: Int {
        (folioReader?.readerCenter?.traitCollection ?? UIScreen.main.traitCollection).verticalSizeClass == .regular ? 10 : 5    //5% for regular size, otherwise 2.5%
    }
    public var currentMarginBottom: Int {
        get {
            let defaults = defaultMarginBottom
            return pref(intFor: .currentMarginBottom, default: defaults)
        }
        set (value) {
            let newValue = max(0, min(50, value))
            pref(setInt: newValue, for: .currentMarginBottom)
            guard currentVMarginLinked == false else { return }
            folioReader?.readerCenter?.currentPage?.byWritingMode(
                horizontal: { self.folioReader?.readerCenter?.currentPage?.updateViewerLayout(delay: 0.2) },
                vertical: { self.folioReader?.readerCenter?.currentPage?.updateRuntimeStyle(delay: 0.4) }
            )
        }
    }

    public var currentHMarginLinked: Bool {
        get {
            pref(boolFor: .currentHMarginLinked, default: true)
        }
        set (value) {
            pref(setBool: value, for: .currentHMarginLinked)
        }
    }
    
    public var defaultMarginLeft: Int {
        (folioReader?.readerCenter?.traitCollection ?? UIScreen.main.traitCollection).horizontalSizeClass == .regular ? 30 : 5    //15% for regular size, otherwise 2.5%
    }
    public var currentMarginLeft: Int {
        get {
            let defaults = self.defaultMarginLeft
            return pref(intFor: .currentMarginLeft, default: defaults)
        }
        set (value) {
            let newValue = max(0, min(50, value))
            pref(setInt: newValue, for: .currentMarginLeft)
            guard currentHMarginLinked == false else { return }
            folioReader?.readerCenter?.currentPage?.byWritingMode(
                horizontal: { self.folioReader?.readerCenter?.currentPage?.updateRuntimeStyle(delay: 0.4) },
                vertical: { self.folioReader?.readerCenter?.currentPage?.updateViewerLayout(delay: 0.2) }
            )
        }
    }

    public var defaultMarginRight: Int {
        (folioReader?.readerCenter?.traitCollection ?? UIScreen.main.traitCollection).horizontalSizeClass == .regular ? 30 : 5     //15% for regular size, otherwise 2.5%
    }
    public var currentMarginRight: Int {
        get {
            let defaults = self.defaultMarginRight
            return pref(intFor: .currentMarginRight, default: defaults)
        }
        set (value) {
            let newValue = max(0, min(50, value))
            pref(setInt: newValue, for: .currentMarginRight)
            guard currentHMarginLinked == false else { return }
            folioReader?.readerCenter?.currentPage?.byWritingMode(
                horizontal: { self.folioReader?.readerCenter?.currentPage?.updateRuntimeStyle(delay: 0.4) },
                vertical: { self.folioReader?.readerCenter?.currentPage?.updateViewerLayout(delay: 0.2) }
            )
        }
    }
    
    public var currentLetterSpacing: Int {
        get {
            pref(intFor: .currentLetterSpacing, default: 2)
        }
        set (value) {
            pref(setInt: value, for: .currentLetterSpacing)
            folioReader?.readerCenter?.currentPage?.updateRuntimeStyle(delay: 0.4)
        }
    }
    
    public var currentLineHeight: Int {
        get {
            pref(intFor: .currentLineHeight, default: 3)
        }
        set (value) {
            pref(setInt: value, for: .currentLineHeight)
            folioReader?.readerCenter?.currentPage?.updateRuntimeStyle(delay: 0.4)
        }
    }

    //in em
    public var currentTextIndent: Int {
        get {
            pref(intFor: .currentTextIndent, default: 2)
        }
        set (value) {
            pref(setInt: value, for: .currentTextIndent)
            folioReader?.readerCenter?.currentPage?.updateRuntimeStyle(delay: 0.4)
        }
    }
    
    public var doWrapPara: Bool {
        get {
            pref(boolFor: .doWrapPara, default: false)
        }
        set (value) {
            pref(setBool: value, for: .doWrapPara)
        }
    }
    
    public var doClearClass: Bool {
        get {
            pref(boolFor: .doClearClass, default: true)
        }
        set (value) {
            pref(setBool: value, for: .doClearClass)
        }
    }
    
    public var styleOverride: StyleOverrideTypes {
        get {
            let rawValue = pref(intFor: .styleOverride, default: StyleOverrideTypes.PNode.rawValue)
            return StyleOverrideTypes(rawValue: rawValue) ?? .PNode
        }
        set (value) {
            pref(setInt: value.rawValue, for: .styleOverride)
            folioReader?.readerCenter?.currentPage?.updateRuntimeStyle(delay: 0.2)
        }
    }
    
    @available(*, deprecated, message: "use delegate")
    @objc dynamic public var savedPositionForCurrentBook: FolioReaderReadPosition? {
        get {
            guard let bookId = folioReader?.readerCenter?.book.name?.deletingPathExtension else { return nil }
            FolioLogger.log("savedPositionForCurrentBook get")
            guard let folioReader = folioReader else { return nil }
            return folioReader.delegate?.folioReaderReadPositionProvider?(folioReader).folioReaderReadPosition(folioReader, bookId: bookId)
        }
        set {
            guard let position = newValue,
                  let bookId = folioReader?.readerCenter?.book.name?.deletingPathExtension else { return }
            
            guard let folioReader = folioReader else { return }
            guard folioReader.isReaderReady || position.takePrecedence else { return }
            
            if let debug = folioReader.readerConfig?.debug, debug.contains(.functionTrace) {
                Thread.callStackSymbols.forEach {
                    FolioLogger.log($0)
                }
                if position.bookProgress < 5.0 {
                    FolioLogger.log(position.bookProgress.description)
                }
            }
            
            folioReader.save(readPosition: position, for: bookId)
        }
    }
    
    public var structuralStyle: FolioReaderStructuralStyle {
        get {
            let rawValue = pref(intFor: .structuralStyle, default: FolioReaderStructuralStyle.atom.rawValue)
            return FolioReaderStructuralStyle(rawValue: rawValue) ?? .atom
        }
        set {
            pref(setInt: newValue.rawValue, for: .structuralStyle)
        }
    }
    
    public var structuralTrackingTocLevel: FolioReaderPositionTrackingStyle {
        get {
            let rawValue = pref(intFor: .structuralTrackingTocLevel, default: FolioReaderPositionTrackingStyle.linear.rawValue)
            return FolioReaderPositionTrackingStyle(rawValue: rawValue) ?? .linear
        }
        set {
            pref(setInt: newValue.rawValue, for: .structuralTrackingTocLevel)
        }
    }
}

extension ReaderPreferences {
    /// Return the appropriate navigation bar background color based on the current theme configuration.
    public func navBackgroundColor(withConfiguration readerConfig: FolioReaderConfig) -> UIColor {
        guard let folioReader = self.folioReader else { return .white }
        return readerConfig.themeModeNavBackground[folioReader.themeMode]
    }

    /// Return the appropriate navigation bar text color based on night mode state.
    public func navTextColor() -> UIColor {
        guard let folioReader = self.folioReader else { return .black }
        return folioReader.readerConfig?.themeModeTextColor[folioReader.themeMode] ?? .black
    }
}
