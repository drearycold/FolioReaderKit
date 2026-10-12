//
//  ReaderPreferenceKeys.swift
//  FolioReaderKit
//
//  Created by DeepMind Antigravity on 7/3/26.
//  Copyright © 2026 FolioReader. All rights reserved.
//

import Foundation

/// Type-safe definitions for all preference keys.
public enum ReaderPreferenceKey {
    // MARK: - Themes
    case nightMode
    case themeMode
    
    // MARK: - Fonts
    case currentFont
    case currentFontSize
    case currentFontWeight
    
    // MARK: - Reading Styles
    case currentAudioRate
    case currentHighlightStyle
    case currentMediaOverlayStyle
    case currentScrollDirection
    case currentLandscapeSpread
    
    // MARK: - Navigation
    case currentNavigationMenuIndex
    case currentAnnotationMenuIndex
    case currentNavigationMenuBookListStyle
    
    // MARK: - Margins
    case currentVMarginLinked
    case currentMarginTop
    case currentMarginBottom
    case currentHMarginLinked
    case currentMarginLeft
    case currentMarginRight
    
    // MARK: - Typography & Layout
    case currentLetterSpacing
    case currentLineHeight
    case currentTextIndent
    case doWrapPara
    case doClearClass
    case styleOverride
    
    // MARK: - Structure
    case structuralStyle
    case structuralTrackingTocLevel

    /// Original string representation of the preference key for backward compatibility.
    public var rawKey: String {
        switch self {
        case .nightMode: return "nightMode"
        case .themeMode: return "themeMode"
        case .currentFont: return "currentFont"
        case .currentFontSize: return "currentFontSize"
        case .currentFontWeight: return "currentFontWeight"
        case .currentAudioRate: return "currentAudioRate"
        case .currentHighlightStyle: return "currentHighlightStyle"
        case .currentMediaOverlayStyle: return "currentMediaOverlayStyle"
        case .currentScrollDirection: return "currentScrollDirection"
        case .currentLandscapeSpread: return "currentLandscapeSpread"
        case .currentNavigationMenuIndex: return "currentNavigationMenuIndex"
        case .currentAnnotationMenuIndex: return "currentAnnotationMenuIndex"
        case .currentNavigationMenuBookListStyle: return "currentNavigationMenuBookListStyle"
        case .currentVMarginLinked: return "currentVMarginLinked"
        case .currentMarginTop: return "currentMarginTop"
        case .currentMarginBottom: return "currentMarginBottom"
        case .currentHMarginLinked: return "currentHMarginLinked"
        case .currentMarginLeft: return "currentMarginLeft"
        case .currentMarginRight: return "currentMarginRight"
        case .currentLetterSpacing: return "currentLetterSpacing"
        case .currentLineHeight: return "currentLineHeight"
        case .currentTextIndent: return "currentTextIndent"
        case .doWrapPara: return "doWrapPara"
        case .doClearClass: return "doClearClass"
        case .styleOverride: return "styleOverride"
        case .structuralStyle: return "structuralStyle"
        case .structuralTrackingTocLevel: return "structuralTrackingTocLevel"
        }
    }
}
