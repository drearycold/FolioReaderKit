//
//  ContainerLoadTests.swift
//  FolioReaderKitTests
//
//  Copyright © 2026 FolioReader. All rights reserved.
//

import FolioEPUBCore
import ReadiumGCDWebServer
import XCTest
@testable import FolioReaderKit

@MainActor
class ContainerLoadTests: XCTestCase {

    /// The sample book in the Example app, read straight from the source tree (simulator tests share
    /// the host file system).
    private var samplePath: String {
        URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Example/Shared/Sample eBooks/1984.epub").path
    }

    /// Hosting apps can show the reader again without recreating it, for example on a tab switch or
    /// after a full-screen sheet. Each `viewWillAppear` used to re-parse the book and re-apply the
    /// position the book was opened at, sending the reader back there.
    func testReappearingDoesNotReloadTheBook() throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: samplePath), samplePath)

        let delegate = LoadCountingDelegate()
        let folioReader = FolioReader()
        folioReader.delegate = delegate
        let container = FolioReaderContainer(withConfig: FolioReaderConfig(), folioReader: folioReader, epubPath: samplePath, webServer: ReadiumGCDWebServer())
        container.loadViewIfNeeded()

        container.viewWillAppear(false)
        waitUntil("first load") { delegate.loadCount == 1 && folioReader.isReaderReady }

        container.viewWillDisappear(false)
        container.viewWillAppear(false)
        // Give a second (unwanted) load time to happen.
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))

        XCTAssertEqual(delegate.loadCount, 1, "Reappearing must not parse and reload the book again")
        withExtendedLifetime(container) {}
    }

    /// `viewWillDisappear` stops the resource server (a tab switch, a full-screen sheet). Reappearing
    /// no longer reloads the book, so it must start the server again, on the port the pages use.
    func testReappearingRestartsTheServerOnTheSamePort() throws {
        let folioReader = FolioReader()
        let webServer = ReadiumGCDWebServer()
        let container = FolioReaderContainer(withConfig: FolioReaderConfig(), folioReader: folioReader, epubPath: samplePath, webServer: webServer)
        container.loadViewIfNeeded()
        container.viewWillAppear(false)
        waitUntil("first load") { folioReader.isReaderReady && webServer.port != 0 }
        let port = webServer.port

        container.viewWillDisappear(false)
        container.viewWillAppear(false)
        waitUntil("server running again") { webServer.port != 0 }
        XCTAssertEqual(webServer.port, port, "Pages keep their URLs")
        container.viewWillDisappear(false)
        withExtendedLifetime(container) {}
    }

    /// A reader opened with `presentReader` / `prepareReader` saves its state when the app leaves the
    /// foreground. The observers used `saveReaderState(completion:)` as their selector, so the
    /// notification arrived where the closure goes and was called and released as one: the Example
    /// crashed every time it went to the background.
    func testLeavingTheForegroundDoesNotCrash() {
        let folioReader = FolioReader()
        folioReader.prepareReader(parentViewController: UIViewController(), withEpubPath: samplePath, andConfig: FolioReaderConfig(), folioReaderCenterDelegate: nil, webServer: ReadiumGCDWebServer())

        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.willTerminateNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        withExtendedLifetime(folioReader) {}
    }

    private func waitUntil(_ description: String, timeout: TimeInterval = 10, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertTrue(condition(), "Timed out waiting for \(description)")
    }
}

private final class LoadCountingDelegate: NSObject, FolioReaderDelegate {
    var loadCount = 0

    func folioReader(_ folioReader: FolioReader, didFinishedLoading book: FRBook) {
        loadCount += 1
    }
}
