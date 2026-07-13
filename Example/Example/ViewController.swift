//
//  ViewController.swift
//  Example
//
//  Created by Heberti Almeida on 08/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import FolioReaderKit
import FolioEPUBCore
import ReadiumGCDWebServer

class ViewController: UIViewController {

    @IBOutlet weak var bookOne: UIButton?
    @IBOutlet weak var bookTwo: UIButton?

    var preferenceProvider: FolioReaderPreferenceProvider?
    var highlightProvider: FolioReaderHighlightProvider?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.bookOne?.tag = Epub.bookOne.rawValue
        self.bookTwo?.tag = Epub.bookTwo.rawValue

        self.setCover(self.bookOne, index: 0)
        self.setCover(self.bookTwo, index: 1)
    }

    private func readerConfiguration(forEpub epub: Epub) -> FolioReaderConfig {
        let config = FolioReaderConfig(withIdentifier: epub.readerIdentifier)
        config.shouldHideNavigationOnTap = epub.shouldHideNavigationOnTap
        config.scrollDirection = epub.scrollDirection
        config.allowSharing = false
        config.enableTTS = false
        config.debug.formUnion([.htmlStyling])

        // Custom sharing quote background
        config.quoteCustomBackgrounds = []
        if let image = UIImage(named: "demo-bg") {
            let customImageQuote = QuoteImage(withImage: image, alpha: 0.6, backgroundColor: UIColor.black)
            config.quoteCustomBackgrounds.append(customImageQuote)
        }

        let textColor = UIColor(red:0.86, green:0.73, blue:0.70, alpha:1.0)
        let customColor = UIColor(red:0.30, green:0.26, blue:0.20, alpha:1.0)
        let customQuote = QuoteImage(withColor: customColor, alpha: 1.0, textColor: textColor)
        config.quoteCustomBackgrounds.append(customQuote)

        return config
    }

    fileprivate func open(epub: Epub) {
        guard let bookPath = epub.bookPath else {
            return
        }

        let readerConfiguration = self.readerConfiguration(forEpub: epub)
        let folioReader = FolioReader()
        folioReader.delegate = self
        folioReader.presentReader(
            parentViewController: self,
            withEpubPath: bookPath,
            andConfig: readerConfiguration,
            animated: true,
            folioReaderCenterDelegate: nil,
            webServer: ReadiumGCDWebServer()
        )
    }

    private func setCover(_ button: UIButton?, index: Int) {
        guard
            let epub = Epub(rawValue: index),
            let bookPath = epub.bookPath else {
                return
        }

        Task {
            do {
                let data = try await FREpubParserArchive.parseCoverImage(bookPath)
                guard let image = UIImage(data: data) else { return }
                await MainActor.run {
                    button?.setBackgroundImage(image, for: .normal)
                }
            } catch {
                print(error.localizedDescription)
            }
        }
    }
    
    private func makeFolioReaderUnzipPath() -> URL? {
        guard let cacheDirectory = try? FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true) else {
            return nil
        }
        let folioReaderUnzipped = cacheDirectory.appendingPathComponent("FolioReaderUnzipped", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folioReaderUnzipped.path) {
            do {
                try FileManager.default.createDirectory(at: folioReaderUnzipped, withIntermediateDirectories: true, attributes: nil)
            } catch {
                return nil
            }
        }
        
        return folioReaderUnzipped
    }
}

extension ViewController: FolioReaderDelegate {
    
    func folioReaderPreferenceProvider(_ folioReader: FolioReader) -> FolioReaderPreferenceProvider {
        if let preferenceProvider = preferenceProvider {
            return preferenceProvider
        } else {
            let preferenceProvider = FolioReaderUserDefaultsPreferenceProvider(folioReader)
            self.preferenceProvider = preferenceProvider
            return preferenceProvider
        }
    }
    
    func folioReaderHighlightProvider(_ folioReader: FolioReader) -> FolioReaderHighlightProvider {
        if let highlightProvider = highlightProvider {
            return highlightProvider
        } else {
            let highlightProvider = FolioReaderInMemoryHighlightProvider(folioReader)
            self.highlightProvider = highlightProvider
            return highlightProvider
        }
    }
}

class FolioReaderUserDefaultsPreferenceProvider: FolioReaderDummyPreferenceProvider {
    
