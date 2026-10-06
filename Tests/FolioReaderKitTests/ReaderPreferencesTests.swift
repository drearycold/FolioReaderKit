//
//  ReaderPreferencesTests.swift
//  FolioReaderKitTests
//
//  Created by DeepMind Antigravity on 7/7/26.
//  Copyright © 2026 FolioReader. All rights reserved.
//

import XCTest
import ReadiumGCDWebServer
@testable import FolioReaderKit

@MainActor
class ReaderPreferencesTests: XCTestCase {
    
    var folioReader: FolioReader!
    var delegate: MockFolioReaderDelegate!
    var preferences: ReaderPreferences!
    
    override func setUp() {
        super.setUp()
        folioReader = FolioReader()
        delegate = MockFolioReaderDelegate()
        folioReader.delegate = delegate
        preferences = folioReader.preferences
    }
    
    override func tearDown() {
        preferences = nil
        delegate = nil
        folioReader = nil
        super.tearDown()
    }
    
    func testNightModeDefaultAndRoundtrip() {
        XCTAssertFalse(preferences.nightMode)
        preferences.nightMode = true
        XCTAssertTrue(preferences.nightMode)
        XCTAssertTrue(delegate.preferenceProvider.preference(boolFor: ReaderPreferenceKey.nightMode.rawKey, default: false))
    }
    
    func testThemeModeDefaultAndRoundtrip() {
        XCTAssertEqual(preferences.themeMode, 1)
        preferences.themeMode = 3
        XCTAssertEqual(preferences.themeMode, 3)
        XCTAssertEqual(delegate.preferenceProvider.preference(intFor: ReaderPreferenceKey.themeMode.rawKey, default: 1), 3)
    }
    
    func testCurrentFontDefaultAndRoundtrip() {
        XCTAssertEqual(preferences.currentFont, "Georgia")
        preferences.currentFont = "Arial"
        XCTAssertEqual(preferences.currentFont, "Arial")
    }
    
    func testCurrentFontSizeDefaultAndRoundtrip() {
        XCTAssertEqual(preferences.currentFontSize, "20px")
        preferences.currentFontSize = "25px"
        XCTAssertEqual(preferences.currentFontSize, "25px")
    }
    
    func testCurrentFontSizeOnly() {
        preferences.currentFontSize = "20px"
        XCTAssertEqual(preferences.currentFontSizeOnly, 20)
        preferences.currentFontSize = "30px"
        XCTAssertEqual(preferences.currentFontSizeOnly, 30)
    }
    
    func testCurrentFontWeightDefaultAndRoundtrip() {
        XCTAssertEqual(preferences.currentFontWeight, "500")
        preferences.currentFontWeight = "bold"
        XCTAssertEqual(preferences.currentFontWeight, "bold")
    }
    
    func testCurrentAudioRateDefaultAndRoundtrip() {
        XCTAssertEqual(preferences.currentAudioRate, 1)
        preferences.currentAudioRate = 4
        XCTAssertEqual(preferences.currentAudioRate, 4)
    }
    
    func testCurrentHighlightStyleDefaultAndRoundtrip() {
        XCTAssertEqual(preferences.currentHighlightStyle, 0)
        preferences.currentHighlightStyle = 2
        XCTAssertEqual(preferences.currentHighlightStyle, 2)
    }
    
    func testCurrentMediaOverlayStyleDefaultAndRoundtrip() {
        XCTAssertEqual(preferences.currentMediaOverlayStyle, .default)
        preferences.currentMediaOverlayStyle = .underline
        XCTAssertEqual(preferences.currentMediaOverlayStyle, .underline)
    }
    
    func testCurrentScrollDirectionDefaultAndRoundtrip() {
        XCTAssertEqual(preferences.currentScrollDirection, preferences.defaultScrollDirection.rawValue)
        preferences.currentScrollDirection = 0
        XCTAssertEqual(preferences.currentScrollDirection, 0)
    }

    func testCurrentScrollDirectionFallsBackToReaderConfigWhenUnset() {
        let config = FolioReaderConfig()
        config.scrollDirection = .vertical
        let container = FolioReaderContainer(withConfig: config, folioReader: folioReader, epubPath: "", webServer: ReadiumGCDWebServer())

        XCTAssertEqual(preferences.currentScrollDirection, FolioReaderScrollDirection.vertical.rawValue)

        // A saved user choice still takes precedence over the config.
        preferences.currentScrollDirection = FolioReaderScrollDirection.horizontalWithPagedContent.rawValue
        XCTAssertEqual(preferences.currentScrollDirection, FolioReaderScrollDirection.horizontalWithPagedContent.rawValue)
        withExtendedLifetime(container) {}
    }

