//
//  CSSGenerationTests.swift
//  FolioReaderKitTests
//
//  Created by DeepMind Antigravity on 7/3/26.
//  Copyright © 2026 FolioReader. All rights reserved.
//

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

    // MARK: - Body classes (expected lists follow the former JS in updateRuntimeStyle)

    func testBodyClassesHorizontalPlusTD() {
        let level = { (n: Int) in [
            "folioStyleL\(n)FontFamilyHelvetica_Neue",
            "folioStyleL\(n)FontSize185px",
            "folioStyleL\(n)FontWeight400",
            "folioStyleL\(n)LetterSpacing2",
            "folioStyleL\(n)LineHeight3",
            "folioStyleL\(n)MarginH3",
            "folioStyleL\(n)TextIndent5",
        ] }
        XCTAssertEqual(
            FolioReaderCSSBuilder.bodyClasses(for: state(.PlusTD)),
            ["folioStyleBodyPaddingLeft4", "folioStyleBodyPaddingRight5"] + level(2) + level(1)
        )
    }

    func testBodyClassesVerticalAllText() {
        let classes = FolioReaderCSSBuilder.bodyClasses(for: state(.AllText, vertical: true))

        XCTAssertEqual(Array(classes.prefix(2)), ["folioStyleBodyPaddingTop2", "folioStyleBodyPaddingBottom3"])
        XCTAssertEqual(classes.count, 2 + 4 * 7)
        XCTAssertEqual(classes[2], "folioStyleL4FontFamilyHelvetica_Neue")
        XCTAssertEqual(classes.last, "folioStyleL1TextIndent5")
        XCTAssertTrue(classes.contains("folioStyleL3MarginV3"))
        XCTAssertFalse(classes.contains { $0.contains("MarginH") })
    }

    func testBodyClassesNoneHasOnlyPadding() {
        XCTAssertEqual(
            FolioReaderCSSBuilder.bodyClasses(for: state(.None)),
            ["folioStyleBodyPaddingLeft4", "folioStyleBodyPaddingRight5"]
        )
    }

    /// Every class the reader can put on `<body>` must have a rule, or the setting silently does nothing.
    func testEveryBodyClassHasARule() {
        let styleSheet = FolioReaderCSSBuilder.baseStyleSheet(styleCSS: nil)
        let fontFamilyRules = FolioReaderCSSBuilder.fontFamilyRules(familyNames: ["Helvetica Neue"])

        var states = [FolioReaderStyleState]()
        for vertical in [false, true] {
            states += FolioReader.FontSizes.map { state(.AllText, vertical: vertical, fontSize: $0) }
            states += (1...9).map { state(.AllText, vertical: vertical, fontWeight: "\($0 * 100)") }
            states += (0...10).map { state(.AllText, vertical: vertical, letterSpacing: $0, lineHeight: $0) }
            states += (-4...4).map { state(.AllText, vertical: vertical, textIndent: $0) }
            states += stride(from: 0, through: 50, by: 5).map { state(.AllText, vertical: vertical, margins: ($0, $0, $0, $0)) }
        }

        for state in states {
            for cls in FolioReaderCSSBuilder.bodyClasses(for: state) {
                let rules = cls.contains("FontFamily") ? fontFamilyRules : styleSheet
                // The trailing space keeps e.g. PaddingLeft1 from matching PaddingLeft10.
                XCTAssertTrue(rules.contains(".\(cls) "), "No rule for body class \(cls)")
            }
        }
    }

    // MARK: - Style sheets

    func testFontFamilyRules() {
        let css = FolioReaderCSSBuilder.fontFamilyRules(familyNames: ["Helvetica Neue"])
        XCTAssertEqual(css.components(separatedBy: "\n").count, 4)
        XCTAssertTrue(css.contains("html body.folioStyleL1FontFamilyHelvetica_Neue p, body.folioStyleL1FontFamilyHelvetica_Neue p { font-family: \"Helvetica Neue\" !important; }"))
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

    func testRuntimeSheetsCarrySelectedFontFamilyThenRuntimeCustomSheets() {
        let sheets = FolioReaderCSSInjector.runtimeSheets(
            currentFont: "Gill Sans",
            customStyleSheets: [
                FolioReaderStyleSheet(id: "base", css: "b", stage: .documentBase),
                FolioReaderStyleSheet(id: "live", css: "l", stage: .runtime),
            ]
        )

        XCTAssertEqual(sheets.map { $0.id }, ["folio_style_font_families", "folio_custom_live"])
        XCTAssertTrue(sheets[0].css.contains("body.folioStyleL1FontFamilyGill_Sans p"))
        XCTAssertFalse(sheets[0].css.contains("Helvetica"), "Only the selected family gets rules")
    }

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

    func testZeroBodyPaddingClassesEmitZeroPadding() {
        let source = FolioReaderCSSBuilder.baseStyleSheet()

        XCTAssertTrue(source.contains(".folioStyleBodyPaddingLeft0 { padding-left: 0.0vw !important;"))
        XCTAssertTrue(source.contains(".folioStyleBodyPaddingRight0 { padding-right: 0.0vw !important;"))
        XCTAssertTrue(source.contains(".folioStyleBodyPaddingTop0 { padding-top: 0.0vh !important;"))
        XCTAssertTrue(source.contains(".folioStyleBodyPaddingBottom0 { padding-bottom: 0.0vh !important;"))
    }
}
