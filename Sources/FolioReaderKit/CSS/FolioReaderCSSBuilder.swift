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
/// Settings never generate new CSS at runtime: `baseStyleSheet` contains a rule for every
/// value of every setting, and `bodyClasses(for:)` picks which of those rules apply.
/// Both sides take their names from `ClassToken`, so selectors and classes can't drift apart.
enum FolioReaderCSSBuilder {

    /// Setting-specific part of a `folioStyleL<level><token>` class name.
    enum ClassToken {
        static func fontFamily(_ name: String) -> String { "FontFamily\(name.replacingOccurrences(of: " ", with: "_"))" }
        static func fontSize(_ size: String) -> String { "FontSize\(size.replacingOccurrences(of: ".", with: ""))" }
        static func fontWeight(_ weight: String) -> String { "FontWeight\(weight)" }
        static func letterSpacing(_ value: Int) -> String { "LetterSpacing\(value)" }
        static func lineHeight(_ value: Int) -> String { "LineHeight\(value)" }
        static func marginH(_ value: Int) -> String { "MarginH\(value)" }
        static func marginV(_ value: Int) -> String { "MarginV\(value)" }
        static func textIndent(_ value: Int) -> String { "TextIndent\(value)" }
    }

    enum BodyPadding: String {
        case left = "Left", right = "Right", top = "Top", bottom = "Bottom"

        func className(_ value: Int) -> String { "folioStyleBodyPadding\(rawValue)\(value)" }
    }

    static func levelClassName(level: StyleOverrideTypes, token: String) -> String {
        "folioStyleL\(level.rawValue)\(token)"
    }

    // MARK: - Body classes

    /// Classes `updateRuntimeStyle` puts on `<body>`. Each override level also applies all lower levels.
    static func bodyClasses(for state: FolioReaderStyleState) -> [String] {
        var classes: [String]
        if state.isVerticalWritingMode {
            classes = [BodyPadding.top.className(state.marginTop / 5), BodyPadding.bottom.className(state.marginBottom / 5)]
        } else {
            classes = [BodyPadding.left.className(state.marginLeft / 5), BodyPadding.right.className(state.marginRight / 5)]
        }

        let levels = StyleOverrideTypes.allCases.filter { $0 != .None && $0.rawValue <= state.styleOverride.rawValue }
        for level in levels.reversed() {
            classes += [
                ClassToken.fontFamily(state.font),
                ClassToken.fontSize(state.fontSize),
                ClassToken.fontWeight(state.fontWeight),
                ClassToken.letterSpacing(state.letterSpacing),
                ClassToken.lineHeight(state.lineHeight),
                // Paragraph spacing follows the line-height setting, not the page margins.
                state.isVerticalWritingMode ? ClassToken.marginV(state.lineHeight) : ClassToken.marginH(state.lineHeight),
                ClassToken.textIndent(state.textIndent + 4)
            ].map { levelClassName(level: level, token: $0) }
        }
        return classes
    }

    // MARK: - Style sheets

    /// The bundled `Style.css`, or `nil` if it is missing from the framework bundle.
    static let bundledStyleCSS: String? = {
        guard let cssURL = Bundle.frameworkBundle().url(forResource: "Style", withExtension: "css"),
              let cssSource = try? String(contentsOf: cssURL) else {
            print("ERROR: Could not find Style.css in bundle \(Bundle.frameworkBundle())")
            return nil
        }
        return cssSource
    }()

    /// `Style.css` followed by `levelRules()`; the content of the `folio_bundle_style` element.
    static func baseStyleSheet(styleCSS: String? = bundledStyleCSS) -> String {
        ((styleCSS.map { [$0] } ?? []) + levelRules()).joined(separator: "\n")
    }

