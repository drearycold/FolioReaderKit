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
    var bookmarkProvider: FolioReaderBookmarkProvider?
    var readPositionProvider: FolioReaderReadPositionProvider?

    /// Bookmarks and reading positions, kept in memory for as long as the app runs, one store per book
    /// (keyed like the reader's `bookId`: the file name without its extension). The bookmark protocol
    /// removes and updates bookmarks by position alone, so each book needs its own store.
    private var bookmarkProviders = [String: FolioReaderInMemoryBookmarkProvider]()
    private var readPositionProviders = [String: FolioReaderInMemoryReadPositionProvider]()

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
        // Scope persisted settings to this book's identifier before the reader starts reading them.
        self.preferenceProvider = FolioReaderUserDefaultsPreferenceProvider(
            folioReader, identifier: readerConfiguration.identifier)

        let bookId = URL(fileURLWithPath: bookPath).deletingPathExtension().lastPathComponent
        let bookmarkProvider = bookmarkProviders[bookId] ?? FolioReaderInMemoryBookmarkProvider()
        bookmarkProviders[bookId] = bookmarkProvider
        self.bookmarkProvider = bookmarkProvider
        let readPositionProvider = readPositionProviders[bookId] ?? FolioReaderInMemoryReadPositionProvider()
        readPositionProviders[bookId] = readPositionProvider
        self.readPositionProvider = readPositionProvider
        // The reader opens at `savedPositionForCurrentBook`; it doesn't look the position up itself.
        readerConfiguration.savedPositionForCurrentBook = readPositionProvider.folioReaderReadPosition(folioReader, bookId: bookId)

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

    func folioReaderBookmarkProvider(_ folioReader: FolioReader) -> FolioReaderBookmarkProvider {
        if let bookmarkProvider = bookmarkProvider {
            return bookmarkProvider
        } else {
            let bookmarkProvider = FolioReaderInMemoryBookmarkProvider()
            self.bookmarkProvider = bookmarkProvider
            return bookmarkProvider
        }
    }

    func folioReaderReadPositionProvider(_ folioReader: FolioReader) -> FolioReaderReadPositionProvider {
        if let readPositionProvider = readPositionProvider {
            return readPositionProvider
        } else {
            let readPositionProvider = FolioReaderInMemoryReadPositionProvider()
            self.readPositionProvider = readPositionProvider
            return readPositionProvider
        }
    }
}

class FolioReaderUserDefaultsPreferenceProvider: FolioReaderDummyPreferenceProvider {

    /// Namespace for keys stored in `UserDefaults`. Keys come from `ReaderPreferenceKey.rawKey`.
    internal let keyPrefix = "com.folioreader."

    /// Backing store. Scoped by the reader config's identifier, so each book keeps its own settings.
    fileprivate let defaults: FolioReaderUserDefaults

    init(_ folioReader: FolioReader, identifier: String?) {
        self.defaults = FolioReaderUserDefaults(withIdentifier: identifier)
        super.init(folioReader)
    }

    override convenience init(_ folioReader: FolioReader) {
        self.init(folioReader, identifier: folioReader.readerConfig?.identifier)
    }

    private func storageKey(_ key: String) -> String {
        return keyPrefix + key
    }

    // Defaults are supplied by FolioReaderKit per key; only fall back to them when nothing is stored.

    override func preference(stringFor key: String, default defaultValue: String) -> String {
        return defaults.value(forKey: storageKey(key)) as? String ?? defaultValue
    }
    override func preference(setString value: String, for key: String) {
        defaults.set(value, forKey: storageKey(key))
    }

    override func preference(intFor key: String, default defaultValue: Int) -> Int {
        return defaults.value(forKey: storageKey(key)) as? Int ?? defaultValue
    }
    override func preference(setInt value: Int, for key: String) {
        defaults.set(value, forKey: storageKey(key))
    }

