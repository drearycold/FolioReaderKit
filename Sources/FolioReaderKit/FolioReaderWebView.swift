//
//  FolioReaderWebView.swift
//  FolioReaderKit
//
//  Created by Hans Seiffert on 21.09.16.
//  Copyright (c) 2016 Folio Reader. All rights reserved.
//

import WebKit

public typealias JSCallback = (String?) ->()

/// The custom WebView used in each page
open class FolioReaderWebView: WKWebView {
    var isColors = false
    var isSharingHighlight = false
    
    var mDictView : UINavigationController?
    
    open var additionalMenuItems = [UIMenuItem]()
    
    let cssOverflowPropertyID = "folio_style_html_overflow"
    fileprivate(set) var cssOverflowProperty = "scroll" {
        didSet {
//            FolioReaderScript.cssInjection(overflow: cssOverflowProperty, id: cssOverflowPropertyID).addIfNeeded(to: self)
        }
    }

    let cssRuntimePropertyID = "folio_style_runtime"
    var cssRuntimeProperty = "" {
        didSet {
            FolioReaderScript(
                source: FolioReaderScript.cssInjectionSource(for: cssRuntimeProperty, id: cssRuntimePropertyID)
            ).addIfNeeded(to: self)
        }
    }

    
    fileprivate weak var readerContainer: FolioReaderContainer?

    fileprivate var readerConfig: FolioReaderConfig {
        guard let readerContainer = readerContainer else { return FolioReaderConfig() }
        return readerContainer.readerConfig
    }

    fileprivate var book: FRBook {
        guard let readerContainer = readerContainer else { return FRBook() }
        return readerContainer.book
    }

    fileprivate var folioReader: FolioReader {
        guard let readerContainer = readerContainer else { return FolioReader() }
        return readerContainer.folioReader
    }