    /// One rule per line for every setting value `bodyClasses(for:)` can select, except font families.
    static func levelRules() -> [String] {
        var cssStrings = [String]()

        cssStrings.append(
            contentsOf: FolioReader.FontSizes.map {
                levels(ClassToken.fontSize($0), def: "font-size: \($0) !important;")
            }.flatMap { $0 }
        )

        cssStrings.append(
            contentsOf: (1...9).map {
                levels(ClassToken.fontWeight("\($0*100)"), def: "font-weight: \($0*100) !important;")
            }.flatMap { $0 }
        )

        cssStrings.append(
            contentsOf: (0...10).map {
                levels(ClassToken.letterSpacing($0), def: "letter-spacing: \(Double($0) / 50.0)em !important; --letter-spacing: \(Double($0) / 50.0)em")
            }.flatMap { $0 }
        )

        cssStrings.append(
            contentsOf: (0...10).map { //1.5 ~ 2.05
                [
                    levels(ClassToken.lineHeight($0), def: "line-height: \(Decimal(($0 + 10) * 5) / 100 + 1) !important;"),
                    levels(ClassToken.marginH($0), def: "margin-top: 1em; margin-bottom: \((Decimal($0 + 10) * 5) / 100)em;"),
                    levels(ClassToken.marginV($0), def: "margin-right: 0em; margin-left: \((Decimal($0 + 10) * 5) / 200)em;")
                ]
            }.flatMap { $0.flatMap { $0 } }
        )

        cssStrings.append(
            contentsOf: (0...8).map {     //-4 ~ 4
                levels(ClassToken.textIndent($0), def: "text-indent: calc( (var(--letter-spacing) + 1em) * \(abs($0-4)) ) \($0<4 ? "hanging" : "") !important; text-align: justify !important; -webkit-hyphens: auto !important;")
            }.flatMap { $0 }
        )

        cssStrings.append(
            contentsOf: (0...8).map {     //-4 ~ 4
                imgLevels(ClassToken.textIndent($0), def: "max-height: \(96 - max($0*2,0))vh !important; max-width: \(96 - max($0*2,0))vw !important;")
            }.flatMap { $0 }
        )

        cssStrings.append(contentsOf: (0...10).map {
            ".\(BodyPadding.left.className($0)) { padding-left: \(Double($0) * 2.5)vw !important; overflow: hidden !important;}"
        })

        cssStrings.append(contentsOf: (0...10).map {
            ".\(BodyPadding.right.className($0)) { padding-right: \(Double($0) * 2.5)vw !important; overflow: hidden !important;}"
        })

        cssStrings.append(contentsOf: (0...10).map {
            ".\(BodyPadding.top.className($0)) { padding-top: \(Double($0) * 2.5)vh !important;}"
        })

        cssStrings.append(contentsOf: (0...10).map {
            ".\(BodyPadding.bottom.className($0)) { padding-bottom: \(Double($0) * 2.5)vh !important;}"
        })

        cssStrings.append(contentsOf: (0...10).map {
            ".\(BodyPadding.left.className($0)) img.folioImg { margin-left: -\(Double($0-1) * 2.5)vw !important; overflow: hidden !important;}"
        })

        cssStrings.append(contentsOf: (0...10).map {
            ".\(BodyPadding.right.className($0)) img.folioImg { margin-right: -\(Double($0-1) * 2.5)vw !important; overflow: hidden !important;}"
        })

        cssStrings.append(contentsOf: (0...10).map {
            ".\(BodyPadding.top.className($0)) img.folioImg { margin-top: -\(Double($0-1) * 2.5)vh !important;}"
        })

        cssStrings.append(contentsOf: (0...10).map {
            ".\(BodyPadding.bottom.className($0)) img.folioImg { margin-bottom: -\(Double($0-1) * 2.5)vh !important;}"
        })

        return cssStrings
    }

    /// `FontFamily*` level rules for each family; callers pass `UIFont.familyNames`.
    static func fontFamilyRules(familyNames: [String]) -> String {
        familyNames.map {
            levels(ClassToken.fontFamily($0), def: "font-family: \"\($0)\" !important;")
        }.flatMap { $0 }.joined(separator: "\n")
    }

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

    private static let levelTags: [StyleOverrideTypes: String] = [.PNode: "p", .PlusTD: "td", .PlusSPAN: "span", .AllText: ""]

    /// One rule per override level, matching `<body>` classes produced by `levelClassName`.
    private static func levels(_ token: String, def: String) -> [String] {
        levelTags.map {
            let className = levelClassName(level: $0, token: token)
            let separator = $1.isEmpty ? "" : " "
            return "html body.\(className) \($1), body.\(className)\(separator)\($1) { \(def) }"
        }.sorted()
    }

    private static func imgLevels(_ token: String, def: String) -> [String] {
        levelTags.map {
            let className = levelClassName(level: $0, token: token)
            let separator = $1.isEmpty ? "" : " "
            return "html body.\(className) \($1) img.folioImg, body.\(className)\(separator)\($1) img.folioImg { \(def) }"
        }.sorted()
    }
}
