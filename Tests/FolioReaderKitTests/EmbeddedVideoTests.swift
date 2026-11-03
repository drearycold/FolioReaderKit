import XCTest
import WebKit
import FolioEPUBCore
import ReadiumGCDWebServer
import ReadiumZIPFoundation
@testable import FolioReaderKit

@MainActor
final class EmbeddedVideoTests: XCTestCase {
    private var sampleURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Example/Shared/Sample eBooks/Embedded Video.epub")
    }

    private func makeServer() async throws -> (FolioReaderContainer, EpubResourceServer) {
        let archive = try await Archive(url: sampleURL, accessMode: .read)
        let book = try await FREpubParserArchive(book: FRBook(), archive: archive).readEpub(epubPath: sampleURL.path)
        let webServer = ReadiumGCDWebServer()
        let container = FolioReaderContainer(withConfig: FolioReaderConfig(), folioReader: FolioReader(), epubPath: "", webServer: webServer)
        container.book = book
        let server = EpubResourceServer(webServer: webServer, container: container)
        server.start()
        return (container, server)
    }

    private func request(_ server: EpubResourceServer, path: String = "Video/demo.mp4",
                         range: String? = nil, ifRange: String? = nil, method: String = "GET") async throws -> (Data, HTTPURLResponse) {
        let url = URL(string: "http://localhost:\(server.port)/sample/EPUB/\(path)")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = method
        request.setValue(range, forHTTPHeaderField: "Range")
        request.setValue(ifRange, forHTTPHeaderField: "If-Range")
        return try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (data ?? Data(), response as! HTTPURLResponse)) }
            }.resume()
        }
    }

    func testRangeSyntax() {
        XCTAssertEqual(EpubByteRange.parse(nil, length: 10), .full)
        XCTAssertEqual(EpubByteRange.parse("bytes=2-4", length: 10), .partial(2..<5))
        XCTAssertEqual(EpubByteRange.parse("bytes=8-100", length: 10), .partial(8..<10))
        XCTAssertEqual(EpubByteRange.parse("bytes=3-", length: 10), .partial(3..<10))
        XCTAssertEqual(EpubByteRange.parse("bytes=-3", length: 10), .partial(7..<10))
        XCTAssertEqual(EpubByteRange.parse("bytes=-20", length: 10), .partial(0..<10))
        for header in ["bytes=-0", "bytes=10-", "bytes=99-100"] {
            XCTAssertEqual(EpubByteRange.parse(header, length: 10), .unsatisfiable)
        }
        for header in ["bytes=", "bytes=5-2", "bytes=0-1,3-4", "items=0-1", "bytes=+1-2", "bytes=0-x", "bytes=0-18446744073709551616"] {
            XCTAssertEqual(EpubByteRange.parse(header, length: 10), .full, header)
        }
        XCTAssertEqual(EpubByteRange.parse("bytes=0-0", length: 0), .unsatisfiable)
        XCTAssertEqual(EpubByteRange.parse("bytes=-1", length: 0), .unsatisfiable)
    }

    func testHTTPRangesForStoredAndDeflatedVideo() async throws {
        let (container, server) = try await makeServer()
        defer { server.stop(); withExtendedLifetime(container) {} }
        XCTAssertEqual(container.book.resources.resources["Video/demo.mp4"]?.mediaType?.name, "video/mp4")
        XCTAssertEqual(MediaType.mp4.name, "audio/mp4")
        for path in ["Video/demo.mp4", "Video/demo-deflated.mp4"] {
            let (full, response) = try await request(server, path: path)
            XCTAssertEqual(response.statusCode, 200)
            XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Type"), "video/mp4")
            XCTAssertEqual(response.value(forHTTPHeaderField: "Content-Length"), "\(full.count)")
            XCTAssertEqual(response.value(forHTTPHeaderField: "Accept-Ranges"), "bytes")
            XCTAssertNil(response.value(forHTTPHeaderField: "Transfer-Encoding"))
            XCTAssertGreaterThan(full.count, 1000)
            let length = full.count
            for (header, bounds) in [("bytes=0-1", 0..<2), ("bytes=100-199", 100..<200),
                                      ("bytes=\(length - 20)-", (length - 20)..<length),
                                      ("bytes=-30", (length - 30)..<length),
                                      ("bytes=\(length - 2)-\(length + 100)", (length - 2)..<length)] {
                let (part, partial) = try await request(server, path: path, range: header)
                XCTAssertEqual(partial.statusCode, 206, header)
                XCTAssertEqual(partial.value(forHTTPHeaderField: "Content-Range"), "bytes \(bounds.lowerBound)-\(bounds.upperBound - 1)/\(length)")
                XCTAssertEqual(partial.value(forHTTPHeaderField: "Content-Length"), "\(bounds.count)")
                XCTAssertEqual(part, full.subdata(in: bounds))
            }
            for header in ["bytes=0-1,3-4", "bytes=oops", "other=0-1"] {
                let (body, ignored) = try await request(server, path: path, range: header)
                XCTAssertEqual(ignored.statusCode, 200)
                XCTAssertEqual(body, full)
            }
            let (_, invalid) = try await request(server, path: path, range: "bytes=\(length)-")
            XCTAssertEqual(invalid.statusCode, 416)
            XCTAssertEqual(invalid.value(forHTTPHeaderField: "Content-Range"), "bytes */\(length)")
            let lastModified = try XCTUnwrap(response.value(forHTTPHeaderField: "Last-Modified"))
            let (matched, match) = try await request(server, path: path, range: "bytes=0-1", ifRange: lastModified)
            XCTAssertEqual(match.statusCode, 206)
            XCTAssertEqual(matched, full.prefix(2))
            let (staleBody, stale) = try await request(server, path: path, range: "bytes=0-1", ifRange: "Mon, 01 Jan 2001 00:00:00 GMT")
            XCTAssertEqual(stale.statusCode, 200)
            XCTAssertEqual(staleBody, full)
            let (body, head) = try await request(server, path: path, method: "HEAD")
            XCTAssertTrue(body.isEmpty)
            XCTAssertEqual(head.value(forHTTPHeaderField: "Content-Length"), "\(length)")
        }
    }

    func testReadersHaveIndependentVideoServersAndSessionLifetime() async throws {
        let (first, server) = try await makeServer()
        let (second, other) = try await makeServer()
        defer { server.stop(); other.stop(); withExtendedLifetime((first, second)) {} }
        XCTAssertNotEqual(server.port, other.port)
        first.viewWillDisappear(false)
        first.viewDidDisappear(false)
        let (_, stillRunning) = try await request(server, range: "bytes=0-1")
        XCTAssertEqual(stillRunning.statusCode, 206)
        server.stop()
        let (_, unaffected) = try await request(other, range: "bytes=0-1")
        XCTAssertEqual(unaffected.statusCode, 206)
    }

    func testChannelBackpressureAndCancellation() async throws {
        let channel = ZipEntryChannel()
        let producer = Task {
            try await channel.send(Data([1]))
            try await channel.send(Data([2]))
        }
        for _ in 0..<100 {
            if await channel.bufferedChunkCount == 1 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let queued = await channel.bufferedChunkCount
        XCTAssertEqual(queued, 1)
        let first = try await channel.next()
        XCTAssertEqual(first, Data([1]))
        await channel.finish(error: CancellationError())
        do { try await producer.value; XCTFail("Producer must be cancelled") } catch is CancellationError {} catch { XCTFail("\(error)") }
        do { _ = try await channel.next(); XCTFail("Cancellation must reach reader") } catch is CancellationError {} catch { XCTFail("\(error)") }
    }

    func testClosingResponseCancelsExtraction() async throws {
        let archive = try await Archive(url: sampleURL, accessMode: .read)
        let entries = try await archive.entries()
        let entry = try XCTUnwrap(entries.first { $0.path == "EPUB/Video/demo.mp4" })
        let response = ZipEntryResponse(archive: archive, entry: entry, contentType: "video/mp4", range: nil)
        let stream = response.stream
        _ = try await stream.channel.next()
        response.close()
        await stream.waitForCompletion()
        do { _ = try await stream.channel.next(); XCTFail("Closed stream must fail") } catch is CancellationError {} catch { XCTFail("\(error)") }
    }

    func testClosingDeflateRangeStopsBeforeReadingTheRestOfItsPrefix() async throws {
        let prefixRead = expectation(description: "first compressed prefix read")
        let gate = PrefixReadGate { prefixRead.fulfill() }
        let source = GatedZIPSource(data: try Data(contentsOf: sampleURL), gate: gate)
        let archive = try await Archive(url: nil, dataSource: source)
        let entries = try await archive.entries()
        let entry = try XCTUnwrap(entries.first { $0.path == "EPUB/Video/demo-deflated.mp4" })
        XCTAssertGreaterThan(entry.compressedSize, 2 * 64 * 1024)
        await gate.arm()
        let response = ZipEntryResponse(archive: archive, entry: entry, contentType: "video/mp4",
                                        range: (entry.uncompressedSize - 8)..<entry.uncompressedSize)
        await fulfillment(of: [prefixRead], timeout: 5)
        // The first compressed block is held before inflation, well before the requested range.
        response.close()
        await gate.release()
        await response.stream.waitForCompletion()
        let reads = await gate.blockReads
        XCTAssertEqual(reads, 1, "Cancelled prefix inflation must not fetch another compressed block")
        do {
            _ = try await response.stream.channel.next()
            XCTFail("Closing a prefix read must cancel the response")
        } catch is CancellationError {} catch { XCTFail("\(error)") }
    }

    func testCorruptZIPFailsInsteadOfReturningEOF() async throws {
        var data = try Data(contentsOf: sampleURL)
        let name = Data("EPUB/Video/demo-deflated.mp4".utf8)
        let nameRange = try XCTUnwrap(data.range(of: name))
        let header = nameRange.lowerBound - 30
        let extraLength = Int(data[header + 28]) + Int(data[header + 29]) * 256
        let start = nameRange.upperBound + extraLength
        data.replaceSubrange(start..<(start + 64), with: Data(repeating: 0xff, count: 64))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = try await Archive(url: url, accessMode: .read)
        let entries = try await archive.entries()
        let entry = try XCTUnwrap(entries.first { $0.path == "EPUB/Video/demo-deflated.mp4" })
        for range in [nil, 0..<UInt64(100)] as [Range<UInt64>?] {
            let stream = ZipEntryStream(archive: archive, entry: entry, range: range)
            defer { stream.cancel() }
            do {
                while try await stream.channel.next() != nil {}
                XCTFail("Malformed compressed data must fail, including partial responses")
            } catch { XCTAssertFalse(error is CancellationError) }
            await stream.waitForCompletion()
        }
    }

    func testVideoVisibilityAndFullscreenPolicy() {
        let view = readerChapter("<video id='v' controls='controls' width='200' height='100'></video><p>Text</p>", paged: false)
        evaluate("var v = document.querySelector('video'); var pauses = 0; v.pause = function(){ pauses++; }; true", in: view)
        XCTAssertEqual(evaluate("v.hasAttribute('playsinline')", in: view) as? Bool, false)
        XCTAssertEqual(evaluate("var r = v.getBoundingClientRect(); folioReaderControlAtPoint(r.left + 5, r.top + 5)", in: view) as? Bool, true)
        evaluate("folioSetReaderVisible(false); true", in: view)
        XCTAssertEqual(evaluate("pauses", in: view) as? Int, 1)
        evaluate("folioSetReaderVisible(true); true", in: view)
        XCTAssertEqual(evaluate("pauses", in: view) as? Int, 1, "Returning must not play or pause again")
        evaluate("v.dispatchEvent(new Event('webkitbeginfullscreen', {bubbles:true})); folioSetReaderVisible(false); folioSetMediaPageVisible(false); true", in: view)
        XCTAssertEqual(evaluate("pauses", in: view) as? Int, 1, "Media full screen must keep playing")
        evaluate("folioPauseVideos(true); true", in: view)
        XCTAssertEqual(evaluate("pauses", in: view) as? Int, 2, "Background/close overrides full screen")
        evaluate("v.dispatchEvent(new Event('webkitendfullscreen', {bubbles:true})); true", in: view)
        waitUntil("hidden reader paused after fullscreen") { self.evaluate("pauses >= 3", in: view) as? Bool == true }
        evaluate("folioSetReaderVisible(true); folioSetMediaPageVisible(true); v.style.position='fixed'; v.style.top='2000px'; pauses=0; folioCheckVideoVisibility(); true", in: view)
        XCTAssertEqual(evaluate("pauses", in: view) as? Int, 1)
    }

    func testProductionPlaybackConfiguration() {
        let container = FolioReaderContainer(withConfig: FolioReaderConfig(), folioReader: FolioReader(), epubPath: "", webServer: ReadiumGCDWebServer())
        let view = FolioReaderWebView(frame: .zero, readerContainer: container)
        XCTAssertTrue(view.configuration.allowsInlineMediaPlayback)
        XCTAssertEqual(view.configuration.mediaTypesRequiringUserActionForPlayback, .all)
    }

    func testVideosFitSpreadsAndVerticalTiers() throws {
        let markup = "<video controls='controls' width='640' height='800'></video>"
        let spread = readerChapter(markup, paged: true, size: CGSize(width: 1000, height: 700), spreadMinimumWidth: 800)
        let spreadWidth = try XCTUnwrap(evaluate("document.querySelector('video').getBoundingClientRect().width", in: spread) as? Double)
        XCTAssertLessThanOrEqual(spreadWidth, 400)
        let tiers = readerChapter(markup, paged: false, verticalWriting: true, size: CGSize(width: 700, height: 1100), tiersMinimumHeight: 900)
        let tierHeight = try XCTUnwrap(evaluate("document.querySelector('video').getBoundingClientRect().height", in: tiers) as? Double)
        XCTAssertLessThanOrEqual(tierHeight, 440)
    }

    func testVideoLoadsPlaysAndSeeksThroughEPUBServer() throws {
        // WebKit helpers pump the main run loop synchronously; don't hold an async MainActor task.
        let ready = expectation(description: "EPUB parsed")
        var result: Result<(FolioReaderContainer, EpubResourceServer), Error>?
        Task {
            do { result = .success(try await makeServer()) }
            catch { result = .failure(error) }
            ready.fulfill()
        }
        wait(for: [ready], timeout: 10)
        let (container, server) = try XCTUnwrap(result).get()
        defer { server.stop(); withExtendedLifetime(container) {} }
        warmUpWebKit()
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = [] // Only the decoding test bypasses gestures.
        configuration.userContentController.addUserScript(FolioReaderScript.bridgeJS)
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 650), configuration: configuration)
        let window = UIWindow(frame: UIScreen.main.bounds)
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.addSubview(view)
        window.isHidden = false
        defer { view.stopLoading(); view.removeFromSuperview(); window.isHidden = true; window.rootViewController = nil }
        for path in ["Text/inline.xhtml", "Text/fullscreen.xhtml"] {
            let navigation = VideoNavigationWaiter(expectation(description: "video chapter loaded"))
            view.navigationDelegate = navigation
            view.load(URLRequest(url: URL(string: "http://localhost:\(server.port)/sample/EPUB/\(path)")!))
            // The first video can launch a GPU/media process even after text WebKit is warm.
            wait(for: [navigation.loaded], timeout: 120)
            guard navigation.finished else { throw NSError(domain: "VideoNavigation", code: 1) }
            if let error = navigation.error { throw error }
            waitUntil("video metadata", timeout: 15) {
                self.evaluate("location.pathname === '/sample/EPUB/\(path)' && !!document.querySelector('video') && document.querySelector('video').readyState >= 1", in: view) as? Bool == true
            }
            guard evaluate("Number.isFinite(document.querySelector('video').duration)", in: view) as? Bool == true else {
                throw NSError(domain: "VideoMetadata", code: 1)
            }
            XCTAssertEqual(evaluate("document.querySelector('video').hasAttribute('playsinline')", in: view) as? Bool, path.contains("inline.xhtml"))
            let duration = try XCTUnwrap(evaluate("document.querySelector('video').duration", in: view) as? Double)
            XCTAssertEqual(duration, 8, accuracy: 0.2)
            XCTAssertEqual(evaluate("document.querySelector('video').videoWidth", in: view) as? Int, 320)
            // Force inline in the test only so programmatic playback doesn't present a native controller.
            evaluate("var v = document.querySelector('video'); v.setAttribute('playsinline', 'playsinline'); v.muted = true; v.play().catch(function(e){ window.playError = String(e); }); true", in: view)
            waitUntil("playback advances", timeout: 10) { self.evaluate("v.currentTime > 0.2", in: view) as? Bool == true }
            evaluate("v.pause(); v.currentTime = 6; true", in: view)
            waitUntil("seek completes", timeout: 10) { self.evaluate("!v.seeking && Math.abs(v.currentTime - 6) < 0.3 && v.readyState >= 2", in: view) as? Bool == true }
            XCTAssertNil(evaluate("window.playError || null", in: view) as? String)
        }
    }
}