    func testContainerKeepsConfiguredScrollDirectionWhenNothingSaved() {
        let config = FolioReaderConfig()
        config.scrollDirection = .vertical
        let container = FolioReaderContainer(withConfig: config, folioReader: folioReader, epubPath: "", webServer: ReadiumGCDWebServer())

        container.loadViewIfNeeded()

        XCTAssertEqual(container.readerConfig.scrollDirection, .vertical)
    }

    func testHasSavedScrollDirection() {
        XCTAssertFalse(preferences.hasSavedScrollDirection)
        preferences.currentScrollDirection = FolioReaderScrollDirection.vertical.rawValue
        XCTAssertTrue(preferences.hasSavedScrollDirection)
    }

    func testConfigTracksExplicitScrollDirection() {
        let config = FolioReaderConfig()
        XCTAssertFalse(config.hasExplicitScrollDirection)
        config.scrollDirection = .horizontalWithScrollContent
        XCTAssertTrue(config.hasExplicitScrollDirection, "Assigning the default value is still an explicit choice")
    }

    func testContainerDoesNotMarkUntouchedConfigExplicit() {
        let container = FolioReaderContainer(withConfig: FolioReaderConfig(), folioReader: folioReader, epubPath: "", webServer: ReadiumGCDWebServer())

        container.loadViewIfNeeded()

        XCTAssertFalse(container.readerConfig.hasExplicitScrollDirection)
    }

    func testParsedBookScrollDirectionPagesOnlyUnconfiguredRightToLeftBooks() {
        func direction(rtl: Bool = true, saved: Bool = false, explicit: Bool = false, canChange: Bool = true) -> FolioReaderScrollDirection? {
            ReaderPreferences.parsedBookScrollDirection(isRtl: rtl, hasSavedDirection: saved, hasExplicitConfigDirection: explicit, canChangeScrollDirection: canChange)
        }

        XCTAssertEqual(direction(), .horizontalWithPagedContent)
        XCTAssertNil(direction(rtl: false), "Left-to-right books keep the configured direction")
        XCTAssertNil(direction(saved: true), "A saved user choice wins")
        XCTAssertNil(direction(explicit: true), "An app-configured direction wins")
        XCTAssertNil(direction(canChange: false), "A locked direction is never changed")
    }
    
    func testNavigationMenuIndices() {
        XCTAssertEqual(preferences.currentNavigationMenuIndex, 0)
        preferences.currentNavigationMenuIndex = 2
        XCTAssertEqual(preferences.currentNavigationMenuIndex, 2)
        
        XCTAssertEqual(preferences.currentAnnotationMenuIndex, 0)
        preferences.currentAnnotationMenuIndex = 1
        XCTAssertEqual(preferences.currentAnnotationMenuIndex, 1)
    }
    
    func testNavigationMenuBookListStyle() {
        // structuralStyle defaults to .atom, so currentNavigationMenuBookListStyle defaults to .List
        XCTAssertEqual(preferences.currentNavigationMenuBookListStyle, .List)
        
        // To read/write .Grid, we must set structuralStyle to .bundle
        preferences.structuralStyle = .bundle
        preferences.currentNavigationMenuBookListStyle = .Grid
        XCTAssertEqual(preferences.currentNavigationMenuBookListStyle, .Grid)
    }
    
    func testMarginsLinked() {
        XCTAssertTrue(preferences.currentVMarginLinked)
        preferences.currentVMarginLinked = false
        XCTAssertFalse(preferences.currentVMarginLinked)
        
        XCTAssertTrue(preferences.currentHMarginLinked)
        preferences.currentHMarginLinked = false
        XCTAssertFalse(preferences.currentHMarginLinked)
    }
    
    func testMarginTopBottomLeftRight() {
        XCTAssertEqual(preferences.currentMarginTop, preferences.defaultMarginTop)
        preferences.currentMarginTop = 15
        XCTAssertEqual(preferences.currentMarginTop, 15)
        
        XCTAssertEqual(preferences.currentMarginBottom, preferences.defaultMarginBottom)
        preferences.currentMarginBottom = 25
        XCTAssertEqual(preferences.currentMarginBottom, 25)
        
        XCTAssertEqual(preferences.currentMarginLeft, preferences.defaultMarginLeft)
        preferences.currentMarginLeft = 35
        XCTAssertEqual(preferences.currentMarginLeft, 35)
        
        XCTAssertEqual(preferences.currentMarginRight, preferences.defaultMarginRight)
        preferences.currentMarginRight = 45
        XCTAssertEqual(preferences.currentMarginRight, 45)
    }
    
