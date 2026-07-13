import Foundation
import FolioEPUBCore

public struct FolioReaderLocatorQuery: Codable, Hashable {
    public var text: String?
    public var cfi: String?
    public var page: Int?
    public var href: String?
    public var fragmentId: String?

    public init(text: String? = nil, cfi: String? = nil, page: Int? = nil,
                href: String? = nil, fragmentId: String? = nil) {
        self.text = text
        self.cfi = cfi
        self.page = page
        self.href = href
        self.fragmentId = fragmentId
    }
}

public struct FolioReaderLocatorResult: Codable, Hashable {
    public var page: Int
    public var href: String?
    public var cfi: String?
    public var fragmentId: String?
    public var text: String?
    public var context: String?
    public var tocPath: [String]
    public var chapterProgress: Double?

    public init(page: Int, href: String? = nil, cfi: String? = nil,
                fragmentId: String? = nil, text: String? = nil,
                context: String? = nil, tocPath: [String] = [],
                chapterProgress: Double? = nil) {
        self.page = page
        self.href = href
        self.cfi = cfi
        self.fragmentId = fragmentId
        self.text = text
        self.context = context
        self.tocPath = tocPath
        self.chapterProgress = chapterProgress
    }
}

public protocol FolioReaderReferenceResolving {
    func currentLocation() async -> FolioReaderLocatorResult?
    func selectedTextLocation() async -> FolioReaderLocatorResult?
    func reverseLookup(text: String, before query: FolioReaderLocatorQuery?) async -> [FolioReaderLocatorResult]
}

public final class FolioReaderReferenceResolver: FolioReaderReferenceResolving {
    public typealias LocationProvider = @MainActor () async -> FolioReaderLocatorResult?

    private let book: FRBook
    private let currentLocationProvider: LocationProvider
    private let selectedTextLocationProvider: LocationProvider
    private let textLocator: FolioReaderTextLocator

    public init(book: FRBook,
                currentLocation: @escaping LocationProvider = { nil },
                selectedTextLocation: @escaping LocationProvider = { nil }) {
        self.book = book
        self.currentLocationProvider = currentLocation
        self.selectedTextLocationProvider = selectedTextLocation
        self.textLocator = FolioReaderTextLocator(book: book)
    }

    init(book: FRBook,
         currentLocation: @escaping LocationProvider = { nil },
         selectedTextLocation: @escaping LocationProvider = { nil },
         documentProvider: @escaping (Int) async -> String?) {
        self.book = book
        self.currentLocationProvider = currentLocation
        self.selectedTextLocationProvider = selectedTextLocation
        self.textLocator = FolioReaderTextLocator(book: book, documentProvider: documentProvider)
    }

    init(book: FRBook,
         textLocator: FolioReaderTextLocator,
         currentLocation: @escaping LocationProvider = { nil },
         selectedTextLocation: @escaping LocationProvider = { nil }) {
        self.book = book
        self.currentLocationProvider = currentLocation
        self.selectedTextLocationProvider = selectedTextLocation
        self.textLocator = textLocator
    }

    public func currentLocation() async -> FolioReaderLocatorResult? {
        await currentLocationProvider()
    }

    public func selectedTextLocation() async -> FolioReaderLocatorResult? {
        await selectedTextLocationProvider()
    }

    public func reverseLookup(text: String, before query: FolioReaderLocatorQuery? = nil) async -> [FolioReaderLocatorResult] {
        guard text.isEmpty == false else { return [] }
        let lastPage = min(query?.page ?? book.spine.spineReferences.count, book.spine.spineReferences.count)
        guard lastPage > 0 else { return [] }

        var results = [FolioReaderLocatorResult]()
        for page in 1...lastPage {
            results.append(contentsOf: await reverseLookup(text: text, on: page,
                                                           beforeCFI: page == query?.page ? query?.cfi : nil))
        }
        return results
    }

    func reverseLookup(text: String, on page: Int, beforeCFI: String? = nil) async -> [FolioReaderLocatorResult] {
        return await textLocator.resolve(text: text, page: page, beforeCFI: beforeCFI)
    }

    static func resolve(text: String, in html: String, page: Int, href: String?, tocPath: [String]) -> [FolioReaderLocatorResult] {
        return FolioReaderTextLocator.resolve(text: text, in: html, page: page, href: href, tocPath: tocPath)
    }
}

public extension FolioReader {
    /// Creates a UI-independent resolver backed by the book currently open in this reader.
    /// The returned resolver does not navigate or modify the reader's temporary reference state.
    func makeReferenceResolver() -> FolioReaderReferenceResolving? {
        guard let center = readerCenter else { return nil }
        let location: FolioReaderReferenceResolver.LocationProvider = { [weak center] in
            guard let center = center else { return nil }
            let page = center.currentPageNumber
            guard page > 0 else { return nil }
            let position = center.currentWebViewScrollPositions[page - 1]
            let href = center.book.spine.spineReferences[safe: page - 1]?.resource.href
            let tocPath = center.getChapterNames(pageNumber: page).compactMap(\.title)
            return FolioReaderLocatorResult(page: page, href: href, cfi: position?.cfi,
                                            tocPath: tocPath, chapterProgress: position?.chapterProgress)
        }
        let selection: FolioReaderReferenceResolver.LocationProvider = { [weak center] in
            guard let center = center, let text = center.tempRefText else { return nil }
            let page = center.currentPageNumber
            let href = center.book.spine.spineReferences[safe: page - 1]?.resource.href
            let cfi = center.tempRefCFI.map { "epubcfi(\(page * 2)/2\($0))" }
            let tocPath = center.getChapterNames(pageNumber: page).compactMap(\.title)
            return FolioReaderLocatorResult(page: page, href: href, cfi: cfi,
                                            text: text, tocPath: tocPath)
        }
        return FolioReaderReferenceResolver(book: center.book, textLocator: center.textLocator,
                                            currentLocation: location,
                                            selectedTextLocation: selection)
    }
}
