//
//  FolioReaderCSSBuilder.swift
//  FolioReaderKit
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import UIKit

/// Reader style settings that select the `folioStyle*` classes on `<body>`.
struct FolioReaderStyleState: Equatable {
    var styleOverride: StyleOverrideTypes
    var font: String
    var fontSize: String
    var fontWeight: String
    var letterSpacing: Int
    var lineHeight: Int
    var textIndent: Int
    var marginTop: Int
    var marginBottom: Int
    var marginLeft: Int
    var marginRight: Int
    var isVerticalWritingMode: Bool
}

extension FolioReaderStyleState {
    init(preferences: ReaderPreferences, isVerticalWritingMode: Bool) {
        self.init(
            styleOverride: preferences.styleOverride,
            font: preferences.currentFont,
            fontSize: preferences.currentFontSize,
            fontWeight: preferences.currentFontWeight,
            letterSpacing: preferences.currentLetterSpacing,
            lineHeight: preferences.currentLineHeight,
            textIndent: preferences.currentTextIndent,
            marginTop: preferences.currentMarginTop,
            marginBottom: preferences.currentMarginBottom,
            marginLeft: preferences.currentMarginLeft,
            marginRight: preferences.currentMarginRight,
            isVerticalWritingMode: isVerticalWritingMode
        )
    }
}

/// Builds every CSS string and `<body>` class name used by the reader.
///
/// The setting rules in `baseStyleSheet` are fixed: they read every value from a `--folio-*`
/// custom property. `updateRuntimeStyle` sets those properties on `<body>` from
/// `customProperties(for:)` and adds `bodyClasses(for:)`, which choose the elements the rules
/// reach. A rule must only reach elements while its properties are set, because a `var()` that
/// refers to an unset property makes the declaration reset the property instead of being ignored.
enum FolioReaderCSSBuilder {

    /// Classes that turn the setting rules on. The `folioStyle` prefix lets the runtime script clear them.
    enum BodyClass {
        static let horizontal = "folioStyleHorizontal"
        static let vertical = "folioStyleVertical"

        /// Applies the text settings to the elements of `level`; levels are cumulative.
        static func scope(_ level: StyleOverrideTypes) -> String {
            "folioStyleScope\(scopeNames[level] ?? "")"
        }

        private static let scopeNames: [StyleOverrideTypes: String] = [.PNode: "P", .PlusTD: "TD", .PlusSPAN: "SPAN", .AllText: "All"]
    }

    /// Custom properties the setting rules read, set on `<body>` by `updateRuntimeStyle`.
    enum CustomProperty: String, CaseIterable {
        case fontFamily = "--folio-font-family"
        case fontSize = "--folio-font-size"
        case fontWeight = "--folio-font-weight"
        case letterSpacing = "--folio-letter-spacing"
        case lineHeight = "--folio-line-height"
        case textIndent = "--folio-text-indent"
        case paragraphSpaceBefore = "--folio-paragraph-space-before"
        case paragraphSpaceAfter = "--folio-paragraph-space-after"
        case imageMaxHeight = "--folio-image-max-height"
        case imageMaxWidth = "--folio-image-max-width"
        case paddingTop = "--folio-padding-top"
        case paddingBottom = "--folio-padding-bottom"
        case paddingLeft = "--folio-padding-left"
        case paddingRight = "--folio-padding-right"

        var reference: String { "var(\(rawValue))" }
    }

    // MARK: - Body classes and properties

    /// Classes `updateRuntimeStyle` puts on `<body>`. Each override level also applies all lower levels.
    static func bodyClasses(for state: FolioReaderStyleState) -> [String] {
        let levels = StyleOverrideTypes.allCases.filter { $0 != .None && $0.rawValue <= state.styleOverride.rawValue }
        return [state.isVerticalWritingMode ? BodyClass.vertical : BodyClass.horizontal] + levels.map(BodyClass.scope)
    }

    /// Values for every `CustomProperty`, in declaration order, so the rules never see an unset one.
    static func customProperties(for state: FolioReaderStyleState) -> [(name: String, value: String)] {
        let letterSpacing = Double(state.letterSpacing) / 50.0
        // Paragraph spacing follows the line-height setting, not the page margins.
        let spaceAfter = Decimal(state.lineHeight + 10) * 5 / 100
        // The image limit follows the text indent setting: 96 at -4 down to 80 at 4.
        let imageMax = 96 - max((state.textIndent + 4) * 2, 0)

        let values: [CustomProperty: String] = [
            .fontFamily: cssString(state.font),
            .fontSize: state.fontSize,
            .fontWeight: state.fontWeight,
            .letterSpacing: "\(letterSpacing)em",
            .lineHeight: "\(Decimal((state.lineHeight + 10) * 5) / 100 + 1)",
            .textIndent: "calc((\(letterSpacing)em + 1em) * \(abs(state.textIndent)))\(state.textIndent < 0 ? " hanging" : "")",
            .paragraphSpaceBefore: state.isVerticalWritingMode ? "0em" : "1em",
            .paragraphSpaceAfter: state.isVerticalWritingMode ? "\(spaceAfter / 2)em" : "\(spaceAfter)em",
            .imageMaxHeight: "\(imageMax)vh",
            .imageMaxWidth: "\(imageMax)vw",
            // Each margin step of 5 is 2.5% of the viewport.
            .paddingTop: "\(Double(state.marginTop / 5) * 2.5)vh",
            .paddingBottom: "\(Double(state.marginBottom / 5) * 2.5)vh",
            .paddingLeft: "\(Double(state.marginLeft / 5) * 2.5)vw",
            .paddingRight: "\(Double(state.marginRight / 5) * 2.5)vw",
        ]
        return CustomProperty.allCases.map { (name: $0.rawValue, value: values[$0] ?? "") }
    }