@MainActor
private final class VideoNavigationWaiter: NSObject, WKNavigationDelegate {
    let loaded: XCTestExpectation
    var finished = false
    var error: Error?
    init(_ loaded: XCTestExpectation) { self.loaded = loaded }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished = true
        loaded.fulfill()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.error = error
        finished = true
        loaded.fulfill()
    }
}

/// Hold the first extraction block until the test closes the HTTP response. The backing read
/// deliberately ignores Task cancellation, just like the dependency's file transaction.
private actor PrefixReadGate {
    private let onFirstRead: @Sendable () -> Void
    private var armed = false
    private var heldRead: CheckedContinuation<Void, Never>?
    private(set) var blockReads = 0

    init(onFirstRead: @escaping @Sendable () -> Void) { self.onFirstRead = onFirstRead }
    func arm() { armed = true }
    func beforeRead(length: Int) async {
        guard armed, length == 64 * 1024 else { return }
        blockReads += 1
        guard blockReads == 1 else { return }
        await withCheckedContinuation { continuation in
            heldRead = continuation
            onFirstRead()
        }
    }
    func release() {
        heldRead?.resume()
        heldRead = nil
    }
}

private struct GatedZIPSource: DataSource {
    let data: Data
    let gate: PrefixReadGate
    var isWritable: Bool { false }
    func length() async throws -> UInt64 { UInt64(data.count) }
    func openRead() async throws -> DataSourceTransaction { GatedZIPTransaction(data: data, gate: gate) }
}

private actor GatedZIPTransaction: DataSourceTransaction {
    private let data: Data
    private let gate: PrefixReadGate
    private var offset = 0
    init(data: Data, gate: PrefixReadGate) { self.data = data; self.gate = gate }
    func position() async throws -> UInt64 { UInt64(offset) }
    func seek(to position: UInt64) async throws { offset = Int(position) }
    func read(length: Int) async throws -> Data {
        await gate.beforeRead(length: length)
        let end = min(data.count, offset + length)
        let result = data.subdata(in: offset..<end)
        offset = end
        return result
    }
}
