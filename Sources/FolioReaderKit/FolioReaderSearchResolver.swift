import Foundation
import FolioEPUBCore

public struct FolioReaderSearchQuery: Codable, Hashable {
    public var text: String
    public var limit: Int?

    public init(text: String, limit: Int? = nil) {
        self.text = text
        self.limit = limit
    }
}

public protocol FolioReaderSearching {
    func search(_ query: FolioReaderSearchQuery) async -> [FolioReaderLocatorResult]
}

public final class FolioReaderSearchResolver: FolioReaderSearching {
    private let book: FRBook
    private let textLocator: FolioReaderTextLocator

    public init(book: FRBook) {
        self.book = book
        self.textLocator = FolioReaderTextLocator(book: book)
    }

    init(book: FRBook, textLocator: FolioReaderTextLocator) {
        self.book = book
        self.textLocator = textLocator
    }

    init(book: FRBook, documentProvider: @escaping (Int) async -> String?) {
        self.book = book
        self.textLocator = FolioReaderTextLocator(book: book, documentProvider: documentProvider)
    }

    public func search(_ query: FolioReaderSearchQuery) async -> [FolioReaderLocatorResult] {
        let normalizedQuery = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedQuery.isEmpty == false,
              book.spine.spineReferences.isEmpty == false else {
            return []
        }
        if let limit = query.limit, limit <= 0 {
            return []
        }

        var results = [FolioReaderLocatorResult]()
        for page in 1...book.spine.spineReferences.count {
            if Task.isCancelled { return [] }
            let remainingLimit = query.limit.map { $0 - results.count }
            if remainingLimit == 0 { return results }
            let pageResults = await textLocator.resolve(text: normalizedQuery, page: page, limit: remainingLimit)
            if Task.isCancelled { return [] }
            results.append(contentsOf: pageResults)
            if let limit = query.limit, results.count >= limit {
                return Array(results.prefix(limit))
            }
            await Task.yield()
        }
        return results
    }
}

public extension FolioReader {
    /// Creates a UI-independent search resolver backed by the book currently open in this reader.
    func makeSearchResolver() -> FolioReaderSearching? {
        guard let center = readerCenter else { return nil }
        return FolioReaderSearchResolver(book: center.book, textLocator: center.textLocator)
    }
}
