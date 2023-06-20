//
//  FolioReaderBookListCell.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 07/05/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit

class FolioReaderBookListCell: UICollectionViewCell {
    let coverImage = UIImageView()
    let titleLabel = UILabel()
    let positionLabel = UILabel()
    let percentageLabel = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.titleLabel.font = UIFont(name: "Avenir", size: 19.0)
        self.titleLabel.adjustsFontSizeToFitWidth = true
        self.titleLabel.lineBreakMode = .byWordWrapping
        self.titleLabel.numberOfLines = 1

        self.coverImage.contentMode = .scaleAspectFit

        self.positionLabel.lineBreakMode = .byWordWrapping
        self.positionLabel.numberOfLines = 1
        
        self.percentageLabel.lineBreakMode = .byWordWrapping
        self.percentageLabel.numberOfLines = 1
        self.percentageLabel.textAlignment = .right

        self.contentView.addSubview(self.coverImage)
        self.contentView.addSubview(self.titleLabel)
        self.contentView.addSubview(self.positionLabel)
        self.contentView.addSubview(self.percentageLabel)
    }
    
    func setup(withConfiguration readerConfig: FolioReaderConfig) {
        if self.frame.height > 200 {
            self.titleLabel.frame = .init(x: 16, y: 8, width: self.frame.width - 16, height: 32)
            self.titleLabel.textAlignment = .center

            self.coverImage.frame = .init(x: 16, y: 40, width: self.frame.width - 32, height: self.frame.height - 80)
            
            self.positionLabel.frame = .init(
                x: 16,
                y: self.coverImage.frame.maxY + 2,
                width: self.frame.width - 32 - 80,
                height: 28
            )
            self.positionLabel.textAlignment = .left
            
            self.percentageLabel.frame = .init(
                x: self.frame.width - 16 - 80,
                y: self.coverImage.frame.maxY + 2,
                width: 80,
                height: 28
            )
        } else {
            self.titleLabel.frame = .init(
                x: 16,
                y: 4,
                width: self.frame.width - 120 - 16 - 8,
                height: 56
            )
            self.titleLabel.font = UIFont(name: "Avenir", size: 18.0)
            self.titleLabel.textAlignment = .left
            self.titleLabel.numberOfLines = 2
            self.titleLabel.lineBreakMode = .byWordWrapping
            self.titleLabel.adjustsFontSizeToFitWidth = true

            self.coverImage.frame = .zero
            
            self.positionLabel.frame = .init(
                x: self.frame.width - 120 - 16 + 8,
                y: 2,
                width: 120 - 8,
                height: 40
            )
            self.positionLabel.textAlignment = .right
            self.positionLabel.numberOfLines = 2
            self.positionLabel.lineBreakMode = .byWordWrapping
            self.positionLabel.adjustsFontSizeToFitWidth = true
            
            if #available(iOS 14.0, *) {
                self.titleLabel.lineBreakStrategy = .pushOut
                self.positionLabel.lineBreakStrategy = .pushOut
            } else {
                // Fallback on earlier versions
            }
            
            
            self.percentageLabel.frame = .init(
                x: self.frame.width - 120 - 16,
                y: self.positionLabel.frame.maxY + 4,
                width: 120,
                height: 16
            )
        }
        
        self.titleLabel.textColor = readerConfig.menuTextColor
        self.positionLabel.textColor = readerConfig.menuTextColor
        self.percentageLabel.textColor = readerConfig.menuTextColor
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("storyboards are incompatible with truth and beauty")
    }
}

class FolioReaderBookListHeader: UICollectionViewCell {
    let label = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.label.frame = .init(x: 8, y: 4, width: frame.width-16, height: 32)
        self.contentView.addSubview(label)
        
        self.contentView.backgroundColor = .init(white: 0.7, alpha: 0.2)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
