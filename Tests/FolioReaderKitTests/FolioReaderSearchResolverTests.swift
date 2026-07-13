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
