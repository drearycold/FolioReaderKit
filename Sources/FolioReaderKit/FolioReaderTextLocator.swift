import Foundation
import FolioEPUBCore
import SwiftSoup

/// Shared EPUB document and text-location infrastructure used by references and search.
final class FolioReaderTextLocator {
    typealias DocumentProvider = (Int) async -> String?

    private let book: FRBook
    private let documentProvider: DocumentProvider
    private var documentCache = [Int: Document]()
    private let cacheLock = NSLock()

    init(book: FRBook) {
        self.book = book
        self.documentProvider = { page in
            await FolioReaderTextLocator.loadDocument(book: book, page: page)
        }
    }

    init(book: FRBook, documentProvider: @escaping DocumentProvider) {
        self.book = book
        self.documentProvider = documentProvider
    }

    func resolve(text: String,
                 page: Int,
                 beforeCFI: String? = nil,
                 afterCFI: String? = nil,
                 beforeCFIExclusive: String? = nil,
                 limit: Int? = nil,
                 direction: FolioReaderSearchDirection = .forward) async -> [FolioReaderLocatorResult] {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              limit.map({ $0 > 0 }) ?? true,
              let document = await document(for: page) else {
            return []
        }

        let href = book.spine.spineReferences[safe: page - 1]?.resource.href
        let matches = Self.resolve(text: text,
                                   in: document,
                                   page: page,
                                   href: href,
                                   tocPath: tocPathForPage(page),
                                   beforeCFI: beforeCFI,
                                   afterCFI: afterCFI,
                                   beforeCFIExclusive: beforeCFIExclusive,
                                   limit: limit,
                                   direction: direction)
        return matches
    }

    static func resolve(text: String, in html: String, page: Int, href: String?, tocPath: [String], limit: Int? = nil) -> [FolioReaderLocatorResult] {
        guard limit.map({ $0 > 0 }) ?? true else { return [] }
        guard let document = try? SwiftSoup.parse(html) else { return [] }
        guard (try? document.attr("CFI", "/\(page * 2)")) != nil else { return [] }
        tagCFI(to: document)
        return resolve(text: text, in: document, page: page, href: href, tocPath: tocPath, limit: limit)
    }

    static func matchingRanges(of query: String, in text: String, limit: Int? = nil) -> [Range<String.Index>] {
        guard query.isEmpty == false,
              text.isEmpty == false,
              limit.map({ $0 > 0 }) ?? true else { return [] }

        var ranges = [Range<String.Index>]()
        _ = forEachMatchingRange(of: query, in: text, direction: .forward) { range in
            ranges.append(range)
            return limit.map { ranges.count < $0 } ?? true
        }
        return ranges
    }

    @discardableResult
    private static func forEachMatchingRange(of query: String,
                                             in text: String,
                                             direction: FolioReaderSearchDirection,
                                             visit: (Range<String.Index>) -> Bool) -> Bool {
        guard query.isEmpty == false, text.isEmpty == false else { return true }

        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        switch direction {
        case .forward:
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  Task.isCancelled == false,
                  let range = text.range(of: query,
                                         options: options,
                                         range: searchStart..<text.endIndex,
                                         locale: nil) {
                guard visit(range) else { return false }
                if range.upperBound == searchStart {
                    guard searchStart < text.endIndex else { break }
                    searchStart = text.index(after: searchStart)
                } else {
                    searchStart = range.upperBound
                }
            }
        case .backward:
            var searchEnd = text.endIndex
            let backwardOptions = options.union(.backwards)
            while text.startIndex < searchEnd,
                  Task.isCancelled == false,
                  let range = text.range(of: query,
                                         options: backwardOptions,
                                         range: text.startIndex..<searchEnd,
                                         locale: nil) {
                guard visit(range) else { return false }
                guard range.lowerBound < searchEnd else { break }
                searchEnd = range.lowerBound
            }
        }
        return Task.isCancelled == false
    }

    private func document(for page: Int) async -> Document? {
        if let cachedDocument = cachedDocument(for: page) {
            return cachedDocument
        }

        guard let html = await documentProvider(page),
              let document = try? SwiftSoup.parse(html),
              (try? document.attr("CFI", "/\(page * 2)")) != nil else {
            return nil
        }

        Self.tagCFI(to: document)
        store(document: document, for: page)
        return document
    }

