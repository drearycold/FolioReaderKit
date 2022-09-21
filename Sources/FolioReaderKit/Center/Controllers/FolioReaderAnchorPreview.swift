//
//  FolioReaderAnchorPreview.swift
//  FolioReaderKit
//
//  Created by Peter on 2022/8/26.
//

import Foundation
import SwiftSoup

class FolioReaderAnchorPreview: UIViewController {
    let folioReader: FolioReader
    let anchorURL: URL
    
    let navBar = UIView()
    
    let gotoButton = UIButton()
    let anchorLabel = UITextView()
    
    let anchorBackgroundView = UIView()
    
    let tapGeatureRecognizer = UITapGestureRecognizer()
    
    let snippetTestRegex = try? NSRegularExpression(pattern: "^\\[\\d+\\]$")
    
    public init(_ folioReader: FolioReader, _ anchorURL: URL) {
        self.folioReader = folioReader
        self.anchorURL = anchorURL
        
        super.init(nibName: nil, bundle: Bundle.frameworkBundle())
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        anchorBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        anchorBackgroundView.backgroundColor = folioReader.readerConfig?.themeModeNavBackground[folioReader.themeMode]
        
        self.view.addSubview(anchorBackgroundView)
        
        NSLayoutConstraint.activate([
            anchorBackgroundView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            anchorBackgroundView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            anchorBackgroundView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            anchorBackgroundView.heightAnchor.constraint(equalToConstant: 160)
        ])
        
        anchorLabel.translatesAutoresizingMaskIntoConstraints = false
        anchorLabel.isEditable = false
        anchorLabel.font = UIFont(name: folioReader.currentFont, size: CGFloat(folioReader.currentFontSizeOnly - 2))
        anchorLabel.textColor = folioReader.readerConfig?.themeModeTextColor[folioReader.themeMode]
        anchorLabel.backgroundColor = .clear
        
        self.view.addSubview(anchorLabel)
        
        NSLayoutConstraint.activate([
            anchorLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            anchorLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16),
            anchorLabel.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: -10),
            anchorLabel.heightAnchor.constraint(equalToConstant: 110)
        ])
        
        
        navBar.translatesAutoresizingMaskIntoConstraints = false
        navBar.layer.cornerRadius = 4
        navBar.layer.borderColor = UIColor(white: 0.5, alpha: 0.2).cgColor
        navBar.layer.borderWidth = 1
        self.view.addSubview(navBar)
        NSLayoutConstraint.activate([
            navBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            navBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            navBar.bottomAnchor.constraint(equalTo: anchorLabel.topAnchor),
            navBar.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        gotoButton.translatesAutoresizingMaskIntoConstraints = false
        gotoButton.setTitle("Jump", for: .normal)
        gotoButton.setTitleColor(folioReader.readerConfig?.tintColor, for: .normal)
        gotoButton.addTarget(self, action: #selector(gotoButtonAction(_:)), for: .primaryActionTriggered)
        
        navBar.addSubview(gotoButton)
        
        NSLayoutConstraint.activate([
            gotoButton.trailingAnchor.constraint(equalTo: navBar.trailingAnchor, constant: -8),
            gotoButton.widthAnchor.constraint(equalToConstant: 60),
            gotoButton.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            gotoButton.heightAnchor.constraint(equalTo: navBar.heightAnchor)
        ])
        
        tapGeatureRecognizer.addTarget(self, action: #selector(tapGesture(_:)))
        
        self.view.addGestureRecognizer(tapGeatureRecognizer)
        
        anchorLabel.text = "Before Locating"
        
        let entryPath = anchorURL.pathComponents.dropFirst(2).joined(separator: "/")
        var entryData = Data()
        
        guard let fragment = anchorURL.fragment,
              let archive = folioReader.readerContainer?.book.epubArchive,
              let entry = archive[entryPath],
              let _ = try? archive.extract(entry, consumer: { entryData.append($0) }),
              let xmlString = String(data: entryData, encoding: .utf8),
              let soupDoc = try? SwiftSoup.parse(xmlString),
              let soupElement = try? soupDoc.getElementById(fragment),
              var snippet = try? soupElement.text(trimAndNormaliseWhitespace: true)
        else { return }
        
        if snippet.isEmpty
            || (snippetTestRegex?.matches(in: snippet, options: [], range: NSMakeRange(0, snippet.count)).isEmpty == false) {
            var elements = [soupElement as Node]
            while let sibling = elements.last?.nextSibling() {
                guard sibling.hasAttr("id") == false else { break }
                if let element = sibling as? Element,
                   let elementsWithID = try? element.getElementsByAttribute("id"),
                   elementsWithID.count > 0 {
                    break
                }
                elements.append(sibling)
            }
            
            snippet = elements.compactMap({ node -> String? in
                if let element = node as? Element {
                    return try? element.text(trimAndNormaliseWhitespace: true)
                }
                if let textNode = node as? TextNode {
                    return textNode.text()
                }
                return nil
            }).joined(separator: " ")
        }
        
        anchorLabel.text = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        anchorLabel.sizeToFit()
    }
    
    @objc func gotoButtonAction(_ sender: UIButton) {
        let entryPath = anchorURL.pathComponents.dropFirst(2).joined(separator: "/")
        guard let readerCenter = folioReader.readerCenter,
              let spineIndex = readerCenter.book.spine.spineReferences.firstIndex(where: { entryPath.contains($0.resource.href) }),
              let fragment = anchorURL.fragment
        else { return }
        readerCenter.currentPage?.pushNavigateWebViewScrollPositions()
        readerCenter.changePageWith(page: spineIndex + 1, andFragment: fragment, animated: true) {
            self.dismiss()
        }
        
    }
    
    @objc func tapGesture(_ sender: UITapGestureRecognizer) {
        guard sender.state == .ended else { return }
        
        guard sender.location(in: self.view).y < self.navBar.frame.minY else { return }
        
        self.dismiss()
    }
}
