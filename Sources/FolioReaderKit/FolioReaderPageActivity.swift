//
//  FolioReaderPageProgress.swift
//  FolioReaderKit
//
//  Created by Peter Lee on 2023/7/28.
//

import Foundation

import UIKit

/// What a page is busy with while `FolioReaderPage.layoutAdapting` is set.
enum PageLayoutStage {
    // Loading a chapter: the cell is set up, then `didFinish` starts the layout chain.
    case initializing, structure
    // Steps of the layout chain, which also run on their own when a setting changes.
    case layout, style, annotations, almostReady, finalizing
    // Laying out a loaded page again.
    case scrollDirection, viewerLayout, transition, profile

    /// Starts loading a chapter, as opposed to laying out a loaded one again.
    var isLoading: Bool {
        self == .initializing || self == .structure
    }
}

/// Covers a page while it loads or is laid out again, so its intermediate layouts don't show.
class FolioReaderPageActivity: UIView {
    let folioReader: FolioReader
    let loadingView = UIActivityIndicatorView(style: .medium)
    let loadingLabelView = UILabel()
    private let statusView: UIStackView

    var adView: UIView? = nil
    private var constraintsWithAdView = [NSLayoutConstraint]()
    private var constraintsWithoutAdView = [NSLayoutConstraint]()

    /// Whether the overlay is up for a chapter load. Its stages are followed by the layout chain,
    /// which keeps the load's message instead of switching to the relayout one at every step.
    private var isLoadingChapter = false

    init(folioReader: FolioReader) {
        self.folioReader = folioReader
        self.statusView = UIStackView(arrangedSubviews: [loadingView, loadingLabelView])
        super.init(frame: .zero)

        loadingLabelView.font = UIFont.preferredFont(forTextStyle: .callout)
        loadingLabelView.adjustsFontForContentSizeCategory = true
        loadingLabelView.numberOfLines = 0
        loadingLabelView.textAlignment = .center

        statusView.axis = .vertical
        statusView.alignment = .center
        statusView.spacing = 12
        statusView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(statusView)

        NSLayoutConstraint.activate([
            statusView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            statusView.leadingAnchor.constraint(greaterThanOrEqualTo: self.layoutMarginsGuide.leadingAnchor, constant: 16),
            statusView.trailingAnchor.constraint(lessThanOrEqualTo: self.layoutMarginsGuide.trailingAnchor, constant: -16),
        ])
        constraintsWithoutAdView = [
            statusView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
        ]
        NSLayoutConstraint.activate(constraintsWithoutAdView)

        self.isHidden = true
    }

    func activate(_ stage: PageLayoutStage, _ showAd: Bool) {
        let wasHidden = self.isHidden
        if stage.isLoading || wasHidden {
            isLoadingChapter = stage.isLoading
        }
        applyTheme()
        layoutStatus(showAd: showAd)
        self.isHidden = false

        if wasHidden {
            fadeIn()
        }
    }

    func deactivate() {
        adView?.removeFromSuperview()
        adView = nil

        layer.removeAllAnimations()
        statusView.layer.removeAllAnimations()
        loadingView.stopAnimating()
        self.isHidden = true
    }

    /// Colors follow the page theme, which can change between activations; the background is
    /// opaque so the status never sits on top of the page's text.
    private func applyTheme() {
        let config = folioReader.readerConfig
        let theme = folioReader.themeMode
        let textColor = config?.themeModeTextColor[safe: theme] ?? .label

        self.backgroundColor = config?.themeModeBackground[safe: theme] ?? .systemBackground
        loadingLabelView.textColor = textColor
        loadingView.color = textColor
        loadingLabelView.text = isLoadingChapter
            ? config?.localizedPageLoading ?? "Loading…"
            : config?.localizedPageRelayout ?? "Updating layout…"
    }

    /// The overlay fades in only when the work takes long enough to read the status. Pages stay
    /// visible while they are laid out again, so a quick relayout (a setting change) leaves the page
    /// as it is instead of blinking to the background or flashing text that is gone before it can be
    /// read. The view stays opaque to touches meanwhile, as it always was.
    private func fadeIn() {
        let background = backgroundColor
        layer.removeAllAnimations()
        statusView.layer.removeAllAnimations()
        backgroundColor = background?.withAlphaComponent(0)
        statusView.alpha = 0
        loadingView.startAnimating()
        UIView.animate(withDuration: 0.2, delay: 0.3, options: [.allowUserInteraction], animations: {
            self.backgroundColor = background
            self.statusView.alpha = 1
        })
    }

    private func layoutStatus(showAd: Bool) {
        NSLayoutConstraint.deactivate(constraintsWithAdView.filter({ $0.isActive }))
        NSLayoutConstraint.deactivate(constraintsWithoutAdView.filter({ $0.isActive }))

        guard showAd, let adView = adView else {
            NSLayoutConstraint.activate(constraintsWithoutAdView)
            return
        }

        self.addSubview(adView)

        if folioReader.readerCenter?.menuBarController.presentingViewController != nil {
            constraintsWithAdView = [
                adView.topAnchor.constraint(equalTo: self.topAnchor, constant: 70),  //navbar + padding
                statusView.topAnchor.constraint(equalTo: adView.bottomAnchor, constant: 32),
            ]
        } else {
            constraintsWithAdView = [
                adView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
                statusView.topAnchor.constraint(equalTo: adView.bottomAnchor, constant: 32),
            ]
        }

        NSLayoutConstraint.activate([
            adView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
        ])
        NSLayoutConstraint.activate(constraintsWithAdView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
