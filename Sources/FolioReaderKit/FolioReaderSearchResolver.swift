import Foundation
import FolioEPUBCore

public struct FolioReaderSearchQuery: Codable, Hashable {
    public var text: String
    public var limit: Int?
    /// An optional page/CFI position. `FolioReaderLocatorQuery` is reused here
    /// so callers can pass the same locator value used by the reference API.
    public var anchor: FolioReaderLocatorQuery?
    public var direction: FolioReaderSearchDirection

    public init(text: String,
                limit: Int? = nil,
                anchor: FolioReaderLocatorQuery? = nil,
                direction: FolioReaderSearchDirection = .forward) {
        self.text = text
        self.limit = limit
        self.anchor = anchor
        self.direction = direction
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case limit
        case anchor
        case direction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        limit = try container.decodeIfPresent(Int.self, forKey: .limit)
        anchor = try container.decodeIfPresent(FolioReaderLocatorQuery.self, forKey: .anchor)
        direction = try container.decodeIfPresent(FolioReaderSearchDirection.self, forKey: .direction) ?? .forward
    }
}

public typealias FolioReaderSearchAnchor = FolioReaderLocatorQuery

public extension FolioReaderLocatorQuery {
    init(page: Int, cfi: String? = nil) {
        self.init(text: nil, cfi: cfi, page: page)
    }
}

public enum FolioReaderSearchDirection: String, Codable, Hashable {
    case forward
    case backward
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

        switch query.direction {
        case .forward:
            return await searchForward(normalizedQuery: normalizedQuery,
                                       limit: query.limit,
                                       anchor: query.anchor)
        case .backward:
            return await searchBackward(normalizedQuery: normalizedQuery,
                                        limit: query.limit,
                                        anchor: query.anchor)
        }
    }

    private func searchForward(normalizedQuery: String,
                               limit: Int?,
                               anchor: FolioReaderLocatorQuery?) async -> [FolioReaderLocatorResult] {
        let pageCount = book.spine.spineReferences.count
        let firstPage = max(1, min(anchor?.page ?? 1, pageCount))
        var results = [FolioReaderLocatorResult]()

        for page in firstPage...pageCount {
            if Task.isCancelled { return [] }
            let remainingLimit = limit.map { $0 - results.count }
            if remainingLimit == 0 { return results }
            let pageAnchor = page == firstPage ? anchor?.cfi : nil
            let pageResults = await textLocator.resolve(text: normalizedQuery,
                                                        page: page,
                                                        afterCFI: pageAnchor,
                                                        limit: remainingLimit)
            if Task.isCancelled { return [] }
            results.append(contentsOf: pageResults)
            if let limit = limit, results.count >= limit {
                return Array(results.prefix(limit))
            }
            await Task.yield()
        }
        return results
    }

    private func searchBackward(normalizedQuery: String,
                                limit: Int?,
                                anchor: FolioReaderLocatorQuery?) async -> [FolioReaderLocatorResult] {
        let pageCount = book.spine.spineReferences.count
        let lastPage = max(1, min(anchor?.page ?? pageCount, pageCount))
        var nearestFirstResults = [FolioReaderLocatorResult]()

        for page in stride(from: lastPage, through: 1, by: -1) {
            if Task.isCancelled { return [] }
            let remainingLimit = limit.map { $0 - nearestFirstResults.count }
            if remainingLimit == 0 { break }
            let pageAnchor = page == lastPage ? anchor?.cfi : nil
            let pageResults = await textLocator.resolve(text: normalizedQuery,
                                                        page: page,
                                                        beforeCFIExclusive: pageAnchor,
                                                        limit: remainingLimit,
                                                        direction: .backward)
            if Task.isCancelled { return [] }
            nearestFirstResults.append(contentsOf: pageResults)
            if let limit = limit, nearestFirstResults.count >= limit { break }
            await Task.yield()
        }

        return Array(nearestFirstResults.reversed())
    }
}

public extension FolioReader {
    /// Creates a UI-independent search resolver backed by the book currently open in this reader.
    func makeSearchResolver() -> FolioReaderSearching? {
        guard let center = readerCenter else { return nil }
        return FolioReaderSearchResolver(book: center.book, textLocator: center.textLocator)
    }
}
