//
//  FolioReaderPage+EpubJSBridge.swift
//  FolioReaderKit
//

import Foundation

extension FolioReaderPage {
    // MARK: EpubJSBridgeDelegate
    func epubJSBridge(_ bridge: EpubJSBridge, didReceiveCommand command: EpubJSBridge.JSCommand, message: String) {
        if self.readerConfig.debug.contains(.htmlStyling) {
            print("epubJSBridge response \(command.rawValue) \n\(message)")
        }

        switch command {
        case .bridgeFinished:
            guard self.readerConfig.debug.contains(.htmlStyling) else { break }
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent(self.book.spine.spineReferences[self.pageNumber-1].resource.href.lastPathComponent)
            print("\(#function) tempDir=\(tempDir.absoluteString) tempFile=\(tempFile.absoluteString)")
            try? FileManager.default.removeItem(atPath: tempFile.path)
            FileManager.default.createFile(atPath: tempFile.path, contents: message.data(using: .utf8), attributes: nil)
        case .writingMode:
            print("writingMode \(message)")
        case .getComputedStyle:
            // Handle if needed
            break
        case .unknown:
            break
        }
    }
}
