import Foundation
import FolioEPUBCore
import SwiftSoup

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
    private let documentProvider: (Int) async -> String?

    public init(book: FRBook,
                currentLocation: @escaping LocationProvider = { nil },
                selectedTextLocation: @escaping LocationProvider = { nil }) {
        self.book = book
        self.currentLocationProvider = currentLocation
        self.selectedTextLocationProvider = selectedTextLocation
        self.documentProvider = { page in
            await FolioReaderReferenceResolver.loadDocument(book: book, page: page)
        }
    }

    init(book: FRBook,
         currentLocation: @escaping LocationProvider = { nil },
         selectedTextLocation: @escaping LocationProvider = { nil },
         documentProvider: @escaping (Int) async -> String?) {
        self.book = book
        self.currentLocationProvider = currentLocation
        self.selectedTextLocationProvider = selectedTextLocation
        self.documentProvider = documentProvider
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
        guard text.isEmpty == false, let html = await documentProvider(page) else { return [] }
        let href = book.spine.spineReferences[safe: page - 1]?.resource.href
        let matches = Self.resolve(text: text, in: html, page: page, href: href, tocPath: tocPathForPage(page))
        guard let boundaryCFI = beforeCFI else { return matches }
        return matches.filter { result in
            guard let cfi = result.cfi else { return true }
            return Self.compare(cfi: cfi, isBeforeOrEqualTo: boundaryCFI)
        }
    }

    static func resolve(text: String, in html: String, page: Int, href: String?, tocPath: [String]) -> [FolioReaderLocatorResult] {
        guard let document = try? SwiftSoup.parse(html),
              let _ = try? document.attr("CFI", "/\(page * 2)") else { return [] }
        tagCFI(to: document)

        let escapedText = NSRegularExpression.escapedPattern(for: text)
        guard let elements = try? document.getElementsMatchingOwnText(Pattern.compile(escapedText)) else { return [] }
        return elements.flatMap { element -> [FolioReaderLocatorResult] in
            guard let elementCFI = try? element.attr("CFI") else { return [] }
            let nodes = element.textNodes()
            let offsetByOne = nodes.first?.previousSibling() != nil
            return nodes.enumerated().flatMap { index, node -> [FolioReaderLocatorResult] in
                let ownText = node.getWholeText()
                guard ownText.contains(text) else { return [] }
                return ownText.ranges(of: text).map { range in
                    let contextStart = ownText.index(range.lowerBound, offsetBy: -30, limitedBy: ownText.startIndex) ?? ownText.startIndex
                    let contextEnd = ownText.index(range.upperBound, offsetBy: 70, limitedBy: ownText.endIndex) ?? ownText.endIndex
                    let prefix = contextStart > ownText.startIndex ? "..." : ""
                    let suffix = contextEnd < ownText.endIndex ? "..." : ""
                    let context = prefix + ownText[contextStart..<contextEnd] + suffix
                    let nodeCFI = "\(elementCFI)/\(index * 2 + 1 + (offsetByOne ? 2 : 0)):\(range.lowerBound.utf16Offset(in: ownText))"
                    return FolioReaderLocatorResult(page: page, href: href, cfi: "epubcfi(\(nodeCFI))",
                                                    text: text, context: String(context), tocPath: tocPath)
                }
            }
        }
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

    private static func compare(cfi: String, isBeforeOrEqualTo boundary: String) -> Bool {
        let numbers: (String) -> [Int] = { value in
            value.split(whereSeparator: { $0.isNumber == false }).compactMap { Int($0) }
        }
        return numbers(cfi).lexicographicallyPrecedes(numbers(boundary)) || numbers(cfi) == numbers(boundary)
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
        return FolioReaderReferenceResolver(book: center.book,
                                            currentLocation: location,
                                            selectedTextLocation: selection)
    }
}

private extension String {
    func ranges(of text: String) -> [Range<String.Index>] {
        var ranges = [Range<String.Index>]()
        var start = startIndex
        while start < endIndex, let range = range(of: text, range: start..<endIndex) {
            ranges.append(range)
            start = range.upperBound
        }
        return ranges
    }
}