    func testTypographyAndLayout() {
        XCTAssertEqual(preferences.currentLetterSpacing, 2)
        preferences.currentLetterSpacing = 5
        XCTAssertEqual(preferences.currentLetterSpacing, 5)
        
        XCTAssertEqual(preferences.currentLineHeight, 3)
        preferences.currentLineHeight = 5
        XCTAssertEqual(preferences.currentLineHeight, 5)
        
        XCTAssertEqual(preferences.currentTextIndent, 2)
        preferences.currentTextIndent = 1
        XCTAssertEqual(preferences.currentTextIndent, 1)
        
        XCTAssertFalse(preferences.doWrapPara)
        preferences.doWrapPara = true
        XCTAssertTrue(preferences.doWrapPara)
        
        XCTAssertTrue(preferences.doClearClass)
        preferences.doClearClass = false
        XCTAssertFalse(preferences.doClearClass)
        
        XCTAssertEqual(preferences.styleOverride, .PNode)
        preferences.styleOverride = .PlusTD
        XCTAssertEqual(preferences.styleOverride, .PlusTD)
    }
    
    func testStructuralStyleAndTrackingTocLevel() {
        XCTAssertEqual(preferences.structuralStyle, .atom)
        preferences.structuralStyle = .bundle
        XCTAssertEqual(preferences.structuralStyle, .bundle)
        
        XCTAssertEqual(preferences.structuralTrackingTocLevel, .linear)
        preferences.structuralTrackingTocLevel = .level1
        XCTAssertEqual(preferences.structuralTrackingTocLevel, .level1)
    }

    func testPageModeRefreshNotificationIsScopedToReaderInstance() {
        let otherReader = FolioReader()
        var matchingNotifications = 0
        var otherNotifications = 0

        let matchingObserver = NotificationCenter.default.addObserver(
            forName: .folioReaderNeedRefreshPageMode,
            object: folioReader,
            queue: nil
        ) { _ in
            matchingNotifications += 1
        }
        let otherObserver = NotificationCenter.default.addObserver(
            forName: .folioReaderNeedRefreshPageMode,
            object: otherReader,
            queue: nil
        ) { _ in
            otherNotifications += 1
        }
        defer {
            NotificationCenter.default.removeObserver(matchingObserver)
            NotificationCenter.default.removeObserver(otherObserver)
        }

        preferences.postPageModeRefresh()

        XCTAssertEqual(matchingNotifications, 1)
        XCTAssertEqual(otherNotifications, 0)
    }

    func testIdentifierAwarePreferenceProviderIsolatesReaderInstances() {
        let scopedDelegate = IdentifierScopedPreferenceDelegate()
        let firstReader = FolioReader()
        let secondReader = FolioReader()
        firstReader.delegate = scopedDelegate
        secondReader.delegate = scopedDelegate

        _ = FolioReaderContainer(
            withConfig: FolioReaderConfig(withIdentifier: "reader-one"),
            folioReader: firstReader,
            epubPath: "",
            webServer: ReadiumGCDWebServer()
        )
        _ = FolioReaderContainer(
            withConfig: FolioReaderConfig(withIdentifier: "reader-two"),
            folioReader: secondReader,
            epubPath: "",
            webServer: ReadiumGCDWebServer()
        )

        firstReader.preferences.currentFont = "Arial"
        secondReader.preferences.currentFont = "Georgia"

        XCTAssertEqual(firstReader.preferences.currentFont, "Arial")
        XCTAssertEqual(secondReader.preferences.currentFont, "Georgia")
        XCTAssertNotEqual(firstReader.preferences.currentFont, secondReader.preferences.currentFont)
    }
}

private class IdentifierScopedPreferenceDelegate: NSObject, FolioReaderDelegate {
    private var providers = [String: MockPreferenceProvider]()

    func folioReaderPreferenceProvider(_ folioReader: FolioReader) -> FolioReaderPreferenceProvider {
        let identifier = folioReader.readerConfig?.identifier ?? "default"
        if let provider = providers[identifier] {
            return provider
        }

        let provider = MockPreferenceProvider()
        providers[identifier] = provider
        return provider
    }
}
