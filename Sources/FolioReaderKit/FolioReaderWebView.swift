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
    var isShare = false
    var isOneWord = false
    
    var mDictView : UIViewController?
    
    open var additionalMenuItems = [UIMenuItem]()
    
    fileprivate(set) var cssOverflowProperty = "scroll" {
        didSet {
            FolioReaderScript.cssInjection(overflow: cssOverflowProperty).addIfNeeded(to: self)
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
        super.init(frame: frame, configuration: configuration)
        FolioReaderScript.cssInjection.addIfNeeded(to: self)
        FolioReaderScript.readiumCFIJS.addIfNeeded(to: self)
        FolioReaderScript.bridgeJS.addIfNeeded(to: self)
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
        if isShare {
            result = false
        } else if isColors {
            result = false
        } else {
            if action == #selector(highlight(_:))
                || action == #selector(highlightWithNote(_:))
                || action == #selector(updateHighlightNote(_:))
                || (action == #selector(define(_:)))
                || (action == #selector(lookup(_:)) && self.mDictView != nil)
                || (action == #selector(play(_:)) && (book.hasAudio || readerConfig.enableTTS))
                || (action == #selector(share(_:)) && readerConfig.allowSharing)
                || (action == #selector(copy(_:)) && readerConfig.allowCopy) {
                result = true
            }
        }
        
        if folioReader.readerContainer?.readerConfig.debug.contains(.contentMenu) ?? false {
            let menuItems = UIMenuController.shared.menuItems ?? [UIMenuItem]()
            let menuItemTitle = menuItems.compactMap { $0.title }
            
            print("FRWV canPerformAction \(readerConfig.useReaderMenuController) \(isShare) \(isColors) \(result) \(action) \(menuItemTitle)")
        }
        
        return result
    }

    // MARK: - UIMenuController - Actions

    @objc func share(_ sender: UIMenuController?) {
        guard let sender = sender else { return }
        
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        let shareImage = UIAlertAction(title: self.readerConfig.localizedShareImageQuote, style: .default, handler: { (action) -> Void in
            if self.isShare {
                self.js("getHighlightContent()") { textToShare in
                    guard let textToShare = textToShare else { return }
                    self.folioReader.readerCenter?.presentQuoteShare(textToShare)
                }
            } else {
                self.js("getSelectedText()") { textToShare in
                    guard let textToShare = textToShare else { return }
                    self.folioReader.readerCenter?.presentQuoteShare(textToShare)

                    self.clearTextSelection()
                }
            }
            self.setMenuVisible(false)
        })

        let shareText = UIAlertAction(title: self.readerConfig.localizedShareTextQuote, style: .default) { (action) -> Void in
            if self.isShare {
                self.js("getHighlightContent()") { textToShare in
                    guard let textToShare = textToShare else { return }
                    self.folioReader.readerCenter?.shareHighlight(textToShare, rect: sender.menuFrame)
                }
            } else {
                self.js("getSelectedText()") { textToShare in
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
        createMenu(options: false)
        setMenuVisible(true)
    }

    func remove(_ sender: UIMenuController?) {
        js("removeThisHighlight()") { removedId in
            guard let removedId = removedId else { return }
            self.folioReader.delegate?.folioReaderHighlightProvider?(self.folioReader).folioReaderHighlight(self.folioReader, removedId: removedId)
        }
        createMenu(options: false)
        setMenuVisible(false)
    }

    @objc func highlight(_ sender: UIMenuController?) {
        js("highlightStringCFI('\(HighlightStyle.classForStyle(self.folioReader.currentHighlightStyle))')") { highlightAndReturn in
            print(highlightAndReturn)
            guard let jsonData = highlightAndReturn?.data(using: .utf8) else {
                return
            }
            self.handleHighlightReturn(jsonData)
        }
    }
    
    @objc func highlightWithNote(_ sender: UIMenuController?) {
        js("highlightStringWithNoteCFI('\(HighlightStyle.classForStyle(self.folioReader.currentHighlightStyle))')") { highlightAndReturn in
            print(highlightAndReturn)
            guard let jsonData = highlightAndReturn?.data(using: String.Encoding.utf8) else {
                return
            }

            self.handleHighlightReturn(jsonData, withNote: true)
        }
    }
    
    func handleHighlightReturn(_ jsonData: Data, withNote: Bool = false) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: jsonData, options: []) as? NSArray,
                  let dic = json.firstObject as? [String: String] else {
                throw HighlightError.runtimeError("no json result")
            }
            guard let startOffset = dic["startOffset"], let startOffsetInt = Int(startOffset) else {
                throw HighlightError.runtimeError("no start offset")
            }
            guard let endOffset = dic["endOffset"], let endOffsetInt = Int(endOffset) else {
                throw HighlightError.runtimeError("no end offset")
            }
            guard let prevHighlightLengthStart = dic["prevHighlightLengthStart"], let prevHighlightLengthStartInt = Int(prevHighlightLengthStart) else {
                throw HighlightError.runtimeError("no prevHighlightLengthStart")
            }
            guard let prevHighlightLengthEnd = dic["prevHighlightLengthEnd"], let prevHighlightLengthEndInt = Int(prevHighlightLengthEnd) else {
                throw HighlightError.runtimeError("no prevHighlightLengthEnd")
            }
            
            let highlight = Highlight()
            highlight.bookId = (self.book.name as NSString?)?.deletingPathExtension
            highlight.startOffset = startOffsetInt
            highlight.endOffset = endOffsetInt
            highlight.content = dic["content"]
            highlight.cfiStart = dic["cfiStart"]
            highlight.cfiEnd = dic["cfiEnd"]
            highlight.contentPost = dic["contentPost"]
            highlight.contentPre = dic["contentPre"]
            highlight.date = Date()
            highlight.highlightId = dic["id"]
            highlight.page = self.folioReader.readerCenter?.currentPageNumber ?? 0
            highlight.type = self.folioReader.currentHighlightStyle
            highlight.style = HighlightStyle.classForStyle(highlight.type)

            if prevHighlightLengthStartInt > 0,
               let cfiStart = highlight.cfiStart,
               let idx = cfiStart.index(of: ":") {
                let offsetIdx = cfiStart.index(after: idx)
                if let offset = Int(cfiStart[offsetIdx...]) {
                    highlight.cfiStart = String(cfiStart[..<offsetIdx]) + Int(offset + prevHighlightLengthStartInt).description
                }
            }
            if prevHighlightLengthEndInt > 0,
               let cfiEnd = highlight.cfiEnd,
               let idx = cfiEnd.index(of: ":") {
                let offsetIdx = cfiEnd.index(after: idx)
                if let offset = Int(cfiEnd[offsetIdx...]) {
                    highlight.cfiEnd = String(cfiEnd[..<offsetIdx]) + Int(offset + prevHighlightLengthEndInt).description
                }
            }
            
            highlight.encodeContents()
            
            let encoder = JSONEncoder()
            let serializedData = try encoder.encode(highlight)
            let encodedData = serializedData.base64EncodedString()
            self.js("injectHighlight('\(encodedData)')") { result in
                guard result == nil else {
                    self.folioReader.readerCenter?.presentAddHighlightError(result!)
                    return
                }
                if withNote {
                    self.folioReader.readerCenter?.presentAddHighlightNote(highlight, edit: false)
                } else {
                    self.folioReader.delegate?.folioReaderHighlightProvider?(self.folioReader).folioReaderHighlight(self.folioReader, added: highlight) { error in
                        guard error == nil else {
                            self.folioReader.readerCenter?.presentAddHighlightError(error!.localizedDescription)
                            return
                        }
                        
                        self.clearTextSelection()
                        self.setMenuVisible(false)
                    }
                }
            }
            
        } catch {
            
        }
    }
    
    @objc func updateHighlightNote (_ sender: UIMenuController?) {
        js("getHighlightId()") { highlightId in
            guard
                let highlightId = highlightId,
                let highlightNote = self.folioReader.delegate?.folioReaderHighlightProvider?(self.folioReader).folioReaderHighlight(self.folioReader, getById: highlightId)
            else { return }
            
            self.folioReader.readerCenter?.presentAddHighlightNote(highlightNote, edit: true)
            self.createMenu(options: false, onHighlight: false)
        }
    }

    @objc func define(_ sender: UIMenuController?) {
        js("getSelectedText()") { selectedText in
            guard let selectedText = selectedText else { return }

            self.setMenuVisible(false)
            self.clearTextSelection()

            let vc = UIReferenceLibraryViewController(term: selectedText)
            vc.view.tintColor = self.readerConfig.tintColor
            guard let readerContainer = self.readerContainer else { return }
            readerContainer.show(vc, sender: nil)
        }
    }

    @objc func lookup(_ sender: UIMenuController?) {
        js("getSelectedText()") { selectedText in
            guard let selectedText = selectedText else { return }
            guard let mDictView = self.mDictView else { return }

            self.setMenuVisible(false)
            self.clearTextSelection()

            mDictView.title = selectedText
            mDictView.view.tintColor = self.readerConfig.tintColor
            let nav = UINavigationController(rootViewController: mDictView)
            nav.navigationBar.isTranslucent = false

            guard let readerContainer = self.readerContainer else { return }
            readerContainer.show(nav, sender: nil)
        }
    }
    
    @objc func play(_ sender: UIMenuController?) {
        self.folioReader.readerAudioPlayer?.play()

        self.clearTextSelection()
    }

    open func setMDictView(mDictView: UIViewController) {
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

    func changeHighlightStyle(_ sender: UIMenuController?, style: HighlightStyle) {
        self.folioReader.currentHighlightStyle = style.rawValue

        js("setHighlightStyle('\(HighlightStyle.classForStyle(style.rawValue))')") { updateId in
            guard let updateId = updateId else { return }
            self.folioReader.delegate?.folioReaderHighlightProvider?(self.folioReader).folioReaderHighlight(self.folioReader, updateById: updateId, type: style)
        }
        
        //FIX: https://github.com/FolioReader/FolioReaderKit/issues/316
        setMenuVisible(false)
    }

    // MARK: - Create and show menu

    func createMenu(options: Bool, onHighlight: Bool = false) {
        guard (self.readerConfig.useReaderMenuController == true) else {
            return
        }

        //MARK: FIXME isShare is broken
        // isShare = options

        let colors = UIImage(readerImageNamed: "colors-marker")
        let share = UIImage(readerImageNamed: "share-marker")
        let remove = UIImage(readerImageNamed: "no-marker")
        let yellow = UIImage(readerImageNamed: "yellow-marker")
        let green = UIImage(readerImageNamed: "green-marker")
        let blue = UIImage(readerImageNamed: "blue-marker")
        let pink = UIImage(readerImageNamed: "pink-marker")
        let underline = UIImage(readerImageNamed: "underline-marker")

        let menuController = UIMenuController.shared

        let highlightItem = UIMenuItem(title: self.readerConfig.localizedHighlightMenu, action: #selector(highlight(_:)))
        let highlightNoteItem = UIMenuItem(title: self.readerConfig.localizedHighlightNote, action: #selector(highlightWithNote(_:)))
        let editNoteItem = UIMenuItem(title: self.readerConfig.localizedHighlightNote, action: #selector(updateHighlightNote(_:)))
        let playAudioItem = UIMenuItem(title: self.readerConfig.localizedPlayMenu, action: #selector(play(_:)))
        let defineItem = UIMenuItem(title: self.readerConfig.localizedDefineMenu, action: #selector(define(_:)))
        let mDictItem = UIMenuItem(title: self.readerConfig.localizedMDictMenu, action: #selector(lookup(_:)))
        
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
            
            isShare = false
        } else if isColors {
            // menu for selecting highlight color
            menuItems = [yellowItem, greenItem, blueItem, pinkItem, underlineItem]
        } else {
            // default menu
            menuItems = [highlightItem, defineItem, highlightNoteItem]
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
    }
    
    open func setMenuVisible(_ menuVisible: Bool, animated: Bool = true, andRect rect: CGRect = CGRect.zero) {
        if menuVisible == false {
            UIMenuController.shared.setMenuVisible(menuVisible, animated: animated)
        }
        
        if !menuVisible && isShare || !menuVisible && isColors {
            isColors = false
            isShare = false
        }
        
        if menuVisible  {
            if !rect.equalTo(CGRect.zero) {
                UIMenuController.shared.setTargetRect(rect, in: self)
            }
        } else {
            self.createMenu(options: false, onHighlight: false)
        }
        
        UIMenuController.shared.setMenuVisible(menuVisible, animated: animated)
    }
    
    // MARK: - Java Script Bridge
    
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
            if  let nsError = error as? NSError,
                let url = nsError.userInfo["WKJavaScriptExceptionSourceURL"] as? NSURL,
                url.absoluteString == "undefined"
            {
                // skip debugPrint - html hasn't loaded yet
            } else if let error = error {
                debugPrint("evaluateJavaScript(\(script)) returned an error:", error)
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
        case .vertical, .defaultVertical, .horizontalWithVerticalContent:
            scrollView.isPagingEnabled = false
            cssOverflowProperty = "scroll"
            scrollView.bounces = true
            break
        case .horizontal:
            scrollView.isPagingEnabled = true
            cssOverflowProperty = "-webkit-paged-x"
            scrollView.bounces = false
            break
        }
    }
}