    /// `value` as a double-quoted CSS string.
    static func cssString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: - Style sheets

    /// The bundled `Style.css`, or `nil` if it is missing from the framework bundle.
    static let bundledStyleCSS: String? = {
        guard let cssURL = Bundle.frameworkBundle().url(forResource: "Style", withExtension: "css"),
              let cssSource = try? String(contentsOf: cssURL, encoding: .utf8) else {
            print("ERROR: Could not find Style.css in bundle \(Bundle.frameworkBundle())")
            return nil
        }
        return cssSource
    }()

    /// `Style.css` followed by `settingRules`; the content of the `folio_bundle_style` element.
    static func baseStyleSheet(styleCSS: String? = bundledStyleCSS) -> String {
        ((styleCSS.map { [$0] } ?? []) + [settingRules]).joined(separator: "\n")
    }

    /// The rules behind every reader setting. Values come from `CustomProperty`, scopes from `BodyClass`.
    static let settingRules: String = {
        typealias P = CustomProperty
        let horizontal = ".\(BodyClass.horizontal)"
        let vertical = ".\(BodyClass.vertical)"
        return """
            \(scopedSelectors()) {
                font-family: \(P.fontFamily.reference) !important;
                font-size: \(P.fontSize.reference) !important;
                font-weight: \(P.fontWeight.reference) !important;
                letter-spacing: \(P.letterSpacing.reference) !important;
                line-height: \(P.lineHeight.reference) !important;
                text-indent: \(P.textIndent.reference) !important;
                text-align: justify !important;
                -webkit-hyphens: auto !important;
            }
            \(scopedSelectors()) {
                margin-block-start: \(P.paragraphSpaceBefore.reference);
                margin-block-end: \(P.paragraphSpaceAfter.reference);
            }
            \(scopedSelectors(descendant: "img.folioImg")) {
                max-height: \(P.imageMaxHeight.reference) !important;
                max-width: \(P.imageMaxWidth.reference) !important;
            }
            \(horizontal) {
                padding-left: \(P.paddingLeft.reference) !important;
                padding-right: \(P.paddingRight.reference) !important;
                overflow: hidden !important;
            }
            \(vertical) {
                padding-top: \(P.paddingTop.reference) !important;
                padding-bottom: \(P.paddingBottom.reference) !important;
            }
            \(horizontal) img.folioImg {
                margin-left: calc(-1 * max(\(P.paddingLeft.reference) - 2.5vw, 0vw)) !important;
                margin-right: calc(-1 * max(\(P.paddingRight.reference) - 2.5vw, 0vw)) !important;
                overflow: hidden !important;
            }
            \(vertical) img.folioImg {
                margin-top: calc(-1 * max(\(P.paddingTop.reference) - 2.5vh, 0vh)) !important;
                margin-bottom: calc(-1 * max(\(P.paddingBottom.reference) - 2.5vh, 0vh)) !important;
            }
            """
    }()

    /// `@font-face` rules for user fonts, served by `EpubResourceServer` under `/_fonts/`.
    static func userFontFaceRules(descriptors: [String: CTFontDescriptor]) -> String {
        descriptors.compactMap { _, fontDescriptor -> String? in
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

            if let ctFontTraits = CTFontDescriptorCopyAttribute(fontDescriptor, kCTFontTraitsAttribute) as? NSDictionary {
                let traitsDict = ctFontTraits as CFDictionary
                if let ctFontSymbolicTrait = CFDictionaryGetValue(
                    traitsDict,
                    unsafeBitCast(kCTFontSymbolicTrait, to: UnsafeRawPointer.self))  {

                    var symTraitVal = UInt32()
                    CFNumberGetValue(unsafeBitCast(ctFontSymbolicTrait, to: CFNumber.self), CFNumberType.intType, &symTraitVal)

                    isItalic = symTraitVal & CTFontSymbolicTraits.traitItalic.rawValue > 0
                    isBold = symTraitVal & CTFontSymbolicTraits.traitBold.rawValue > 0

                    cssFontWeight = isBold ? "bold" : "normal"
                }

                if let weightRef = CFDictionaryGetValue(
                    traitsDict,
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

            return "@font-face { font-family: \"\(fontFamilyName)\"; font-style: \(isItalic ? "italic" : "normal"); font-weight: \(cssFontWeight); src: url(\"/_fonts/\(fontURL.lastPathComponent)\");} "

        }.joined(separator: " ")
    }

    /// Content of the `folio_style_overflow` element for the current scroll mode and writing mode.
    static func overflowCSS(overflow: String, verticalWritingMode: Bool) -> String {
        var cssText = "html { overflow: \(overflow) !important; display: block !important; text-align: justify !important;}"
        if overflow == "-webkit-paged-x" {
            if verticalWritingMode {
                cssText += " body { min-width: 100vw; margin: 0 0 !important; }"
            } else {
                cssText += " body { min-height: 100vh; margin: 0 0 !important; }"
            }
        }
        return cssText
    }

    // MARK: - Selectors

    private static let levelTags: [(StyleOverrideTypes, String)] = [(.PNode, "p"), (.PlusTD, "td"), (.PlusSPAN, "span"), (.AllText, "")]

    /// One selector per override level, matching `BodyClass.scope`; `AllText` selects `<body>` itself.
    private static func scopedSelectors(descendant: String? = nil) -> String {
        levelTags.map { level, tag in
            (["html body.\(BodyClass.scope(level))"] + [tag, descendant ?? ""].filter { !$0.isEmpty }).joined(separator: " ")
        }.joined(separator: ",\n")
    }
}