    private func cachedDocument(for page: Int) -> Document? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return documentCache[page]
    }

    private func store(document: Document, for page: Int) {
        cacheLock.lock()
        documentCache[page] = document
        cacheLock.unlock()
    }

    private static func resolve(text: String,
                                in document: Document,
                                page: Int,
                                href: String?,
                                tocPath: [String],
                                beforeCFI: String? = nil,
                                afterCFI: String? = nil,
                                beforeCFIExclusive: String? = nil,
                                limit: Int? = nil,
                                direction: FolioReaderSearchDirection = .forward) -> [FolioReaderLocatorResult] {
        guard let body = document.body() else { return [] }

        var results = [FolioReaderLocatorResult]()
        let elements = (try? body.getAllElements()) ?? Elements()
        let elementsToVisit = direction == .forward ? Array(elements) : Array(elements.reversed())
        for element in elementsToVisit {
            if Task.isCancelled { return [] }
            guard isBodyTextElement(element) else { continue }

            guard let elementCFI = try? element.attr("CFI") else { continue }
            let nodes = element.textNodes()
            let offsetByOne = nodes.first?.previousSibling() != nil
            let indexedNodes = nodes.enumerated().map { $0 }
            let nodesToVisit = direction == .forward ? indexedNodes : Array(indexedNodes.reversed())
            for (index, node) in nodesToVisit {
                if Task.isCancelled { return [] }
                let ownText = node.getWholeText()
                if let limit, results.count >= limit { return results }
                _ = forEachMatchingRange(of: text, in: ownText, direction: direction) { range in
                    if Task.isCancelled { return false }
                    let contextStart = ownText.index(range.lowerBound, offsetBy: -30, limitedBy: ownText.startIndex) ?? ownText.startIndex
                    let contextEnd = ownText.index(range.upperBound, offsetBy: 70, limitedBy: ownText.endIndex) ?? ownText.endIndex
                    let prefix = contextStart > ownText.startIndex ? "..." : ""
                    let suffix = contextEnd < ownText.endIndex ? "..." : ""
                    let context = prefix + ownText[contextStart..<contextEnd] + suffix
                    let nodeCFI = "\(elementCFI)/\(index * 2 + 1 + (offsetByOne ? 2 : 0)):\(range.lowerBound.utf16Offset(in: ownText))"
                    let cfi = "epubcfi(\(nodeCFI))"
                    if let beforeCFI, !compare(cfi: cfi, isBeforeOrEqualTo: beforeCFI) {
                        return true
                    }
                    if let beforeCFIExclusive, !compare(cfi: cfi, isStrictlyBefore: beforeCFIExclusive) {
                        return true
                    }
                    if let afterCFI, !compare(cfi: cfi, isStrictlyAfter: afterCFI) {
                        return true
                    }
                    results.append(FolioReaderLocatorResult(
                        page: page,
                        href: href,
                        cfi: cfi,
                        text: text,
                        context: String(context),
                        tocPath: tocPath
                    ))
                    if let limit = limit, results.count >= limit {
                        return false
                    }
                    return true
                }
                if Task.isCancelled { return [] }
                if let limit, results.count >= limit { return results }
            }

        }
        return results
    }

    private static func isBodyTextElement(_ element: Element) -> Bool {
        var current: Element? = element
        while let node = current {
            let tagName = node.tagName().lowercased()
            if tagName == "script" || tagName == "style" || tagName == "noscript" {
                return false
            }
            current = node.parent()
        }
        return true
    }

    private func tocPathForPage(_ page: Int) -> [String] {
        guard let resource = book.spine.spineReferences[safe: page - 1]?.resource else { return [] }
        return (book.resourceTocMap[resource] ?? []).compactMap { reference in
            var titles = [String]()
            var current: FRTocReference? = reference
            while let item = current {
                titles.insert(item.title, at: 0)
                current = item.parent
            }
            return titles
        }.max(by: { $0.count < $1.count }) ?? []
    }

    private static func loadDocument(book: FRBook, page: Int) async -> String? {
        guard let archive = await book.getThreadEpubArchive(),
              let spine = book.spine.spineReferences[safe: page - 1],
              let opf = book.opfResource else { return nil }
        let opfURL = URL(fileURLWithPath: opf.href)
        let spineURL = URL(fileURLWithPath: spine.resource.href, relativeTo: opfURL)
        let path = spineURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let entry = book.archiveEntriesCache[path] else { return nil }
        let accumulator = DataAccumulator()
        guard (try? await archive.extract(entry, consumer: { data in
            accumulator.append(data)
        })) != nil else { return nil }
        return String(data: accumulator.result, encoding: .utf8)
    }

    private static func tagCFI(to element: Element) {
        guard let cfi = try? element.attr("CFI") else { return }
        for (index, child) in element.children().enumerated() {
            guard (try? child.attr("CFI", "\(cfi)/\((index + 1) * 2)")) != nil else { continue }
            tagCFI(to: child)
        }
    }

    static func compare(cfi: String, isBeforeOrEqualTo boundary: String) -> Bool {
        let numbers: (String) -> [Int] = { value in
            value.split(whereSeparator: { $0.isNumber == false }).compactMap { Int($0) }
        }
        return numbers(cfi).lexicographicallyPrecedes(numbers(boundary)) || numbers(cfi) == numbers(boundary)
    }

    static func compare(cfi: String, isStrictlyBefore boundary: String) -> Bool {
        compare(cfi: cfi, isBeforeOrEqualTo: boundary) && compare(cfi: boundary, isBeforeOrEqualTo: cfi) == false
    }

    static func compare(cfi: String, isStrictlyAfter boundary: String) -> Bool {
        compare(cfi: boundary, isStrictlyBefore: cfi)
    }
}