    internal let kCurrentFontFamily = "com.folioreader.kCurrentFontFamily"
    internal let kCurrentFontSize = "com.folioreader.kCurrentFontSize"
    internal let kCurrentFontWeight = "com.folioreader.kCurrentFontWeight"

    internal let kCurrentAudioRate = "com.folioreader.kCurrentAudioRate"
    internal let kCurrentHighlightStyle = "com.folioreader.kCurrentHighlightStyle"
    internal let kCurrentMediaOverlayStyle = "com.folioreader.kMediaOverlayStyle"
    internal let kCurrentScrollDirection = "com.folioreader.kCurrentScrollDirection"
    internal let kNightMode = "com.folioreader.kNightMode"
    internal let kThemeMode = "com.folioreader.kThemeMode"
    internal let kCurrentTOCMenu = "com.folioreader.kCurrentTOCMenu"
    internal let kCurrentMarginTop = "com.folioreader.kCurrentMarginTop"
    internal let kCurrentMarginBottom = "com.folioreader.kCurrentMarginBottom"
    internal let kCurrentMarginLeft = "com.folioreader.kCurrentMarginLeft"
    internal let kCurrentMarginRight = "com.folioreader.kCurrentMarginRight"
    internal let kCurrentLetterSpacing = "com.folioreader.kCurrentLetterSpacing"
    internal let kCurrentLineHeight = "com.folioreader.kCurrentLineHeight"
    internal let kCurrentTextIndent = "com.folioreader.kCurrentTextIndent"
    internal let kDoWrapPara = "com.folioreader.kDoWrapPara"
    internal let kDoClearClass = "com.folioreader.kDoClearClass"
    internal let kCurrentAnnotationMenuIndex = "com.folioreader.kCurrentAnnotationMenuIndex"
    internal let kCurrentNavigationMenuBookListStyle = "com.folioreader.kCurrentNavigationMenuBookListStyle"
    internal let kCurrentVMarginLinked = "com.folioreader.kCurrentVMarginLinked"
    internal let kCurrentHMarginLinked = "com.folioreader.kCurrentHMarginLinked"
    internal let kStyleOverride = "com.folioreader.kStyleOverride"
    internal let kStructuralStyle = "com.folioreader.kStructuralStyle"
    internal let kStructuralTocLevel = "com.folioreader.kStructuralTocLevel"
    
    override init(_ folioReader: FolioReader) {
        super.init(folioReader)
        
        // Register initial defaults
        register(defaults: [
            kCurrentFontFamily: "andada",
            kNightMode: false,
            kThemeMode: FolioReaderThemeMode.day.rawValue,
            kCurrentFontSize: "2",
            kCurrentAudioRate: 1,
            kCurrentHighlightStyle: 0,
            kCurrentTOCMenu: 0,
            kCurrentMediaOverlayStyle: MediaOverlayStyle.default.rawValue,
            kCurrentScrollDirection: FolioReaderScrollDirection.defaultVertical.rawValue,
            kCurrentAnnotationMenuIndex: 0,
            kCurrentNavigationMenuBookListStyle: 0,
            kCurrentVMarginLinked: true,
            kCurrentHMarginLinked: true,
            kStyleOverride: 1,
            kStructuralStyle: 0,
            kStructuralTocLevel: 0
            ])
    }
    
    fileprivate var defaults: FolioReaderUserDefaults {
        return FolioReaderUserDefaults(
            withIdentifier: folioReader.readerCenter?.readerContainer?.readerConfig.identifier)
    }

    public func register(defaults: [String: Any]) {
        self.defaults.register(defaults: defaults)
    }

    override func preference(stringFor key: String, default defaultValue: String) -> String {
        return self.defaults.value(forKey: key) as? String ?? super.preference(stringFor: key, default: defaultValue)
    }

    override func preference(setString value: String, for key: String) {
        self.defaults.set(value, forKey: key)
    }

    func preference(nightMode defaults: Bool) -> Bool {
        return self.defaults.bool(forKey: kNightMode)
    }
    
    func preference(setNightMode value: Bool){
        self.defaults.set(value, forKey: kNightMode)
    }
    
    func preference(themeMode defaults: Int) -> Int {
        return self.defaults.integer(forKey: kThemeMode)
    }
    func preference(setThemeMode value: Int) {
        self.defaults.set(value, forKey: kThemeMode)
    }
    
