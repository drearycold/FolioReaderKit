import XCTest
import FolioEPUBCore
@testable import FolioReaderKit

final class FolioReaderSearchResolverTests: XCTestCase {
    func testSearchIgnoresCaseAndDiacriticsAndUsesOriginalUTF16Offset() async {
        let html = "<html><head><title>cafe</title></head><body><script>cafe</script><p>xx CAFÉ and cafe\u{301}</p></body></html>"
        let resolver = makeResolver(pages: [html])

        let results = await resolver.search(FolioReaderSearchQuery(text: "cafe"))

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.map(\.page), [1, 1])
        XCTAssertEqual(Set(results.compactMap(\.cfi)).count, 2)
        XCTAssertTrue(results.allSatisfy { $0.context?.contains("CAFÉ") == true || $0.context?.contains("cafe") == true })
        XCTAssertTrue(results.first?.cfi?.contains(":3") == true)
    }

    func testSearchReturnsSpineOrderAndHonorsLimit() async {
        let resolver = makeResolver(pages: [
            "<html><body><p>term then term</p></body></html>",
            "<html><body><p>term on next page</p></body></html>"
        ])

        let results = await resolver.search(FolioReaderSearchQuery(text: "TERM", limit: 2))

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.map(\.page), [1, 1])
        XCTAssertEqual(results.map(\.text), ["TERM", "TERM"])
    }

    func testSearchStopsAtLimitWithinOnePageWithManyMatches() async {
        let resolver = makeResolver(pages: [
            "<html><body><p>\(String(repeating: "term ", count: 100))</p></body></html>"
        ])

        let results = await resolver.search(FolioReaderSearchQuery(text: "term", limit: 3))

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results.map(\.page), [1, 1, 1])
        XCTAssertEqual(Set(results.compactMap(\.cfi)).count, 3)
    }

    func testSearchTrimsLeadingAndTrailingWhitespaceBeforeMatching() async {
        let resolver = makeResolver(pages: [
            "<html><body><p>term in the body</p></body></html>"
        ])

        let results = await resolver.search(FolioReaderSearchQuery(text: "  term  "))

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.text, "term")
    }

    func testSearchSkipsEmptyQueriesAndNonBodyText() async {
        let resolver = makeResolver(pages: [
            "<html><head><title>term</title></head><body><style>term</style><p>other</p></body></html>"
        ])

        let emptyQueryResults = await resolver.search(FolioReaderSearchQuery(text: ""))
        let nonBodyResults = await resolver.search(FolioReaderSearchQuery(text: "term"))
        XCTAssertTrue(emptyQueryResults.isEmpty)
        XCTAssertTrue(nonBodyResults.isEmpty)
    }

    func testForwardAnchorIsExclusiveAndBackwardReturnsNearestMatchesInNaturalOrder() async {
        let resolver = makeResolver(pages: [
            "<html><body><p>term one term two</p></body></html>",
            "<html><body><p>term three term four</p></body></html>"
        ])

        let allResults = await resolver.search(FolioReaderSearchQuery(text: "term"))
        XCTAssertEqual(allResults.count, 4)
        guard let anchorCFI = allResults[1].cfi else {
            return XCTFail("Expected a CFI anchor")
        }

        let forward = await resolver.search(FolioReaderSearchQuery(
            text: "term",
            anchor: FolioReaderSearchAnchor(page: 1, cfi: anchorCFI),
            direction: .forward
        ))
        let backward = await resolver.search(FolioReaderSearchQuery(
            text: "term",
            anchor: FolioReaderSearchAnchor(page: 1, cfi: anchorCFI),
            direction: .backward
        ))

        XCTAssertEqual(forward, Array(allResults.dropFirst(2)))
        XCTAssertEqual(backward, [allResults[0]])
    }

    func testBackwardAnchorUsesNearestMatchesBeforeReturningNaturalOrderAndHonorsLimit() async {
        let resolver = makeResolver(pages: [
            "<html><body><p>term one term two term three term four</p></body></html>"
        ])
        let allResults = await resolver.search(FolioReaderSearchQuery(text: "term"))
        guard let anchorCFI = allResults.last?.cfi else {
            return XCTFail("Expected a CFI anchor")
        }

        let backward = await resolver.search(FolioReaderSearchQuery(
            text: "term",
            limit: 2,
            anchor: FolioReaderSearchAnchor(page: 1, cfi: anchorCFI),
            direction: .backward
        ))

        XCTAssertEqual(backward, Array(allResults[1...2]))
    }

    func testAnchorSearchWrapsAcrossPagesWithoutIncludingAnchor() async {
        let resolver = makeResolver(pages: [
            "<html><body><p>term on first</p></body></html>",
            "<html><body><p>term on second</p></body></html>",
            "<html><body><p>term on third</p></body></html>"
        ])
        let allResults = await resolver.search(FolioReaderSearchQuery(text: "term"))
        guard let anchorCFI = allResults[1].cfi else {
            return XCTFail("Expected a CFI anchor")
        }

        let forward = await resolver.search(FolioReaderSearchQuery(
            text: "term",
            limit: 3,
            anchor: FolioReaderSearchAnchor(page: 2, cfi: anchorCFI),
            direction: .forward
        ))
        let backward = await resolver.search(FolioReaderSearchQuery(
            text: "term",
            limit: 3,
            anchor: FolioReaderSearchAnchor(page: 2, cfi: anchorCFI),
            direction: .backward
        ))

        XCTAssertEqual(forward.map(\.page), [3])
        XCTAssertEqual(backward.map(\.page), [1])
    }

    func testBackwardAnchorInLargeTextNodeHonorsSmallLimit() async {
        let html = "<html><body><p>\(String(repeating: "term ", count: 2000))</p></body></html>"
        let resolver = makeResolver(pages: [html])
        let nearbyResults = await resolver.search(FolioReaderSearchQuery(text: "term", limit: 1001))
        guard let anchorCFI = nearbyResults[safe: 1000]?.cfi else {
            return XCTFail("Expected an anchor in the large text node")
        }
        let anchor = FolioReaderSearchAnchor(page: 1, cfi: anchorCFI)

        let results = await resolver.search(FolioReaderSearchQuery(
            text: "term",
            limit: 2,
            anchor: anchor,
            direction: .backward
        ))

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.map(\.cfi), [nearbyResults[998].cfi, nearbyResults[999].cfi])
    }

    private func makeResolver(pages: [String]) -> FolioReaderSearchResolver {
        let book = FRBook()
        book.spine.spineReferences = pages.enumerated().map { index, _ in
            let resource = FRResource()
            resource.href = "chapter\(index + 1).xhtml"
            return Spine(resource: resource)
        }
        return FolioReaderSearchResolver(book: book, documentProvider: { page in
            pages[safe: page - 1]
        })
    }
}