    init(frame: CGRect, readerContainer: FolioReaderContainer) {
        self.readerContainer = readerContainer
        
        let configuration = WKWebViewConfiguration()
        configuration.dataDetectorTypes = .link
        if let wkProcessorPool = readerContainer.folioReader.readerCenter?.wkProcessorPool {
            configuration.processPool = wkProcessorPool
        }
        super.init(frame: frame, configuration: configuration)
        FolioReaderScript.bridgeJS.addIfNeeded(to: self)
        FolioReaderScript.readiumCFIJS.addIfNeeded(to: self)

        FolioReaderScript.cssInjection.addIfNeeded(to: self)
        FolioReaderScript(
            source: FolioReaderScript.cssInjectionSource(for: folioReader.cssUserFontFaces(), id: "folio_style_user_font_faces")
        ).addIfNeeded(to: self)
        FolioReaderScript(
            source: FolioReaderScript.cssInjectionSource(for: folioReader.cssFontFamilies(), id: "folio_style_font_families")
        ).addIfNeeded(to: self)
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UIMenuController

    open override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard readerConfig.useReaderMenuController else {
            return super.canPerformAction(action, withSender: sender)
        }

        var result = false
        if isSharingHighlight {
            result = false
            let canPerform = action == #selector(updateHighlightNote(_:))
            
            print("\(#function) canPerform=\(canPerform) action=\(action)")
            if canPerform {
                result = true
            }
        } else if isColors {
            result = false
        } else {
            let canPerform = action == #selector(highlight(_:))
            || action == #selector(highlightWithNote(_:))
            || action == #selector(updateHighlightNote(_:))
            || (action == #selector(define(_:)))
            || (action == #selector(reference(_:)))
            || (action == #selector(lookup(_:)) && self.mDictView != nil)
            || (action == #selector(play(_:)) && (book.hasAudio || readerConfig.enableTTS))
            || (action == #selector(share(_:)) && readerConfig.allowSharing)
            || (action == #selector(copy(_:)) && readerConfig.allowCopy)
            print("\(#function) canPerform=\(canPerform) action=\(action)")
            if canPerform {
                result = true
            }
        }
        
        if folioReader.readerContainer?.readerConfig.debug.contains(.contentMenu) ?? false {
            let menuItems = UIMenuController.shared.menuItems ?? [UIMenuItem]()
            let menuItemTitle = menuItems.compactMap { $0.title }
            
            print("FRWV canPerformAction \(readerConfig.useReaderMenuController) \(isSharingHighlight) \(isColors) \(result) \(action) \(menuItemTitle)")
        }
        
        return result
    }

    // MARK: - UIMenuController - Actions

    @objc func share(_ sender: UIMenuController?) {
        guard let sender = sender else { return }
        
        guard let currentPage = self.folioReader.readerCenter?.currentPage,
              let webView = currentPage.webView
        else {
            return
        }
        
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        let shareImage = UIAlertAction(title: self.readerConfig.localizedShareImageQuote, style: .default, handler: { (action) -> Void in
            if webView.isSharingHighlight {
                webView.js("getHighlightContent()") { textToShare in
                    guard let textToShare = textToShare else { return }
                    self.folioReader.readerCenter?.presentQuoteShare(textToShare)
                }
            } else {
                webView.js("getSelectedText()") { textToShare in
                    guard let textToShare = textToShare else { return }
                    self.folioReader.readerCenter?.presentQuoteShare(textToShare)

                    self.clearTextSelection()
                }
            }
            self.setMenuVisible(false)
        })

        let shareText = UIAlertAction(title: self.readerConfig.localizedShareTextQuote, style: .default) { (action) -> Void in
            if webView.isSharingHighlight {
                webView.js("getHighlightContent()") { textToShare in
                    guard let textToShare = textToShare else { return }
                    self.folioReader.readerCenter?.shareHighlight(textToShare, rect: sender.menuFrame)
                }
            } else {
                webView.js("getSelectedText()") { textToShare in
                    guard let textToShare = textToShare else { return }
                    self.folioReader.readerCenter?.shareHighlight(textToShare, rect: sender.menuFrame)
                }
            }
            self.setMenuVisible(false)
        }

        let cancel = UIAlertAction(title: self.readerConfig.localizedCancel, style: .cancel, handler: nil)

        alertController.addAction(shareImage)
        alertController.addAction(shareText)
        alertController.addAction(cancel)

        if let alert = alertController.popoverPresentationController {
            alert.sourceView = self.folioReader.readerCenter?.currentPage
            alert.sourceRect = sender.menuFrame
        }

        self.folioReader.readerCenter?.present(alertController, animated: true, completion: nil)
    }

    func colors(_ sender: UIMenuController?) {
        isColors = true
        createMenu(onHighlight: false)
        setMenuVisible(true)
    }

    func remove(_ sender: UIMenuController?) {
        js("removeThisHighlight()") { removedId in
            guard let removedId = removedId else { return }
            self.folioReader.delegate?.folioReaderHighlightProvider?(self.folioReader).folioReaderHighlight(self.folioReader, removedId: removedId)
        }
        createMenu(onHighlight: false)
        setMenuVisible(false)
    }

    @objc func highlight(_ sender: UIMenuController?) {
        js("highlightStringCFI('\(FolioReaderHighlightStyle.classForStyle(self.folioReader.currentHighlightStyle))', false)") { highlightAndReturn in
            guard let highlightAndReturn = highlightAndReturn else { return }
            
            print(highlightAndReturn)
            guard let jsonData = highlightAndReturn.data(using: .utf8) else {
                return
            }
            self.handleHighlightReturn(jsonData)
        }
    }
    
    @objc func highlightWithNote(_ sender: UIMenuController?) {
        js("highlightStringCFI('\(FolioReaderHighlightStyle.classForStyle(self.folioReader.currentHighlightStyle))', true)") { highlightAndReturn in
            guard let highlightAndReturn = highlightAndReturn else { return }

            print(highlightAndReturn)
            guard let jsonData = highlightAndReturn.data(using: .utf8) else {
                return
            }

            self.handleHighlightReturn(jsonData, withNote: true)
        }
    }
    
    // will keep original's id and date if presented
    func handleHighlightReturn(_ jsonData: Data, withNote: Bool = false, original: FolioReaderHighlight? = nil, completion: ((FolioReaderHighlight?, FolioReaderHighlightError?) -> Void)? = nil) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? NSArray,
                  let dic = json.firstObject as? [String: String] else {
                      throw FolioReaderHighlightError.runtimeError("no json result, string=\(String(data: jsonData, encoding: .utf8) ?? "(invalid data)")")
            }
            guard let startOffset = dic["startOffset"], let startOffsetInt = Int(startOffset) else {
                throw FolioReaderHighlightError.runtimeError("no start offset")
            }
            guard let endOffset = dic["endOffset"], let endOffsetInt = Int(endOffset) else {
                throw FolioReaderHighlightError.runtimeError("no end offset")
            }
            guard let prevHighlightLengthStart = dic["prevHighlightLengthStart"], let prevHighlightLengthStartInt = Int(prevHighlightLengthStart) else {
                throw FolioReaderHighlightError.runtimeError("no prevHighlightLengthStart")
            }
            guard let prevHighlightLengthEnd = dic["prevHighlightLengthEnd"], let prevHighlightLengthEndInt = Int(prevHighlightLengthEnd) else {
                throw FolioReaderHighlightError.runtimeError("no prevHighlightLengthEnd")
            }
            
            let highlight = FolioReaderHighlight()
            highlight.bookId = self.book.name?.deletingPathExtension
            highlight.startOffset = startOffsetInt
            highlight.endOffset = endOffsetInt
            highlight.content = dic["content"]
            highlight.cfiStart = dic["cfiStart"]
            highlight.cfiEnd = dic["cfiEnd"]
            highlight.contentPost = dic["contentPost"]
            highlight.contentPre = dic["contentPre"]
            if let date = original?.date {
                highlight.date = date + 0.001
            } else {
                highlight.date = Date()
            }
            highlight.highlightId = original?.highlightId ?? dic["id"]
            highlight.page = self.folioReader.readerCenter?.currentPageNumber ?? 1
            highlight.type = self.folioReader.currentHighlightStyle
            highlight.style = FolioReaderHighlightStyle.classForStyle(highlight.type)

            if prevHighlightLengthStartInt > 0,
               let cfiStart = highlight.cfiStart,
               let idx = cfiStart.firstIndex(of: ":") {
                let offsetIdx = cfiStart.index(after: idx)
                if let offset = Int(cfiStart[offsetIdx...]) {
                    highlight.cfiStart = String(cfiStart[..<offsetIdx]) + Int(offset + prevHighlightLengthStartInt).description
                }
            }
            if prevHighlightLengthEndInt > 0,
               let cfiEnd = highlight.cfiEnd,
               let idx = cfiEnd.firstIndex(of: ":") {
                let offsetIdx = cfiEnd.index(after: idx)
                if let offset = Int(cfiEnd[offsetIdx...]) {
                    highlight.cfiEnd = String(cfiEnd[..<offsetIdx]) + Int(offset + prevHighlightLengthEndInt).description
                }
            }
            
            highlight.encodeContents()
            
            let serializedData = try JSONEncoder().encode([highlight])
            let encodedData = serializedData.base64EncodedString()
            self.js("injectHighlights('\(encodedData)')") { result in
                var errMsg: String = "Unknown Error"
                var deferred: (() -> Void)? = {
                    if original == nil {
                        self.folioReader.readerCenter?.presentAddHighlightError(errMsg)
                    } else {
                        completion?(original, FolioReaderHighlightError.runtimeError(errMsg))
                    }
                    return
                }
                
                defer {
                    deferred?()
                }
                
                guard let result = result else {
                    return
                }
                
                let decoder = JSONDecoder()
                
                guard let encodedData = result.data(using: .utf8),
                      let encodedObjects = try? decoder.decode([String].self, from: encodedData)
                else {
                    return
                }
                
                var boundingRect: NodeBoundingClientRect? = nil
                
                if let objectData = encodedObjects.first?.data(using: .utf8) {
                    boundingRect = try? JSONDecoder().decode(NodeBoundingClientRect.self, from: objectData)
                }
                
                guard boundingRect != nil, boundingRect!.err.isEmpty else {
                    errMsg = boundingRect?.err ?? errMsg
                    return
                }
                
                let contentOffset = CGPoint(x: boundingRect!.left, y: boundingRect!.top)
            
                let highlightChapterNames = self.folioReader.readerCenter?.currentPage?.getChapterTocReferences(for: contentOffset, by: self.frame.size).compactMap { $0.title } ?? ["TODO"]
                highlight.tocFamilyTitles = highlightChapterNames.reversed()
                
                highlight.spineName = self.book.spine.spineReferences[highlight.page - 1].resource.href
                if let resHref = highlight.spineName,
                   let opfUrl = URL(string: self.book.opfResource.href),
                   let resUrl = URL(string: resHref, relativeTo: opfUrl) {
                    highlight.spineName = resUrl.absoluteString.replacingOccurrences(of: "//", with: "")
                    while highlight.spineName.hasPrefix("/") {
                        highlight.spineName.removeFirst()
                    }
                }

                if let cfiStart = highlight.cfiStart, cfiStart.hasPrefix("/2") == false {
                    highlight.cfiStart = "/2\(cfiStart)"
                }
                if let cfiEnd = highlight.cfiEnd, cfiEnd.hasPrefix("/2") == false {
                    highlight.cfiEnd = "/2\(cfiEnd)"
                }
                
                if withNote {
                    if original == nil {
                        self.folioReader.readerCenter?.presentAddHighlightNote(highlight, edit: false)
                    } else {
                        completion?(highlight, nil)
                    }
                } else {
                    self.folioReader.delegate?.folioReaderHighlightProvider?(self.folioReader).folioReaderHighlight(self.folioReader, added: highlight) { error in
                        guard error == nil else {
                            if original == nil {
                                self.folioReader.readerCenter?.presentAddHighlightError(error!.localizedDescription)
                            } else {
                                completion?(highlight, FolioReaderHighlightError.runtimeError(error!.localizedDescription))
                            }
                            return
                        }
                        
                        self.clearTextSelection()
                        self.setMenuVisible(false)
                        
                        self.folioReader.readerCenter?.highlightErrors.removeValue(forKey: highlight.highlightId)
                        
                        completion?(highlight, nil)
                    }
                }
                
                deferred = nil
            }
            
        } catch FolioReaderHighlightError.runtimeError(let hlError) {
            completion?(original, FolioReaderHighlightError.runtimeError(hlError))
        } catch {
            completion?(original, FolioReaderHighlightError.runtimeError("\(error.localizedDescription)"))
        }
    }
    
    @objc func updateHighlightNote (_ sender: UIMenuController?) {
        guard let currentPage = self.folioReader.readerCenter?.currentPage,
              let webView = currentPage.webView
        else {
            return
        }
        webView.js("getHighlightId()") { highlightId in
            guard
                let highlightId = highlightId,
                let highlightNote = self.folioReader.delegate?.folioReaderHighlightProvider?(self.folioReader).folioReaderHighlight(self.folioReader, getById: highlightId)
            else { return }
            
            self.folioReader.readerCenter?.presentAddHighlightNote(highlightNote, edit: true)
            self.createMenu(onHighlight: false)
        }
    }

    @objc func define(_ sender: UIMenuController?) {
        guard let currentPage = self.folioReader.readerCenter?.currentPage,
              let webView = currentPage.webView
        else {
            return
        }
        webView.js("getSelectedText()") { selectedText in
            guard let selectedText = selectedText else { return }

            self.setMenuVisible(false)
            self.clearTextSelection()

            let vc = UIReferenceLibraryViewController(term: selectedText)
            vc.view.backgroundColor = self.readerConfig.menuBackgroundColor
            vc.view.tintColor = self.readerConfig.tintColor
            guard let readerContainer = self.readerContainer else { return }
            // readerContainer.show(vc, sender: nil)    // will close reader container
            readerContainer.present(vc, animated: true, completion: nil)
        }
    }

    @objc func lookup(_ sender: UIMenuController?) {
        guard let currentPage = self.folioReader.readerCenter?.currentPage,
              let webView = currentPage.webView
        else {
            return
        }
        webView.js("getSelectedText()") { selectedText in
            guard let selectedText = selectedText else { return }
            guard let mDictView = self.mDictView else { return }

            self.setMenuVisible(false)
            self.clearTextSelection()

            var json = [
                "word": selectedText,
                "backgroundColor": self.readerConfig.themeModeBackground[self.folioReader.themeMode].hexString(false)]
            if self.folioReader.nightMode {
                json["textColor"] = self.readerConfig.themeModeTextColor[self.folioReader.themeMode].hexString(false)
            }
            var title = ""
            do {
                title = String(data: try JSONEncoder().encode(json), encoding: .utf8) ?? selectedText
            } catch {
                title = selectedText
            }
            
            mDictView.title = selectedText
            self.folioReader.readerCenter?.pageDelegate?.pageStyleChanged?(currentPage, self.folioReader)
            
            guard let readerContainer = self.readerContainer else { return }
//            readerContainer.show(mDictView, sender: nil)
            readerContainer.present(mDictView, animated: true)
        }
    }
    
    @objc func reference(_ sender: UIMenuController?) {
        guard let currentPage = self.folioReader.readerCenter?.currentPage,
              let webView = currentPage.webView
        else {
            return
        }
        webView.js("getSelectedTextCFI()") { selJsonStr in
            guard let selJsonData = selJsonStr?.data(using: .utf8),
                  let selJson = try? JSONSerialization.jsonObject(with: selJsonData) as? [String:String],
                  let selectedText = selJson["sel"],
                  let selectedCFI = selJson["cfi"]
            else { return }
            
            self.clearTextSelection()
            self.setMenuVisible(false)
            
            guard let readerCenter = self.readerContainer?.centerViewController,
                  let bookmarkBarButtonItem = readerCenter.navigationItem.leftBarButtonItems?[safe: 2],
                  let selector = bookmarkBarButtonItem.action else { return }
            
            readerCenter.tempRefText = selectedText
            readerCenter.tempRefCFI = selectedCFI
            self.folioReader.currentAnnotationMenuIndex = 0
            UIApplication.shared.sendAction(selector, to: readerCenter, from: bookmarkBarButtonItem, for: nil)
        }
    }
    
    @objc func play(_ sender: UIMenuController?) {
        self.folioReader.readerAudioPlayer?.play()

        self.clearTextSelection()
    }

    open func setMDictView(mDictView: UINavigationController) {
        self.mDictView = mDictView
    }
    
    func setYellow(_ sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .yellow)
    }

    func setGreen(_ sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .green)
    }

    func setBlue(_ sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .blue)
    }

    func setPink(_ sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .pink)
    }