    func preference(currentFont defaults: String) -> String {
        return self.defaults.value(forKey: kCurrentFontFamily) as? String ?? defaults
    }
    func preference(setCurrentFont value: String) {
        self.defaults.set(value, forKey: kCurrentFontFamily)
    }
    
    func preference(currentFontSize defaults: String) -> String {
        return self.defaults.value(forKey: kCurrentFontSize) as? String ?? defaults
    }
    func preference(setCurrentFontSize value: String) {
        self.defaults.set(value, forKey: kCurrentFontSize)
    }
    
    func preference(currentFontWeight defaults: String) -> String {
        return self.defaults.value(forKey: kCurrentFontWeight) as? String ?? defaults
    }
    func preference(setCurrentFontWeight value: String) {
        self.defaults.set(value, forKey: kCurrentFontWeight)
    }
    
    func preference(currentAudioRate defaults: Int) -> Int {
        return self.defaults.integer(forKey: kCurrentAudioRate)
    }
    func preference(setCurrentAudioRate value: Int) {
        self.defaults.set(value, forKey: kCurrentAudioRate)
    }
    
    func preference(currentHighlightStyle defaults: Int) -> Int {
        return self.defaults.integer(forKey: kCurrentHighlightStyle)
    }
    func preference(setCurrentHighlightStyle value: Int) {
        self.defaults.set(value, forKey: kCurrentHighlightStyle)
    }
    
    func preference(currentMediaOverlayStyle defaults: Int) -> Int {
        return self.defaults.value(forKey: kCurrentMediaOverlayStyle) as? Int ?? defaults
    }
    func preference(setCurrentMediaOverlayStyle value: Int) {
        self.defaults.set(value, forKey: kCurrentMediaOverlayStyle)
    }
    
    func preference(currentScrollDirection defaults: Int) -> Int {
        return self.defaults.value(forKey: kCurrentScrollDirection) as? Int ?? defaults
    }
    func preference(setCurrentScrollDirection value: Int) {
        self.defaults.set(value, forKey: kCurrentScrollDirection)
    }
    
    func preference(currentNavigationMenuIndex defaults: Int) -> Int {
        return self.defaults.integer(forKey: kCurrentTOCMenu)
    }
    func preference(setCurrentNavigationMenuIndex value: Int) {
        self.defaults.set(value, forKey: kCurrentTOCMenu)
    }

    func preference(currentAnnotationMenuIndex defaults: Int) -> Int {
        return self.defaults.integer(forKey: kCurrentAnnotationMenuIndex)
    }
    func preference(setCurrentAnnotationMenuIndex value: Int) {
        self.defaults.set(value, forKey: kCurrentAnnotationMenuIndex)
    }

    func preference(currentNavigationMenuBookListStyle defaults: Int) -> Int {
        return self.defaults.integer(forKey: kCurrentNavigationMenuBookListStyle)
    }
    func preference(setCurrentNavigationMenuBookListStyle value: Int) {
        self.defaults.set(value, forKey: kCurrentNavigationMenuBookListStyle)
    }
    
    func preference(currentMarginTop defaults: Int) -> Int {
        return self.defaults.integer(forKey: kCurrentMarginTop)
    }
    func preference(setCurrentMarginTop value: Int) {
        self.defaults.set(value, forKey: kCurrentMarginTop)
    }
    
    func preference(currentMarginBottom defaults: Int) -> Int {
        return self.defaults.integer(forKey: kCurrentMarginBottom)
    }
    func preference(setCurrentMarginBottom value: Int) {
        self.defaults.set(value, forKey: kCurrentMarginBottom)
    }
    
    func preference(currentMarginLeft defaults: Int) -> Int {
        return self.defaults.integer(forKey: kCurrentMarginLeft)
    }
    func preference(setCurrentMarginLeft value: Int) {
        self.defaults.set(value, forKey: kCurrentMarginLeft)
    }
    
    func preference(currentMarginRight defaults: Int) -> Int {
        return self.defaults.integer(forKey: kCurrentMarginRight)
    }
    func preference(setCurrentMarginRight value: Int) {
        self.defaults.set(value, forKey: kCurrentMarginRight)
    }

    func preference(currentVMarginLinked defaults: Bool) -> Bool {
        return self.defaults.bool(forKey: kCurrentVMarginLinked)
    }
    func preference(setCurrentVMarginLinked value: Bool) {
        self.defaults.set(value, forKey: kCurrentVMarginLinked)
    }

