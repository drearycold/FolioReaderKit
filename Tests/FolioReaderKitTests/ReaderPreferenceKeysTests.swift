//
//  ReaderPreferenceKeysTests.swift
//  FolioReaderKitTests
//
//  Created by DeepMind Antigravity on 7/7/26.
//  Copyright © 2026 FolioReader. All rights reserved.
//

import XCTest
@testable import FolioReaderKit

class ReaderPreferenceKeysTests: XCTestCase {
    
    func testRawKeyMappings() {
        let expectedMappings: [ReaderPreferenceKey: String] = [
            .nightMode: "nightMode",
            .themeMode: "themeMode",
            .currentFont: "currentFont",
            .currentFontSize: "currentFontSize",
            .currentFontWeight: "currentFontWeight",
            .currentAudioRate: "currentAudioRate",
            .currentHighlightStyle: "currentHighlightStyle",
            .currentMediaOverlayStyle: "currentMediaOverlayStyle",
            .currentScrollDirection: "currentScrollDirection",
            .currentLandscapeSpread: "currentLandscapeSpread",
            .currentNavigationMenuIndex: "currentNavigationMenuIndex",
            .currentAnnotationMenuIndex: "currentAnnotationMenuIndex",
            .currentNavigationMenuBookListStyle: "currentNavigationMenuBookListStyle",
            .currentVMarginLinked: "currentVMarginLinked",
            .currentMarginTop: "currentMarginTop",
            .currentMarginBottom: "currentMarginBottom",
            .currentHMarginLinked: "currentHMarginLinked",
            .currentMarginLeft: "currentMarginLeft",
            .currentMarginRight: "currentMarginRight",
            .currentLetterSpacing: "currentLetterSpacing",
            .currentLineHeight: "currentLineHeight",
            .currentTextIndent: "currentTextIndent",
            .doWrapPara: "doWrapPara",
            .doClearClass: "doClearClass",
            .styleOverride: "styleOverride",
            .structuralStyle: "structuralStyle",
            .structuralTrackingTocLevel: "structuralTrackingTocLevel"
        ]
        
        for (key, expectedString) in expectedMappings {
            XCTAssertEqual(key.rawKey, expectedString)
        }
    }
    
    func testNoDuplicateKeys() {
        let allKeys: [ReaderPreferenceKey] = [
            .nightMode, .themeMode, .currentFont, .currentFontSize, .currentFontWeight,
            .currentAudioRate, .currentHighlightStyle, .currentMediaOverlayStyle, .currentScrollDirection,
            .currentLandscapeSpread,
            .currentNavigationMenuIndex, .currentAnnotationMenuIndex, .currentNavigationMenuBookListStyle,
            .currentVMarginLinked, .currentMarginTop, .currentMarginBottom, .currentHMarginLinked,
            .currentMarginLeft, .currentMarginRight, .currentLetterSpacing, .currentLineHeight,
            .currentTextIndent, .doWrapPara, .doClearClass, .styleOverride, .structuralStyle,
            .structuralTrackingTocLevel
        ]
        
        let rawKeys = allKeys.map { $0.rawKey }
        let uniqueKeys = Set(rawKeys)
        
        XCTAssertEqual(rawKeys.count, uniqueKeys.count, "There should be no duplicate preference keys")
    }
}
