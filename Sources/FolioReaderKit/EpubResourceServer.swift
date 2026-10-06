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

    public init(webServer: ReadiumGCDWebServer, container: FolioReaderContainer) {
        self.webServer = webServer
        self.container = container
        
        self.dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        self.dateFormatter.locale = Locale(identifier: "en_US")
        self.dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    }

    /// Registers default and font handlers, and starts the server.
    public func start() {
        setupHandlers()
        
        try? webServer.start(options: [
            ReadiumGCDWebServerOption_Port: preferredPort,
            ReadiumGCDWebServerOption_BindToLocalhost: true
        ])
        
        // Fallback
        if webServer.isRunning == false {
            try? webServer.start(options: [
                ReadiumGCDWebServerOption_BindToLocalhost: true
            ])
            
            if webServer.isRunning == false {
                try? webServer.start(options: [
                    ReadiumGCDWebServerOption_BindToLocalhost: true
                ])
            }
        }
    }

    /// Stops the server if running.
    public func stop() {
        if webServer.isRunning {
            webServer.stop()
        }
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