    override func preference(boolFor key: String, default defaultValue: Bool) -> Bool {
        return defaults.value(forKey: storageKey(key)) as? Bool ?? defaultValue
    }
    override func preference(setBool value: Bool, for key: String) {
        defaults.set(value, forKey: storageKey(key))
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

/// Bookmarks for one book, keyed by position (a CFI).
public class FolioReaderInMemoryBookmarkProvider: NSObject, FolioReaderBookmarkProvider {
    private var bookmarks = [String: FolioReaderBookmark]()

    public func folioReaderBookmark(_ folioReader: FolioReader, added bookmark: FolioReaderBookmark, completion: Completion?) {
        guard let pos = bookmark.pos else {
            completion?(FolioReaderBookmarkError.emptyError("Bookmark without a position") as NSError)
            return
        }
        if let existing = bookmarks[pos] {
            completion?(FolioReaderBookmarkError.duplicateError(existing.title) as NSError)
            return
        }
        bookmarks[pos] = bookmark
        completion?(nil)
    }

    public func folioReaderBookmark(_ folioReader: FolioReader, removed bookmarkPos: String) {
        bookmarks.removeValue(forKey: bookmarkPos)
    }

    public func folioReaderBookmark(_ folioReader: FolioReader, updated bookmarkPos: String, title: String) {
        bookmarks[bookmarkPos]?.title = title
    }

    public func folioReaderBookmark(_ folioReader: FolioReader, getBy bookmarkPos: String) -> FolioReaderBookmark? {
        return bookmarks[bookmarkPos]
    }

    public func folioReaderBookmark(_ folioReader: FolioReader, allByBookId bookId: String, andPage page: NSNumber?) -> [FolioReaderBookmark] {
        return bookmarks.values.filter { $0.bookId == bookId && (page == nil || $0.page == page?.intValue) }.sorted()
    }

    public func folioReaderBookmark(_ folioReader: FolioReader) -> [FolioReaderBookmark] {
        return bookmarks.values.sorted()
    }
}

/// Reading positions, one per device for each book, as a sync service would keep them. The reader
/// marks the position it opened at, and each later save, with `takePrecedence`. It saves from a
/// background queue and reads on the main thread, hence the lock.
public class FolioReaderInMemoryReadPositionProvider: NSObject, FolioReaderReadPositionProvider {
    private var positions = [String: [String: FolioReaderReadPosition]]()   // bookId → deviceId → position
    private let lock = NSLock()

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    public func folioReaderReadPosition(_ folioReader: FolioReader, bookId: String) -> FolioReaderReadPosition? {
        return locked {
            positions[bookId]?.values.max {
                ($0.takePrecedence ? 1 : 0, $0.epoch) < ($1.takePrecedence ? 1 : 0, $1.epoch)
            }
        }
    }

    public func folioReaderReadPosition(_ folioReader: FolioReader, bookId: String, by rootPageNumber: Int) -> FolioReaderReadPosition? {
        let structuralStyle = folioReader.structuralStyle
        let trackingStyle = folioReader.structuralTrackingTocLevel
        return locked {
            positions[bookId]?.values.first {
                $0.structuralStyle == structuralStyle
                    && $0.positionTrackingStyle == trackingStyle
                    && $0.structuralRootPageNumber == rootPageNumber
            }
        }
    }

    public func folioReaderReadPosition(_ folioReader: FolioReader, bookId: String, set readPosition: FolioReaderReadPosition, completion: Completion?) {
        locked { positions[bookId, default: [:]][readPosition.deviceId] = readPosition }
        completion?(nil)
    }

    public func folioReaderReadPosition(_ folioReader: FolioReader, bookId: String, remove readPosition: FolioReaderReadPosition) {
        locked { _ = positions[bookId]?.removeValue(forKey: readPosition.deviceId) }
    }

    public func folioReaderReadPosition(_ folioReader: FolioReader, bookId: String, getById deviceId: String) -> [FolioReaderReadPosition] {
        return locked { positions[bookId]?[deviceId].map { [$0] } ?? [] }
    }

    public func folioReaderReadPosition(_ folioReader: FolioReader, allByBookId bookId: String) -> [FolioReaderReadPosition] {
        return locked { positions[bookId].map { Array($0.values) } ?? [] }
    }

    public func folioReaderReadPosition(_ folioReader: FolioReader) -> [FolioReaderReadPosition] {
        return locked { positions.values.flatMap { $0.values } }
    }

    public func folioReaderPositionHistory(_ folioReader: FolioReader, bookId: String) -> [FolioReaderReadPositionHistory] {
        return []
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