    func setUnderline(_ sender: UIMenuController?) {
        changeHighlightStyle(sender, style: .underline)
    }

    func changeHighlightStyle(_ sender: UIMenuController?, style: FolioReaderHighlightStyle) {
        self.folioReader.currentHighlightStyle = style.rawValue

        js("setHighlightStyle('\(FolioReaderHighlightStyle.classForStyle(style.rawValue))')") { updateId in
            guard let updateId = updateId else { return }
            self.folioReader.delegate?.folioReaderHighlightProvider?(self.folioReader).folioReaderHighlight(self.folioReader, updateById: updateId, type: style)
        }
        
        //FIX: https://github.com/FolioReader/FolioReaderKit/issues/316
        setMenuVisible(false)
    }

    
    // MARK: - Create and show menu

    func createMenu(onHighlight: Bool) {
        guard (self.readerConfig.useReaderMenuController == true) else {
            return
        }

        isSharingHighlight = onHighlight

        let colors = UIImage(readerImageNamed: "colors-marker")
        var share = UIImage(readerImageNamed: "share-marker")
        if #available(iOS 13.0, *) {
            share = share?.withTintColor(.white)
        }
        let remove = UIImage(readerImageNamed: "no-marker")
        let yellow = UIImage(readerImageNamed: "yellow-marker")
        let green = UIImage(readerImageNamed: "green-marker")
        let blue = UIImage(readerImageNamed: "blue-marker")
        let pink = UIImage(readerImageNamed: "pink-marker")
        let underline = UIImage(readerImageNamed: "underline-marker")
        var mdictImage = UIImage(readerImageNamed: "icon-dictionary")
        if #available(iOS 13.0, *) {
            mdictImage = mdictImage?.withTintColor(.white)
        }

        let menuController = UIMenuController.shared

        let highlightItem = UIMenuItem(title: self.readerConfig.localizedHighlightMenu, action: #selector(highlight(_:)))
        let highlightNoteItem = UIMenuItem(title: self.readerConfig.localizedHighlightNote, action: #selector(highlightWithNote(_:)))
        let editNoteItem = UIMenuItem(title: self.readerConfig.localizedHighlightNote, action: #selector(updateHighlightNote(_:)))
        let playAudioItem = UIMenuItem(title: self.readerConfig.localizedPlayMenu, action: #selector(play(_:)))
        let defineItem = UIMenuItem(title: self.readerConfig.localizedDefineMenu, action: #selector(define(_:)))
        let referenceItem = UIMenuItem(title: "Ref.", action: #selector(reference(_:)))
        
        let mDictItem = UIMenuItem(title: self.readerConfig.localizedMDictMenu, image: mdictImage) { [weak self] _ in
            self?.lookup(menuController)
        }
        
        let colorsItem = UIMenuItem(title: "C", image: colors) { [weak self] _ in
            self?.colors(menuController)
        }
        let shareItem = UIMenuItem(title: "S", image: share) { [weak self] _ in
            self?.share(menuController)
        }
        let removeItem = UIMenuItem(title: "R", image: remove) { [weak self] _ in
            self?.remove(menuController)
        }
        let yellowItem = UIMenuItem(title: "Y", image: yellow) { [weak self] _ in
            self?.setYellow(menuController)
        }
        let greenItem = UIMenuItem(title: "G", image: green) { [weak self] _ in
            self?.setGreen(menuController)
        }
        let blueItem = UIMenuItem(title: "B", image: blue) { [weak self] _ in
            self?.setBlue(menuController)
        }
        let pinkItem = UIMenuItem(title: "P", image: pink) { [weak self] _ in
            self?.setPink(menuController)
        }
        let underlineItem = UIMenuItem(title: "U", image: underline) { [weak self] _ in
            self?.setUnderline(menuController)
        }

        var menuItems: [UIMenuItem] = []

        // menu on existing highlight
        if onHighlight {
            menuItems = [colorsItem, editNoteItem, removeItem]
            
            if (self.readerConfig.allowSharing == true) {
                menuItems.append(shareItem)
            }
            
        } else if isColors {
            // menu for selecting highlight color
            menuItems = [yellowItem, greenItem, blueItem, pinkItem, underlineItem]
        } else {
            // default menu
            menuItems = [highlightItem, defineItem, referenceItem, highlightNoteItem]
            if self.readerConfig.enableMDictViewer {
                menuItems.append(mDictItem)
            }

            if self.book.hasAudio || self.readerConfig.enableTTS {
                menuItems.insert(playAudioItem, at: 0)
            }

            if (self.readerConfig.allowSharing == true) {
                menuItems.append(shareItem)
            }
        }
        
        menuController.menuItems = menuItems
        menuController.update()
        
        if let readerContainer = self.folioReader.readerContainer {
            UIMenuController.installTo(responder: readerContainer)
        }
    }
    
    open func setMenuVisible(_ menuVisible: Bool, animated: Bool = true, andRect rect: CGRect = CGRect.zero) {
        if menuVisible == false {
            UIMenuController.shared.setMenuVisible(menuVisible, animated: animated)
        }
        
        if !menuVisible && isSharingHighlight || !menuVisible && isColors {
            isColors = false
            isSharingHighlight = false
        }
        
        if menuVisible  {
            if !rect.equalTo(CGRect.zero) {
                UIMenuController.shared.setTargetRect(rect, in: self)
            }
        } else {
            self.createMenu(onHighlight: false)
        }
        
        UIMenuController.shared.setMenuVisible(menuVisible, animated: animated)
    }
    
    // MARK: - Java Script Bridge
    
    @available(iOS 13.0.0, *)
    open func js(_ script: String) async -> String? {
        if let result = try? await evaluateJavaScript(script) {
            let output = "\(result)"
            if output.isEmpty {
                return nil
            } else {
                return output
            }
        } else {
            return nil
        }
    }
    
    open func js(_ script: String, completion: JSCallback? = nil) {
        evaluateJavaScript(script) { result, error in
            let output: String?
            if let result = result {
                let stringResult = "\(result)"
                if stringResult.isEmpty {
                    output = nil
                } else {
                    output = stringResult
                }
            } else {
                output = nil
            }
            if  let nsError = error as NSError?,
                let url = nsError.userInfo["WKJavaScriptExceptionSourceURL"] as? NSURL,
                url.absoluteString == "undefined"
            {
                // skip debugPrint - html hasn't loaded yet
            } else if let error = error {
                debugPrint("evaluateJavaScript(\(script)) returned an error:", error, "url:", self.url?.absoluteString ?? "NOURL")
            }
            completion?(output)
        }
    }
    
    // MARK: WebView
    
    func clearTextSelection() {
        // Forces text selection clearing
        // @NOTE: this doesn't seem to always work
        
        self.isUserInteractionEnabled = false
        self.isUserInteractionEnabled = true
    }
    
    func setupScrollDirection() {
        switch self.readerConfig.scrollDirection {
        case .vertical, .defaultVertical, .horizontalWithScrollContent:
            scrollView.isPagingEnabled = false
            cssOverflowProperty = "scroll"
            scrollView.bounces = true
            break
        case .horitonzalWithPagedContent:
            scrollView.isPagingEnabled = true
            cssOverflowProperty = "-webkit-paged-x"
            scrollView.bounces = false
            break
        }
    }
}