    func preference(currentHMarginLinked defaults: Bool) -> Bool {
        return self.defaults.bool(forKey: kCurrentHMarginLinked)
    }
    func preference(setCurrentHMarginLinked value: Bool) {
        self.defaults.set(value, forKey: kCurrentHMarginLinked)
    }
    
    func preference(currentLetterSpacing defaults: Int) -> Int {
        return self.defaults.integer(forKey: kCurrentLetterSpacing)
    }
    func preference(setCurrentLetterSpacing value: Int) {
        self.defaults.set(value, forKey: kCurrentLetterSpacing)
    }
    
    func preference(currentLineHeight defaults: Int) -> Int {
        return self.defaults.integer(forKey: kCurrentLineHeight)
    }
    func preference(setCurrentLineHeight value: Int) {
        self.defaults.set(value, forKey: kCurrentLineHeight)
    }
    
    func preference(doWrapPara defaults: Bool) -> Bool {
        return self.defaults.bool(forKey: kDoWrapPara)
    }
    func preference(setDoWrapPara value: Bool) {
        self.defaults.set(value, forKey: kDoWrapPara)
    }
    
    func preference(doClearClass defaults: Bool) -> Bool {
        return self.defaults.bool(forKey: kDoClearClass)
    }
    func preference(setDoClearClass value: Bool) {
        self.defaults.set(value, forKey: kDoClearClass)
    }
    
    func preference(currentTextIndent defaults: Int) -> Int {
        return self.defaults.integer(forKey: kCurrentTextIndent)
    }
    func preference(setCurrentTextIndent value: Int) {
        self.defaults.set(value, forKey: kCurrentTextIndent)
    }

    func preference(styleOverride defaults: Int) -> Int {
        return self.defaults.integer(forKey: kStyleOverride)
    }
    func preference(setStyleOverride value: Int) {
        self.defaults.set(value, forKey: kStyleOverride)
    }

    func preference(structuralStyle defaults: Int) -> Int {
        return self.defaults.integer(forKey: kStructuralStyle)
    }
    func preference(setStructuralStyle value: Int) {
        self.defaults.set(value, forKey: kStructuralStyle)
    }

    func preference(structuralTocLevel defaults: Int) -> Int {
        return self.defaults.integer(forKey: kStructuralTocLevel)
    }
    func preference(setStructuralTocLevel value: Int) {
        self.defaults.set(value, forKey: kStructuralTocLevel)
    }
    
    func preference(savedPosition defaults: [String: Any]?) -> [String: Any]? {
        guard let bookId = folioReader.readerCenter?.readerContainer?.book.name else {
            return defaults
        }
        return self.defaults.value(forKey: bookId) as? [String : Any]
    }
    
    func preference(setSavedPosition value: [String: Any]) {
        guard let bookId = folioReader.readerCenter?.readerContainer?.book.name else {
            return
        }
        self.defaults.set(value, forKey: bookId)
    }
}

public class FolioReaderInMemoryHighlightProvider: NSObject, FolioReaderHighlightProvider {
    private var highlights = [String: FolioReaderHighlight]()
    let folioReader: FolioReader
    
    init(_ folioReader: FolioReader) {
        self.folioReader = folioReader
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, added highlight: FolioReaderHighlight, completion: Completion?) {
        highlights[highlight.highlightId] = highlight
        completion?(nil)
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, removedId highlightId: String) {
        highlights.removeValue(forKey: highlightId)
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, updateById highlightId: String, type style: FolioReaderHighlightStyle) {
        highlights[highlightId]?.type = style.rawValue
    }

    public func folioReaderHighlight(_ folioReader: FolioReader, getById highlightId: String) -> FolioReaderHighlight? {
        return highlights[highlightId]
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, allByBookId bookId: String, andPage page: NSNumber?) -> [FolioReaderHighlight] {
        return highlights.values.filter { $0.bookId == bookId && (page == nil || $0.page == page?.intValue) }.sorted()
    }

    public func folioReaderHighlight(_ folioReader: FolioReader) -> [FolioReaderHighlight] {
        return Array(highlights.values)
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, saveNoteFor highlight: FolioReaderHighlight) {
        highlights[highlight.highlightId] = highlight
    }
}

// MARK: - IBAction

extension ViewController {
    
    @IBAction func didOpen(_ sender: AnyObject) {
        guard let epub = Epub(rawValue: sender.tag) else {
            return
        }

        self.open(epub: epub)
    }
}
