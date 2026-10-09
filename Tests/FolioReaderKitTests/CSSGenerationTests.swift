//
//  CSSGenerationTests.swift
//  FolioReaderKitTests
//
//  Created by DeepMind Antigravity on 7/3/26.
//  Copyright © 2026 FolioReader. All rights reserved.
//

import CoreText
import XCTest
@testable import FolioReaderKit

class CSSGenerationTests: XCTestCase {

    private func state(
        _ styleOverride: StyleOverrideTypes,
        vertical: Bool = false,
        font: String = "Helvetica Neue",
        fontSize: String = "18.5px",
        fontWeight: String = "400",
        letterSpacing: Int = 2,
        lineHeight: Int = 3,
        textIndent: Int = 1,
        margins: (top: Int, bottom: Int, left: Int, right: Int) = (10, 15, 20, 25)
    ) -> FolioReaderStyleState {
        FolioReaderStyleState(
            styleOverride: styleOverride,
            font: font,
            fontSize: fontSize,
            fontWeight: fontWeight,
            letterSpacing: letterSpacing,
            lineHeight: lineHeight,
            textIndent: textIndent,
            marginTop: margins.top,
            marginBottom: margins.bottom,
            marginLeft: margins.left,
            marginRight: margins.right,
            isVerticalWritingMode: vertical
        )
    }

    // MARK: - Body classes and properties

    func testBodyClassesHorizontalPlusTD() {
        XCTAssertEqual(
            FolioReaderCSSBuilder.bodyClasses(for: state(.PlusTD)),
            ["folioStyleHorizontal", "folioStyleScopeP", "folioStyleScopeTD", "folioStyleFontScopeP", "folioStyleFontScopeTD"]
        )
    }

    func testBodyClassesVerticalAllText() {
        XCTAssertEqual(
            FolioReaderCSSBuilder.bodyClasses(for: state(.AllText, vertical: true)),
            ["folioStyleVertical", "folioStyleScopeP", "folioStyleScopeTD", "folioStyleScopeSPAN", "folioStyleScopeAll",
             "folioStyleFontScopeP", "folioStyleFontScopeTD", "folioStyleFontScopeSPAN", "folioStyleFontScopeAll"]
        )
    }

