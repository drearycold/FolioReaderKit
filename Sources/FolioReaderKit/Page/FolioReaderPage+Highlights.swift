//
//  FolioReaderPage+Highlights.swift
//  FolioReaderKit
//

import UIKit

extension FolioReaderPage {
    func injectHighlights(completion: (() -> Void)? = nil) {
        self.layoutAdapting = "Preparing Document Annotations..."
        
        guard let bookId = (self.book.name as NSString?)?.deletingPathExtension else {
            completion?()
            return
        }
        
        let provider = self.folioReader.highlightProvider
        let reader = self.folioReader
        let pageNum = self.pageNumber
        
        Task {
            let originalHighlights = await provider?.highlights(bookId: bookId, page: pageNum, for: reader) ?? []
            let highlights = originalHighlights.map({ hl -> FolioReaderHighlight in
                let prefix = "/2"
                if let cfiStart = hl.cfiStart, cfiStart.hasPrefix(prefix) {
                    hl.cfiStart = String(cfiStart[cfiStart.index(cfiStart.startIndex, offsetBy: prefix.count)..<cfiStart.endIndex])
                }
                if let cfiEnd = hl.cfiEnd, cfiEnd.hasPrefix(prefix) {
                    hl.cfiEnd = String(cfiEnd[cfiEnd.index(cfiEnd.startIndex, offsetBy: prefix.count)..<cfiEnd.endIndex])
                }
                return hl
            })
            
            guard !highlights.isEmpty else {
                await MainActor.run {
                    completion?()
                }
                return
            }
            
            let encodedData = ((try? JSONEncoder().encode(highlights)) ?? .init()).base64EncodedString()
            
            await MainActor.run {
                // The page may have been reused or released while the provider answered; the page-load
                // chain must still continue.
                guard let webView = self.webView else {
                    completion?()
                    return
                }
                let highlightsInterval = FolioSignpost.begin("HighlightsJS", "\(highlights.count) highlights")
                webView.js("injectHighlights('\(encodedData)')") { results in
                    highlightsInterval.end()
                    defer {
                        completion?()
                    }
                    
                    //FIXME: populate toc family titles
                    guard let webViewFrameSize = self.webView?.frame.size else { return }
                    
                    let decoder = JSONDecoder()
                    guard let results = results,
                          let encodedData = results.data(using: .utf8),
                          let encodedObjects = try? decoder.decode([String].self, from: encodedData)
                    else { return }
                    
                    var highlightIdToBoundingMap = [String: NodeBoundingClientRect]()
                    encodedObjects.forEach { encodedObject in
                        guard let objectData = encodedObject.data(using: .utf8),
                              let object = try? decoder.decode(NodeBoundingClientRect.self, from: objectData) else { return }
                        
                        guard object.err.isEmpty else {
                            self.folioReader.readerCenter?.highlightErrors[object.id] = object.err
                            return
                        }
                        
                        self.folioReader.readerCenter?.highlightErrors.removeValue(forKey: object.id)
                        
                        highlightIdToBoundingMap[object.id] = object
                    }
                    
                    highlights.filter {
                        $0.tocFamilyTitles.first == "TODO" || $0.tocFamilyTitles.isEmpty
                    }.forEach { highlight in
                        guard let boundingRect = highlightIdToBoundingMap[highlight.highlightId] else { return }
                        
                        let contentOffset = CGPoint(x: boundingRect.left, y: boundingRect.top)
                        
                        let highlightChapterNames = self.getChapterTocReferences(for: contentOffset, by: webViewFrameSize).compactMap { $0.title }
                        
                        guard highlightChapterNames.first != "TODO" else { return }
                        
                        highlight.tocFamilyTitles = highlightChapterNames.reversed()
                        highlight.date += 0.001
                        
                        print("\(#function) fixHighlight \(boundingRect) \(highlight.tocFamilyTitles) \(highlight.content)")
                        let provider = self.folioReader.highlightProvider
                        let reader = self.folioReader
                        Task {
                            _ = try? await provider?.addHighlight(highlight, for: reader)
                        }
                    }
                }
            }
        }
    }
    
    func relocateHighlights(highlight: FolioReaderHighlight, completion: ((FolioReaderHighlight?, FolioReaderHighlightError?) -> Void)? = nil) {
        let encodedData = ((try? JSONEncoder().encode([highlight])) ?? .init()).base64EncodedString()
        
        self.webView?.js("relocateHighlights('\(encodedData)')") { results in
            guard let results = results else { return }
            
            defer {
                print("\(#function) results=\(results)")
            }
            
            guard let resultsData = results.data(using: .utf8),
                  let result = try? JSONDecoder().decode([NodeBoundingClientRect].self, from: resultsData).first
            else {
                completion?(highlight, FolioReaderHighlightError.runtimeError("Unknown Exception"))
                return
            }
            
            guard let highlightData = result.err.data(using: .utf8)
            else {
                completion?(highlight, FolioReaderHighlightError.runtimeError("Unknown Exception"))
                return
            }
            
            self.webView?.handleHighlightReturn(highlightData, withNote: !(highlight.noteForHighlight?.isEmpty ?? true), original: highlight) { highlight, error in
                completion?(highlight, error)
            }
        }
    }
}
