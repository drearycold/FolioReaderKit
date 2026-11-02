//
//  EpubJSBridge.swift
//  FolioReaderKit
//
//  Created by Gemini on 2026/03/21.
//

import Foundation
import WebKit

protocol EpubJSBridgeDelegate: AnyObject {
    func epubJSBridge(_ bridge: EpubJSBridge, didReceiveCommand command: EpubJSBridge.JSCommand, message: String)
}

class EpubJSBridge: NSObject, WKScriptMessageHandler {
    enum JSCommand: String {
        case bridgeFinished = "bridgeFinished"
        case getComputedStyle = "getComputedStyle"
        case writingMode = "writingMode"
        case mediaFullscreen = "mediaFullscreen"
        case unknown = "unknown"
        
        static func from(message: String) -> (JSCommand, String) {
            for command in [bridgeFinished, getComputedStyle, writingMode, mediaFullscreen] {
                if message.hasPrefix(command.rawValue) {
                    let content = message.suffix(message.count - command.rawValue.count).trimmingCharacters(in: .whitespaces)
                    return (command, content)
                }
            }
            return (.unknown, message)
        }
    }
    
    weak var delegate: EpubJSBridgeDelegate?
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? String else { return }
        
        let (command, content) = JSCommand.from(message: body)
        delegate?.epubJSBridge(self, didReceiveCommand: command, message: content)
    }
}
