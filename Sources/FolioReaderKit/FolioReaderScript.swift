//
//  FolioReaderScript.swift
//  FolioReaderKit
//
//  Created by Stanislav on 12.06.2020.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import WebKit

class FolioReaderScript: WKUserScript {
    
    init(source: String) {
        super.init(source: source,
                   injectionTime: .atDocumentEnd,
                   forMainFrameOnly: true)
    }
    
    @available(iOS 14.0, *)
    override init(source: String,
        injectionTime: WKUserScriptInjectionTime,
        forMainFrameOnly: Bool,
        in contentWorld: WKContentWorld) {
        super.init(source: source, injectionTime: injectionTime, forMainFrameOnly: forMainFrameOnly, in: contentWorld)
    }
    
    static let bridgeJS: FolioReaderScript = {
        guard let jsURL = Bundle.frameworkBundle().url(forResource: "Bridge", withExtension: "js"),
              let jsSource = try? String(contentsOf: jsURL) else {
            print("ERROR: Could not find Bridge.js in bundle \(Bundle.frameworkBundle())")
            return FolioReaderScript(source: "")
        }
        return FolioReaderScript(source: jsSource)
    }()
    
    static let readiumCFIJS: FolioReaderScript = {
        guard let jsURL = Bundle.frameworkBundle().url(forResource: "readium-cfi.umd", withExtension: "js"),
              let jsSource = try? String(contentsOf: jsURL) else {
            print("ERROR: Could not find readium-cfi.umd.js in bundle \(Bundle.frameworkBundle())")
            return FolioReaderScript(source: "")
        }
        return FolioReaderScript(source: jsSource)
    }()

}

extension WKUserScript {
    
    func addIfNeeded(to webView: WKWebView?) {
        guard let controller = webView?.configuration.userContentController else { return }
        let alreadyAdded = controller.userScripts.contains { [unowned self] in
            return $0.source == self.source &&
                $0.injectionTime == self.injectionTime &&
                $0.isForMainFrameOnly == self.isForMainFrameOnly
        }
        if alreadyAdded { return }
        controller.addUserScript(self)
    }
    
}
