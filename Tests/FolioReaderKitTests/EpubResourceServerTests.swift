//
//  EpubResourceServerTests.swift
//  FolioReaderKitTests
//
//  Created by DeepMind Antigravity on 7/7/26.
//  Copyright © 2026 FolioReader. All rights reserved.
//

import XCTest
import ReadiumGCDWebServer
@testable import FolioReaderKit

@MainActor
class EpubResourceServerTests: XCTestCase {
    
    func testServerLifecycle() {
        let config = FolioReaderConfig()
        let folioReader = FolioReader()
        let webServer = ReadiumGCDWebServer()
        let container = FolioReaderContainer(
            withConfig: config,
            folioReader: folioReader,
            epubPath: "",
            webServer: webServer
        )
        
        let server = EpubResourceServer(webServer: webServer, container: container)
        
        XCTAssertFalse(webServer.isRunning)
        
        server.start()
        
        XCTAssertTrue(webServer.isRunning)
        
        server.stop()
        
        XCTAssertFalse(webServer.isRunning)
    }

    func testTwoResourceServersCanRunOnSeparatePorts() {
        let firstWebServer = ReadiumGCDWebServer()
        let secondWebServer = ReadiumGCDWebServer()
        let firstContainer = FolioReaderContainer(
            withConfig: FolioReaderConfig(withIdentifier: "reader-one"),
            folioReader: FolioReader(),
            epubPath: "",
            webServer: firstWebServer
        )
        let secondContainer = FolioReaderContainer(
            withConfig: FolioReaderConfig(withIdentifier: "reader-two"),
            folioReader: FolioReader(),
            epubPath: "",
            webServer: secondWebServer
        )
        let firstServer = EpubResourceServer(webServer: firstWebServer, container: firstContainer)
        let secondServer = EpubResourceServer(webServer: secondWebServer, container: secondContainer)

        firstServer.start()
        defer { firstServer.stop() }
        secondServer.start()
        defer { secondServer.stop() }

        XCTAssertTrue(firstWebServer.isRunning)
        XCTAssertTrue(secondWebServer.isRunning)
        XCTAssertNotEqual(firstWebServer.port, secondWebServer.port)

        let firstURL = FolioReaderCenter.resourceURL(
            fileName: "BookOne.epub",
            opfHref: "OPS/package.opf",
            resourceHref: "chapter1.xhtml",
            port: firstWebServer.port
        )
        let secondURL = FolioReaderCenter.resourceURL(
            fileName: "BookTwo.epub",
            opfHref: "OPS/package.opf",
            resourceHref: "chapter1.xhtml",
            port: secondWebServer.port
        )

        XCTAssertEqual(firstURL?.port, Int(firstWebServer.port))
        XCTAssertEqual(secondURL?.port, Int(secondWebServer.port))
        XCTAssertNotEqual(firstURL?.port, secondURL?.port)
    }

    // MARK: - Keeping the pages' port

    private func makeServer() -> (EpubResourceServer, ReadiumGCDWebServer, FolioReaderContainer) {
        let webServer = ReadiumGCDWebServer()
        let container = FolioReaderContainer(withConfig: FolioReaderConfig(), folioReader: FolioReader(), epubPath: "", webServer: webServer)
        return (EpubResourceServer(webServer: webServer, container: container), webServer, container)
    }

    /// Holds `port` on localhost, as another reader or app would. A port that is already taken (the
    /// simulator shares the Mac's loopback, so a running reader app holds 46436) needs no blocker.
    private func occupy(_ port: UInt, mayBeTaken: Bool = false) -> ReadiumGCDWebServer? {
        let blocker = ReadiumGCDWebServer()
        do {
            try blocker.start(options: [ReadiumGCDWebServerOption_Port: port, ReadiumGCDWebServerOption_BindToLocalhost: true])
            XCTAssertEqual(blocker.port, port)
            return blocker
        } catch {
            XCTAssertTrue(mayBeTaken, "\(port) could not be held: \(error)")
            return nil
        }
    }

    /// ReadiumGCDWebServer stops in the background and binds again with its start options when the
    /// app returns. Started without a port, as the fallback did when 46436 was taken, it came back on
    /// another one and the loaded pages pointed at a dead port (reproduced on the simulator).
    func testFallbackPortSurvivesTheBackground() {
        let blocker = occupy(46436, mayBeTaken: true)
        defer { blocker?.stop() }
        let (server, webServer, container) = makeServer()
        defer { server.stop() }

        server.start()
        let port = webServer.port
        XCTAssertNotEqual(port, 0)
        XCTAssertNotEqual(port, 46436)
        XCTAssertEqual(server.port, port)

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertEqual(webServer.port, 0, "Suspended in the background")
        XCTAssertEqual(server.port, port, "The pages' port is remembered")
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        XCTAssertEqual(webServer.port, port, "Back on the same port")
        withExtendedLifetime(container) {}
    }

    /// The reader stops the server when it disappears (a tab switch, a full-screen sheet).
    func testRestartingKeepsThePort() {
        let blocker = occupy(46436, mayBeTaken: true)
        defer { blocker?.stop() }
        let (server, webServer, container) = makeServer()
        defer { server.stop() }

        server.start()
        let port = webServer.port
        server.stop()
        XCTAssertFalse(server.start(), "Same port, nothing to reload")
        XCTAssertEqual(webServer.port, port)
        withExtendedLifetime(container) {}
    }

    /// The server's own restart after the background ignores a failed bind and still reports
    /// `isRunning`. `start()` notices, binds another port and says the pages must reload.
    func testFailedRestartAfterTheBackgroundIsDetected() {
        let (server, webServer, container) = makeServer()
        defer { server.stop() }
        server.start()
        let port = webServer.port

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        let blocker = occupy(port)
        defer { blocker?.stop() }
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        XCTAssertTrue(webServer.isRunning, "ReadiumGCDWebServer still reports running")
        XCTAssertEqual(webServer.port, 0)
        XCTAssertFalse(server.isListening)

        XCTAssertTrue(server.start(), "The port changed")
        XCTAssertTrue(server.isListening)
        XCTAssertNotEqual(server.port, port)
        XCTAssertEqual(server.port, webServer.port)
        withExtendedLifetime(container) {}
    }

    func testReaderServerURLs() {
        XCTAssertTrue(FolioReaderPage.isReaderServerURL(URL(string: "http://localhost:57128/1984.epub/text/ch1.xhtml")!))
        XCTAssertTrue(FolioReaderPage.isReaderServerURL(URL(string: "http://127.0.0.1:46436/a.xhtml")!))
        XCTAssertTrue(FolioReaderPage.isReaderServerURL(URL(string: "http://[::1]:46436/a.xhtml")!))
        XCTAssertFalse(FolioReaderPage.isReaderServerURL(URL(string: "https://example.com/")!))
        XCTAssertFalse(FolioReaderPage.isReaderServerURL(URL(string: "http://example.com/localhost")!))
    }
}
