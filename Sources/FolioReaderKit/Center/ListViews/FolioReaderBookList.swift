//
//  FolioReaderBookList.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 15/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import AEXML

/// Table Of Contents delegate
@objc protocol FolioReaderBookListDelegate: AnyObject {
    /**
     Notifies when the user selected some item on menu.
     */
    func bookList(_ bookList: FolioReaderBookList, didSelectRowAtIndexPath indexPath: IndexPath, withTocReference reference: FRTocReference)

    /**
     Notifies when book list did totally dismissed.
     */
    func bookList(didDismissedBookList bookList: FolioReaderBookList)
}

class FolioReaderBookList: UICollectionViewController {
    weak var delegate: FolioReaderBookListDelegate?
    fileprivate var tocItems = [FRTocReference]()
    fileprivate var sectionTocItems = [(FRTocReference, [FRTocReference])]()
    fileprivate var tocPositions = [FRTocReference: FolioReaderReadPosition]()
    fileprivate var book: FRBook
    fileprivate var readerConfig: FolioReaderConfig
    fileprivate var folioReader: FolioReader
    fileprivate var highlightResourceIds = Set<String>()
    fileprivate var layout = UICollectionViewFlowLayout()
    fileprivate var coverImage: UIImage?
    
    init(folioReader: FolioReader, readerConfig: FolioReaderConfig, book: FRBook, delegate: FolioReaderBookListDelegate?) {
        self.readerConfig = readerConfig
        self.folioReader = folioReader
        self.delegate = delegate
        self.book = book
        
        layout.itemSize = .init(width: 300, height: 400)
        layout.minimumInteritemSpacing = 0
        layout.scrollDirection = .vertical
        
        super.init(collectionViewLayout: layout)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init with coder not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Register cell classes
        self.collectionView.register(FolioReaderBookListCell.self, forCellWithReuseIdentifier: kReuseCellIdentifier)
        self.collectionView.register(FolioReaderBookListHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: kReuseHeaderFooterIdentifier)
        self.collectionView.backgroundColor = self.readerConfig.themeModeMenuBackground[self.folioReader.themeMode]

        // Create TOC list
        switch self.folioReader.structuralStyle {
        case .bundle:
            let rootTocLevel = self.folioReader.structuralTrackingTocLevel.rawValue
            self.sectionTocItems = self.book.flatTableOfContents.reduce(into: [], { partialResult, tocRef in
                guard let tocLevel = tocRef.level,
                      tocLevel == rootTocLevel - 1 else { return }
                
                self.tocItems.append(tocRef)
                
                guard let tocParent = tocRef.parent else { return }
                
                if partialResult.last?.0 != tocParent {
                    partialResult.append((tocParent, []))
                }
                partialResult[partialResult.endIndex - 1].1.append(tocRef)
            })
            
            guard let bookId = self.folioReader.readerConfig?.identifier else { return }
            self.tocPositions = self.tocItems.reduce(into: [:], { partialResult, tocRef in
                let bookTocIndexPathRow = self.book.findPageByResource(tocRef)
                let bookTocPageNumber = bookTocIndexPathRow + 1
                guard let readPosition = self.folioReader.delegate?.folioReaderReadPositionProvider?(self.folioReader).folioReaderReadPosition(self.folioReader, bookId: bookId, by: bookTocPageNumber)
                else { return }
                partialResult[tocRef] = readPosition
            })
        case .topic:
            self.sectionTocItems = self.book.flatTableOfContents.reduce(into: [], { partialResult, tocRef in
                guard tocRef.children.isEmpty
                        || tocRef.children.allSatisfy({ $0.resource?.href == tocRef.resource?.href })
                else { return }
                
                guard self.tocItems.last != tocRef.parent else { return }
                
                self.tocItems.append(tocRef)
                
                guard let tocParent = tocRef.parent else { return }
                
                if partialResult.last?.0 != tocParent {
                    partialResult.append((tocParent, []))
                }
                partialResult[partialResult.endIndex - 1].1.append(tocRef)
            })
            
            guard let bookId = self.folioReader.readerConfig?.identifier else { return }
            self.tocPositions = self.tocItems.reduce(into: [:], { partialResult, tocRef in
                let bookTocIndexPathRow = self.book.findPageByResource(tocRef)
                let bookTocPageNumber = bookTocIndexPathRow + 1
                guard let readPosition = self.folioReader.delegate?.folioReaderReadPositionProvider?(self.folioReader).folioReaderReadPosition(self.folioReader, bookId: bookId, by: bookTocPageNumber)
                else { return }
                partialResult[tocRef] = readPosition
            })
        case .atom:
            break
        }
        
        if self.folioReader.structuralStyle == .bundle {
            //prepare cover image
            let opfURL = URL(fileURLWithPath: book.opfResource.href, isDirectory: false)
            
            guard let bookId = self.folioReader.readerConfig?.identifier,
                  let imgSrc = book.coverImage?.href,
                  let archive = book.epubArchive,
                  let imgEntry = archive[URL(fileURLWithPath: imgSrc, relativeTo: opfURL).path.trimmingCharacters(in: ["/"])]
            else { return }
            
            let tempFile = URL(
                fileURLWithPath: imgEntry.path,
                relativeTo: FileManager.default.temporaryDirectory.appendingPathComponent(bookId, isDirectory: true))
            let tempDir = tempFile.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            
            if FileManager.default.fileExists(atPath: tempFile.path) == false {
                let _ = try? archive.extract(imgEntry, to: tempFile)
            }
            
            self.coverImage = UIImage(contentsOfFile: tempFile.path)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        highlightResourceIds.removeAll()
        
        guard let currentPage = self.folioReader.readerCenter?.currentPage else { return }
        
        highlightResourceIds.formUnion(currentPage.getChapterTocReferences(for: .zero, by: .zero).compactMap { $0.resource?.id })
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Jump to the current book
        delay(0.2) {
            guard let index = self.tocItems.firstIndex(where: { self.highlightResourceIds.contains($0.resource?.id ?? "___NIL___") }) else { return }
            guard let indexPath = { () -> IndexPath? in
            switch self.folioReader.currentNavigationMenuBookListSyle {
            case .Grid:
                return IndexPath(row: index, section: 0)
            case .List:
                if self.sectionTocItems.isEmpty {
                    return IndexPath(row: index, section: 0)
                } else {
                    let tocRef = self.tocItems[index]
                    guard let tocParent = tocRef.parent,
                          let section = self.sectionTocItems.firstIndex(where: { $0.0 == tocParent }),
                          let row = self.sectionTocItems[section].1.firstIndex(of: tocRef)
                    else { return nil }
                    return IndexPath(row: row, section: section)
                }
            }
            }() else { return }
            self.collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
        }
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        switch self.folioReader.currentNavigationMenuBookListSyle {
        case .Grid:
            let minWidth = 185.0
            
            let itemCount = floor(self.collectionView.frame.size.width / minWidth)
            let itemWidth = floor((self.collectionView.frame.size.width - layout.minimumInteritemSpacing*(itemCount-1)) / itemCount)
            let itemHeight = itemWidth * 1.333 + 80
            layout.itemSize = .init(width: itemWidth, height: itemHeight)
            layout.minimumLineSpacing = 16
            layout.headerReferenceSize = .zero
        case .List:
            let itemWidth = self.collectionView.frame.size.width
            let itemHeight = 64.0
            layout.itemSize = .init(width: itemWidth, height: itemHeight)
            layout.minimumLineSpacing = 0
            if self.folioReader.structuralTrackingTocLevel == .level1 {
                layout.headerReferenceSize = .zero
            } else {
                layout.headerReferenceSize = .init(width: 200, height: 40)
            }
        }
    }

    // MARK: - collection view data source
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        switch self.folioReader.currentNavigationMenuBookListSyle {
        case .Grid:
            return 1
        case .List:
            return sectionTocItems.isEmpty ? 1 : sectionTocItems.count
        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch self.folioReader.currentNavigationMenuBookListSyle {
        case .Grid:
            return tocItems.count
        case .List:
            return sectionTocItems.isEmpty ? tocItems.count : sectionTocItems[section].1.count
        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: kReuseCellIdentifier, for: indexPath) as! FolioReaderBookListCell

        cell.setup(withConfiguration: self.readerConfig)
        guard let tocReference = { () -> FRTocReference? in
            switch self.folioReader.currentNavigationMenuBookListSyle{
            case .Grid:
                return tocItems[indexPath.row]
            case .List:
                return sectionTocItems.isEmpty ? tocItems[indexPath.row] : sectionTocItems[indexPath.section].1[indexPath.row]
            }
        }()
        else { return cell }

        cell.titleLabel.text = tocReference.title.trimmingCharacters(in: .whitespacesAndNewlines)

        // Add audio duration for Media Ovelay
        if let resource = tocReference.resource {
            if let mediaOverlay = resource.mediaOverlay {
                let duration = self.book.duration(for: "#"+mediaOverlay)

                if let durationFormatted = (duration != nil ? duration : "")?.clockTimeToMinutesString() {
                    cell.titleLabel.text = (cell.titleLabel.text ?? "") + (duration != nil ? (" - " + durationFormatted) : "")
                }
            }
        }

        // Mark current reading book
        cell.titleLabel.textColor = highlightResourceIds.contains(tocReference.resource?.id ?? "___NIL___") ? self.readerConfig.menuTextColorSelected : self.readerConfig.menuTextColor
        
        cell.positionLabel.textColor = highlightResourceIds.contains(tocReference.resource?.id ?? "___NIL___") ? self.readerConfig.menuTextColorSelected : self.readerConfig.menuTextColor
        cell.positionLabel.font = UIFont(name: "Avenir-Light", size: 14.0)

        cell.percentageLabel.textColor = highlightResourceIds.contains(tocReference.resource?.id ?? "___NIL___") ? self.readerConfig.menuTextColorSelected : self.readerConfig.menuTextColor
        cell.percentageLabel.font = UIFont(name: "Avenir-Light", size: 11.0)
        
        if let position = tocPositions[tocReference] {
            cell.positionLabel.text = position.chapterName
            let formatter = NumberFormatter()
            formatter.numberStyle = .percent
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
            cell.percentageLabel.text = (formatter.string(from: NSNumber(value: position.chapterProgress / 100.0)) ?? "0.0%") + " / " + (formatter.string(from: NSNumber(value: position.bookProgress / 100.0)) ?? "0.0%")
        } else {
            cell.positionLabel.text = "Not Started"
            cell.percentageLabel.text = ""
        }
        
        cell.layoutMargins = UIEdgeInsets.zero
        cell.preservesSuperviewLayoutMargins = false
        
        
        cell.positionLabel.isHidden = false
        cell.percentageLabel.isHidden = false
        cell.contentView.backgroundColor = .clear
        cell.backgroundColor = UIColor.clear
        
        cell.coverImage.image = nil
        let titleLabelText = cell.titleLabel.text
        
        guard self.folioReader.currentNavigationMenuBookListSyle == .Grid else { return cell }
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let bookId = self.folioReader.readerConfig?.identifier,
                  let archive = self.book.threadEpubArchive,
                  let resource = tocReference.resource,
                  let tocPage = resource.spineIndices.first
            else { return }
            
            let opfURL = URL(fileURLWithPath: self.book.opfResource.href, isDirectory: false)
            var imgNodes = [AEXMLElement]()
            var coverURL = opfURL
            
            var image: UIImage?
            for page in (max(0,tocPage-1) ... tocPage).reversed() {
                let resource = self.book.spine.spineReferences[page].resource
                let entryURL = URL(fileURLWithPath: resource.href, isDirectory: false, relativeTo: opfURL)
                guard let entry = archive[entryURL.path.trimmingCharacters(in: ["/"])] else { continue }
                
                var entryData = Data()
                let _ = try? archive.extract(entry, consumer: { data in
                    entryData.append(data)
                })
                guard let xmlDoc = try? AEXMLDocument(xml: entryData) else { continue }
                
                imgNodes = xmlDoc.allDescendants { $0.name == "img" || $0.name == "IMG" || $0.name == "image" || $0.name == "IMAGE" }
                
                guard imgNodes.isEmpty == false else { continue }
                
                coverURL = entryURL
                
                guard let imgSrc = imgNodes.first?.attributes["src"] ?? imgNodes.first?.attributes["xlink:href"],
                      let imgEntry = archive[URL(fileURLWithPath: imgSrc, relativeTo: coverURL).path.trimmingCharacters(in: ["/"])]
                else { continue }
                
                let tempFile = URL(
                    fileURLWithPath: imgEntry.path,
                    relativeTo: FileManager.default.temporaryDirectory.appendingPathComponent(bookId, isDirectory: true))
                let tempDir = tempFile.deletingLastPathComponent()
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
                
                if FileManager.default.fileExists(atPath: tempFile.path) == false {
                    let _ = try? archive.extract(imgEntry, to: tempFile)
                }
                
                guard let tempImage = UIImage(contentsOfFile: tempFile.path),
                      tempImage.size.width >= 250,
                      tempImage.size.height >= 300 else { continue }
                
                image = tempImage
                break
            }
            
            DispatchQueue.main.async {
                guard titleLabelText == cell.titleLabel.text,
                      cell.coverImage.image == nil
                else { return }
                cell.coverImage.image = image ?? self.coverImage
            }
        }
        
        return cell
    }

    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: kReuseHeaderFooterIdentifier, for: indexPath)
        
        guard let cell = headerView as? FolioReaderBookListHeader else { return headerView }
        var sectionToc: FRTocReference? = self.sectionTocItems[safe: indexPath.section]?.0
        var titles = [String]()
        while let title = sectionToc?.title {
            titles.append(title)
            sectionToc = sectionToc?.parent
        }
        cell.label.text = titles.reversed().joined(separator: " - ")
        
        return cell
    }
    
    // MARK: - Table view delegate

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        let tocReference = { () -> FRTocReference in
            switch self.folioReader.currentNavigationMenuBookListSyle {
            case .Grid:
                return self.tocItems[indexPath.row]
            case .List:
                return self.sectionTocItems.isEmpty ? self.tocItems[indexPath.row] : self.sectionTocItems[indexPath.section].1[indexPath.row]
            }
        }()
        if let position = tocPositions[tocReference] {
            self.folioReader.readerCenter?.currentWebViewScrollPositions[position.pageNumber - 1] = position
        }
        delegate?.bookList(self, didSelectRowAtIndexPath: indexPath, withTocReference: tocReference)
        
        collectionView.deselectItem(at: indexPath, animated: true)
        dismiss { 
            self.delegate?.bookList(didDismissedBookList: self)
        }
    }
}

extension FolioReaderBookList {
    public func pickRandomTopic() {
        guard let index = self.tocItems.indices.randomElement(),
              let section = self.sectionTocItems.indices.randomElement(),
              let sectionItem = self.sectionTocItems[section].1.indices.randomElement()
        else { return }
        
        if sectionTocItems.isEmpty {
            self.collectionView(self.collectionView, didSelectItemAt: IndexPath(row: index, section: 0))
        } else {
            self.collectionView(self.collectionView, didSelectItemAt: IndexPath(row: sectionItem, section: section))
        }
    }
}