    /// An unknown family (YetAnotherEBookReader's "Original", meaning the publisher's font, or a removed
    /// user font) gets no font classes, so the book keeps its fonts; the other settings still apply.
    func testUnavailableFontLeavesTheBookFonts() {
        var unavailable = state(.PlusTD)
        unavailable.isFontAvailable = false
        XCTAssertEqual(FolioReaderCSSBuilder.bodyClasses(for: unavailable), ["folioStyleHorizontal", "folioStyleScopeP", "folioStyleScopeTD"])
        XCTAssertFalse(FolioReaderStyleState.isAvailableFont("Original", userFontDescriptors: [:]))
        XCTAssertTrue(FolioReaderStyleState.isAvailableFont("Helvetica Neue", userFontDescriptors: [:]))
        XCTAssertTrue(FolioReaderStyleState.isAvailableFont("Reader Test Font", userFontDescriptors: [
            "reader-test-font": CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: "Reader Test Font"] as CFDictionary),
        ]))
    }

    func testBodyClassesNoneHasOnlyWritingMode() {
        XCTAssertEqual(FolioReaderCSSBuilder.bodyClasses(for: state(.None)), ["folioStyleHorizontal"])
    }

    func testCustomPropertiesHorizontal() {
        let properties = FolioReaderCSSBuilder.customProperties(for: state(.PNode))
        XCTAssertEqual(properties.map { $0.name }, FolioReaderCSSBuilder.CustomProperty.allCases.map { $0.rawValue })
        XCTAssertEqual(properties.map { $0.value }, [
            "\"Helvetica Neue\"", "18.5px", "400", "0.04em", "1.65",
            "calc((0.04em + 1em) * 1)",
            "1em", "0.65em",
            "5.0vh", "7.5vh", "10.0vw", "12.5vw",
            "env(safe-area-inset-left, 0px)", "env(safe-area-inset-right, 0px)",
        ])
    }

    /// Apps that turn off `reserveSafeAreaInsidePageFrame` want edge-to-edge pages, in landscape too.
    func testSideSafeAreaFollowsTheReserveSetting() {
        var edgeToEdge = state(.PNode)
        edgeToEdge.reserveSafeArea = false
        let values = Dictionary(uniqueKeysWithValues: FolioReaderCSSBuilder.customProperties(for: edgeToEdge).map { ($0.name, $0.value) })
        XCTAssertEqual(values["--folio-safe-area-left"], "0px")
        XCTAssertEqual(values["--folio-safe-area-right"], "0px")
    }

    func testCustomPropertiesVerticalHangingIndent() {
        let values = Dictionary(uniqueKeysWithValues: FolioReaderCSSBuilder.customProperties(
            for: state(.PNode, vertical: true, textIndent: -3)
        ).map { ($0.name, $0.value) })
        XCTAssertEqual(values["--folio-text-indent"], "calc((0.04em + 1em) * 3) hanging")
        XCTAssertEqual(values["--folio-paragraph-space-before"], "0em")
        XCTAssertEqual(values["--folio-paragraph-space-after"], "0.325em")
    }

    func testZeroMarginsEmitZeroPadding() {
        let values = Dictionary(uniqueKeysWithValues: FolioReaderCSSBuilder.customProperties(
            for: state(.None, margins: (0, 0, 0, 0))
        ).map { ($0.name, $0.value) })
        XCTAssertEqual(values["--folio-padding-top"], "0.0vh")
        XCTAssertEqual(values["--folio-padding-bottom"], "0.0vh")
        XCTAssertEqual(values["--folio-padding-left"], "0.0vw")
        XCTAssertEqual(values["--folio-padding-right"], "0.0vw")
    }

    func testFontFamilyIsQuotedAndEscaped() {
        XCTAssertEqual(FolioReaderCSSBuilder.cssString("Gill Sans"), "\"Gill Sans\"")
        XCTAssertEqual(FolioReaderCSSBuilder.cssString("a\"b\\c"), "\"a\\\"b\\\\c\"")
    }

    /// A `var()` whose property is never set resets the declaration instead of being ignored,
    /// so every property the rules read must get a value.
    func testEveryReferencedPropertyHasAValue() throws {
        let regex = try NSRegularExpression(pattern: "var\\((--[a-z-]+)\\)")
        let rules = FolioReaderCSSBuilder.settingRules
        let referenced = Set(regex.matches(in: rules, range: NSRange(rules.startIndex..., in: rules)).compactMap {
            Range($0.range(at: 1), in: rules).map { String(rules[$0]) }
        })
        XCTAssertFalse(referenced.isEmpty)

        for vertical in [false, true] {
            let properties = FolioReaderCSSBuilder.customProperties(for: state(.AllText, vertical: vertical))
            XCTAssertTrue(properties.allSatisfy { !$0.value.isEmpty })
            XCTAssertEqual(referenced.subtracting(properties.map { $0.name }), [])
        }
    }

    // MARK: - Style sheets

    func testBaseStyleSheetIsStyleCSSFollowedBySettingRules() throws {
        let styleURL = try XCTUnwrap(Bundle.frameworkBundle().url(forResource: "Style", withExtension: "css"))
        let styleCSS = try String(contentsOf: styleURL, encoding: .utf8)

        XCTAssertEqual(FolioReaderCSSBuilder.bundledStyleCSS, styleCSS)
        XCTAssertEqual(FolioReaderCSSBuilder.baseStyleSheet(), styleCSS + "\n" + FolioReaderCSSBuilder.settingRules)
        XCTAssertEqual(FolioReaderCSSBuilder.baseStyleSheet(styleCSS: nil), FolioReaderCSSBuilder.settingRules)
    }

    func testUserFontFaceRulesEmpty() {
        XCTAssertTrue(FolioReaderCSSBuilder.userFontFaceRules(descriptors: [:]).isEmpty)
    }

    func testOverflowCSS() {
        let html = "html { overflow: scroll !important; display: block !important; text-align: justify !important;}"
        XCTAssertEqual(FolioReaderCSSBuilder.overflowCSS(overflow: "scroll", verticalWritingMode: false), html)
        XCTAssertEqual(FolioReaderCSSBuilder.overflowCSS(overflow: "scroll", verticalWritingMode: true), html)

        let pagedHTML = "html { overflow: -webkit-paged-x !important; display: block !important; text-align: justify !important;}"
        XCTAssertEqual(
            FolioReaderCSSBuilder.overflowCSS(overflow: "-webkit-paged-x", verticalWritingMode: false),
            pagedHTML + " body { min-height: 100vh; margin: 0 0 !important; }"
        )
        XCTAssertEqual(
            FolioReaderCSSBuilder.overflowCSS(overflow: "-webkit-paged-x", verticalWritingMode: true),
            pagedHTML + " body { min-width: 100vw; margin: 0 0 !important; }"
        )
    }

    // MARK: - Custom style sheets

    func testCustomSheetsFilterByStagePrefixIDsAndKeepLastDuplicate() {
        let sheets = [
            FolioReaderStyleSheet(id: "a", css: "a1", stage: .runtime),
            FolioReaderStyleSheet(id: "b", css: "b1", stage: .documentBase),
            FolioReaderStyleSheet(id: "c", css: "c1", stage: .runtime),
            FolioReaderStyleSheet(id: "a", css: "a2", stage: .runtime),
            FolioReaderStyleSheet(id: "a", css: "a-base", stage: .documentBase),
        ]

        let runtime = FolioReaderCSSInjector.customSheets(sheets, stage: .runtime)
        XCTAssertEqual(runtime.map { $0.id }, ["folio_custom_a", "folio_custom_c"])
        XCTAssertEqual(runtime.map { $0.css }, ["a2", "c1"])

        let documentBase = FolioReaderCSSInjector.customSheets(sheets, stage: .documentBase)
        XCTAssertEqual(documentBase.map { $0.id }, ["folio_custom_b", "folio_custom_a"])
        XCTAssertEqual(documentBase.map { $0.css }, ["b1", "a-base"])
    }

    func testBundledPageStyleDoesNotForceTopOrBottomPageMargins() {
        let source = FolioReaderCSSBuilder.baseStyleSheet()

        XCTAssertTrue(source.contains("@page"))
        XCTAssertTrue(source.contains("margin: 0 0 !important;"))
        XCTAssertFalse(source.contains("margin-top: 1em !important;"))
        XCTAssertFalse(source.contains("margin-bottom: 1em !important;"))
    }
}
