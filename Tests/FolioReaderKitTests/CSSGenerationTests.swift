//
//  CSSGenerationTests.swift
//  FolioReaderKitTests
//
//  Created by DeepMind Antigravity on 7/3/26.
//  Copyright © 2026 FolioReader. All rights reserved.
//

import XCTest
@testable import FolioReaderKit

@MainActor
class CSSGenerationTests: XCTestCase {
    
    func testGenerateRuntimeStyle() {
        let folioReader = FolioReader()
        let delegate = MockFolioReaderDelegate()
        folioReader.delegate = delegate
        
        // Setup initial preference settings
        folioReader.styleOverride = .PNode
        delegate.preferenceProvider.preference(setString: "20px", for: "currentFontSize")
        delegate.preferenceProvider.preference(setInt: 2, for: "currentLetterSpacing")
        delegate.preferenceProvider.preference(setInt: 3, for: "currentLineHeight")
        delegate.preferenceProvider.preference(setInt: 1, for: "currentTextIndent")
        
        var css = folioReader.generateRuntimeStyle()
        XCTAssertTrue(css.contains("p {"))
        XCTAssertFalse(css.contains("p, td {"))
        XCTAssertFalse(css.contains("p, td, span {"))
        
        // Test styleOverride changes
        folioReader.styleOverride = .PlusTD
        css = folioReader.generateRuntimeStyle()
        XCTAssertTrue(css.contains("p, td {"))
        
        folioReader.styleOverride = .PlusSPAN
        css = folioReader.generateRuntimeStyle()
        XCTAssertTrue(css.contains("p, td, td, span {"))
        
        folioReader.styleOverride = .None
        css = folioReader.generateRuntimeStyle()
        XCTAssertFalse(css.contains("p {"))
        XCTAssertFalse(css.contains("p, td, td, span {"))
    }
    
    func testCssLevelsHelpers() {
        let levels = ReaderCSSGenerator.CssLevels(type: "FontFamilyTest", def: "color: red;")
        XCTAssertEqual(levels.count, 4)
        // .PNode is rawValue 1
        XCTAssertTrue(levels.contains("html body.folioStyleL1FontFamilyTest p, body.folioStyleL1FontFamilyTest p { color: red; }"))
        // .PlusTD is rawValue 2
        XCTAssertTrue(levels.contains("html body.folioStyleL2FontFamilyTest td, body.folioStyleL2FontFamilyTest td { color: red; }"))
        
        let imgLevels = ReaderCSSGenerator.CssImgLevels(type: "ImgTest", def: "max-width: 100%;")
        XCTAssertEqual(imgLevels.count, 4)
        XCTAssertTrue(imgLevels.contains("html body.folioStyleL1ImgTest p img.folioImg, body.folioStyleL1ImgTest p img.folioImg { max-width: 100%; }"))
    }
    
    func testCssFontFamilies() {
        let folioReader = FolioReader()
        let cssGenerator = ReaderCSSGenerator(folioReader: folioReader)
        let fontFamiliesCss = cssGenerator.cssFontFamilies()
        
        XCTAssertFalse(fontFamiliesCss.isEmpty)
        // Verify it contains styling for typical iOS fonts like Helvetica
        XCTAssertTrue(fontFamiliesCss.contains("Helvetica"))
    }
    
    func testCssUserFontFacesEmpty() {
        let folioReader = FolioReader()
        let cssGenerator = ReaderCSSGenerator(folioReader: folioReader)
        let userFontFaces = cssGenerator.cssUserFontFaces()
        // Without user font descriptors set, this should be empty
        XCTAssertTrue(userFontFaces.isEmpty)
    }

    func testBundledPageStyleDoesNotForceTopOrBottomPageMargins() {
        let source = FolioReaderScript.cssInjection.source

        XCTAssertTrue(source.contains("@page"))
        XCTAssertTrue(source.contains("margin: 0 0 !important;"))
        XCTAssertFalse(source.contains("margin-top: 1em !important;"))
        XCTAssertFalse(source.contains("margin-bottom: 1em !important;"))
    }

    func testZeroBodyPaddingClassesEmitZeroPadding() {
        let source = FolioReaderScript.cssInjection.source

        XCTAssertTrue(source.contains(".folioStyleBodyPaddingLeft0 { padding-left: 0.0vw !important;"))
        XCTAssertTrue(source.contains(".folioStyleBodyPaddingRight0 { padding-right: 0.0vw !important;"))
        XCTAssertTrue(source.contains(".folioStyleBodyPaddingTop0 { padding-top: 0.0vh !important;"))
        XCTAssertTrue(source.contains(".folioStyleBodyPaddingBottom0 { padding-bottom: 0.0vh !important;"))
    }
}
