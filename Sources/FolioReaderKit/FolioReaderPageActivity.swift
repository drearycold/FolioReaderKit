//
//  FolioReaderPageProgress.swift
//  FolioReaderKit
//
//  Created by Peter Lee on 2023/7/28.
//

import Foundation

import UIKit

class FolioReaderPageActivity: UIView {
    let folioReader: FolioReader
    let loadingView = UIActivityIndicatorView()
    let loadingLabelView = UILabel()

    var adView: UIView? = nil
    private var constraintsWithAdView = [NSLayoutConstraint]()
    private var constraintsWithoutAdView = [NSLayoutConstraint]()
    
    init(folioReader: FolioReader) {
        self.folioReader = folioReader
        super.init(frame: .zero)
        
        loadingView.style = folioReader.isNight(.white, .gray)
        loadingView.startAnimating()
        loadingView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(loadingView)
        
        NSLayoutConstraint.activate([
            loadingView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
        ])
        
        loadingLabelView.text = "Initializing..."
         loadingLabelView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(loadingLabelView)
        NSLayoutConstraint.activate([
            loadingLabelView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
        ])
        
        constraintsWithoutAdView = [
            loadingLabelView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            loadingView.centerYAnchor.constraint(equalTo: loadingLabelView.centerYAnchor, constant: 30),
        ]
        NSLayoutConstraint.activate(constraintsWithoutAdView)
    }
    
    func activate(_ status: String, _ showAd: Bool) {
        defer {
            self.isHidden = false
        }
        
        if !showAd {
            NSLayoutConstraint.deactivate(constraintsWithAdView.filter({ $0.isActive }))
            NSLayoutConstraint.deactivate(constraintsWithoutAdView.filter({ $0.isActive }))
            NSLayoutConstraint.activate(constraintsWithoutAdView)
            
            return
        }
        guard let adView = adView else { return }

        self.addSubview(adView)
        
        loadingLabelView.text = status
        loadingView.startAnimating()
        
        NSLayoutConstraint.deactivate(constraintsWithAdView.filter({ $0.isActive }))
        NSLayoutConstraint.deactivate(constraintsWithoutAdView.filter({ $0.isActive }))
        
        if folioReader.readerCenter?.menuBarController.presentingViewController != nil {
            constraintsWithAdView = [
                adView.topAnchor.constraint(equalTo: self.topAnchor, constant: 70),  //navbar + padding
                loadingLabelView.topAnchor.constraint(equalTo: adView.bottomAnchor, constant: 32),
                loadingView.topAnchor.constraint(equalTo: loadingLabelView.bottomAnchor, constant: 16),
            ]
        } else {
            constraintsWithAdView = [
                adView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
                loadingLabelView.topAnchor.constraint(equalTo: adView.bottomAnchor, constant: 32),
                loadingView.topAnchor.constraint(equalTo: loadingLabelView.bottomAnchor, constant: 16),
            ]
        }
        
        NSLayoutConstraint.activate([
            adView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            loadingLabelView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            loadingView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
        ])
        NSLayoutConstraint.activate(constraintsWithAdView)
        
        loadingView.color = folioReader.readerConfig?.themeModeTextColor[folioReader.themeMode]
        loadingLabelView.textColor = folioReader.readerConfig?.themeModeTextColor[folioReader.themeMode]
       
        self.backgroundColor = folioReader.readerConfig?.themeModeBackground[folioReader.themeMode].withAlphaComponent(0.9)
    }
    
    func deactivate() {
        adView?.removeFromSuperview()
        adView = nil
        
        self.isHidden = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
