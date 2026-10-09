//
//  EpubResourceServer.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 15/04/15.
//  Refactored by DeepMind Antigravity on 7/3/26.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import Foundation
import ReadiumGCDWebServer
import ReadiumZIPFoundation

/// Encapsulates EPUB web server routing and request handling.
open class EpubResourceServer {
    private let webServer: ReadiumGCDWebServer
    private let dateFormatter = DateFormatter()
    private weak var container: FolioReaderContainer?
    private let preferredPort: UInt = 46436
    private var handlersInstalled = false

    /// The port the pages load from. Kept across stops and restarts, because loaded pages keep
    /// their URLs; it only changes when it can't be bound again.
    public private(set) var port: UInt = 0

    public init(webServer: ReadiumGCDWebServer, container: FolioReaderContainer) {
        self.webServer = webServer
        self.container = container
        
        self.dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        self.dateFormatter.locale = Locale(identifier: "en_US")
        self.dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    }

    /// Whether the server is listening. `ReadiumGCDWebServer.isRunning` stays true after a failed
    /// restart, so check the port as well.
    public var isListening: Bool {
        webServer.isRunning && webServer.port != 0
    }

    /// Registers the handlers once and starts the server on `port` if it was started before, else
    /// on 46436, else on any free port.
    ///
    /// The server is always started with an explicit port. ReadiumGCDWebServer suspends itself in
    /// the background and binds again with its start options when the app returns; started without a
    /// port (the old fallback), it came back on a different one, and every loaded page pointed at a
    /// dead port. Returns whether the port changed, in which case loaded pages must be reloaded.
    @discardableResult
    public func start() -> Bool {
        installHandlersIfNeeded()
        guard !isListening else { return false }
        // Running but not listening: a restart after the background failed to bind.
        if webServer.isRunning {
            webServer.stop()
        }

        let previousPort = port
        let candidates = [previousPort, preferredPort].filter { $0 != 0 }
        if !candidates.contains(where: start(on:)), start(on: 0) {
            // Any free port, then that port explicitly, so a restart binds it again.
            let freePort = webServer.port
            webServer.stop()
            if !start(on: freePort) {
                _ = start(on: 0)
            }
        }
        // Nothing bound: keep the pages' port to try again later.
        guard webServer.port != 0 else { return false }
        port = webServer.port
        return previousPort != 0 && port != previousPort
    }

    private func start(on port: UInt) -> Bool {
        var options: [String: Any] = [ReadiumGCDWebServerOption_BindToLocalhost: true]
        if port != 0 {
            options[ReadiumGCDWebServerOption_Port] = port
        }
        guard (try? webServer.start(options: options)) != nil else { return false }
        if webServer.port == 0 {
            webServer.stop()
            return false
        }
        return true
    }

    /// Stops the server if running. `start()` binds the same port again.
    public func stop() {
        if webServer.isRunning {
            webServer.stop()
        }
    }

    private func installHandlersIfNeeded() {
        guard !handlersInstalled else { return }
        handlersInstalled = true
        setupHandlers()
    }

    private func setupHandlers() {
        // Default GET handler to serve zipped EPUB resources
        webServer.addDefaultHandler(forMethod: "GET", request: ReadiumGCDWebServerRequest.self, asyncProcessBlock: { [weak self] request, uninstrumentedCompletion in
            let resourceInterval = FolioSignpost.begin("Resource", request.path)
            let completion: ReadiumGCDWebServerCompletionBlock = { response in
                resourceInterval.end()
                uninstrumentedCompletion(response)
            }
            guard let self = self, let container = self.container else {
                completion(ReadiumGCDWebServerErrorResponse())
                return
            }
            
            guard let path = request.path.removingPercentEncoding else {
                completion(ReadiumGCDWebServerErrorResponse())
                return
            }
            print("EpubResourceServer GCDREQUEST path=\(path)")
            
            var pathSegs = path.split(separator: "/")
            guard pathSegs.count > 1 else {
                completion(ReadiumGCDWebServerErrorResponse())
                return
            }
            pathSegs.removeFirst()
            let resourcePath = pathSegs.joined(separator: "/")
            
            Task {
                do {
                    guard let archiveURL = container.book.epubURL else {
                        completion(ReadiumGCDWebServerErrorResponse())
                        return
                    }
                    
                    guard let entry = container.book.archiveEntriesCache[resourcePath] else {
                        completion(ReadiumGCDWebServerErrorResponse())
                        return
                    }
                    
                    let archive = try await Archive(url: archiveURL, accessMode: .read)
                    
                    var contentType = ReadiumGCDWebServerGetMimeTypeForExtension((resourcePath as NSString).pathExtension, nil)
                    if contentType.contains("text/") {
                        contentType += ";charset=utf-8"
                    }
                    
                    let stream = AsyncStream<Data> { continuation in
                        Task {
                            do {
                                _ = try await archive.extract(entry) { data in
                                    continuation.yield(data)
                                }
                                continuation.finish()
                            } catch {
                                print("EpubResourceServer zipfile-deflate-error \(resourcePath) error=\(error.localizedDescription)")
                                continuation.finish()
                            }
                        }
                    }
                    
                    let streamIterator = ReadiumStreamIterator(stream.makeAsyncIterator())
                    
                    let streamResponse = ReadiumGCDWebServerStreamedResponse(
                          contentType: contentType,
                          asyncStreamBlock: { streamCompletion in
                              Task {
                                  let data = await streamIterator.next()
                                  streamCompletion(data ?? Data(), nil)
                              }
                          }
                    )
                    
                    if let modificationDate = entry.fileAttributes[.modificationDate] as? Date {
                        streamResponse.setValue(self.dateFormatter.string(from: modificationDate), forAdditionalHeader: "Last-Modified")
                        streamResponse.cacheControlMaxAge = 60
                    }
                    
                    completion(streamResponse)
                } catch {
                    print("EpubResourceServer archive-error \(resourcePath) error=\(error.localizedDescription)")
                    completion(ReadiumGCDWebServerErrorResponse())
                }
            }
        })

        // Font GET handler to serve fonts from documents directory
        webServer.addHandler(forMethod: "GET", pathRegex: "^/_fonts/.+?(otf|ttf)$", request: ReadiumGCDWebServerRequest.self, asyncProcessBlock: { request, completion in
            let fileName = (request.path as NSString).lastPathComponent
            print("EpubResourceServer GCDREQUEST FONT fileName=\(fileName) path=\(request.path)")

            guard let documentDirectory = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else {
                completion(ReadiumGCDWebServerErrorResponse())
                return
            }
            
            let fontFileURL = documentDirectory.appendingPathComponent("Fonts", isDirectory: true).appendingPathComponent(fileName, isDirectory: false)
            guard FileManager.default.fileExists(atPath: fontFileURL.path) else {
                completion(ReadiumGCDWebServerErrorResponse())
                return
            }
            
            guard let fileResponse = ReadiumGCDWebServerFileResponse(file: fontFileURL.path) else {
                completion(ReadiumGCDWebServerErrorResponse())
                return
            }
            
            completion(fileResponse)
        })
    }
}

/// Actor wrapping AsyncStream iterator for thread safety
private actor ReadiumStreamIterator {
    private var iterator: AsyncStream<Data>.AsyncIterator
    init(_ iterator: AsyncStream<Data>.AsyncIterator) {
        self.iterator = iterator
    }
    func next() async -> Data? {
        var it = iterator
        let data = await it.next()
        iterator = it
        return data
    }
}
