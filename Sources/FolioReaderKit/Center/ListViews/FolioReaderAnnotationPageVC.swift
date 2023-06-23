//
//  PageViewController.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 14/07/16.
//  Copyright © 2016 FolioReader. All rights reserved.
//

import UIKit

class FolioReaderAnnotationPageVC: UIPageViewController {

    var segmentedControl: UISegmentedControl!
    var viewList = [UIViewController]()
    var segmentedControlItems = [String]()
    
    var viewControllerZero: UIViewController!
    var viewControllerOne: UIViewController!
    var viewControllerTwo: UIViewController!

    var index: Int
    fileprivate var readerConfig: FolioReaderConfig
    fileprivate var folioReader: FolioReader

    // MARK: Init

    init(folioReader: FolioReader, readerConfig: FolioReaderConfig) {
        self.folioReader = folioReader
        self.readerConfig = readerConfig
        self.index = self.folioReader.currentAnnotationMenuIndex
        super.init(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)

        self.edgesForExtendedLayout = UIRectEdge()
        self.extendedLayoutIncludesOpaqueBars = true
    }

    required init?(coder: NSCoder) {
        fatalError("storyboards are incompatible with truth and beauty")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        segmentedControl = UISegmentedControl(items: segmentedControlItems)
        segmentedControl.addTarget(self, action: #selector(FolioReaderAnnotationPageVC.didSwitchMenu(_:)), for: UIControl.Event.valueChanged)
        segmentedControl.selectedSegmentIndex = index
//        segmentedControl.setWidth(100, forSegmentAt: 0)
//        segmentedControl.setWidth(100, forSegmentAt: 1)
        self.navigationItem.titleView = segmentedControl

        viewList = [viewControllerOne, viewControllerTwo]

        viewControllerOne.didMove(toParent: self)
        viewControllerTwo.didMove(toParent: self)
        
        if (self.folioReader.readerCenter?.tempRefText) != nil {
            viewList.insert(viewControllerZero, at: 0)
            viewControllerZero.didMove(toParent: self)
        }

        self.delegate = self
        self.dataSource = self

        self.view.backgroundColor = UIColor.white
        if index >= viewList.count {
            index = 0
        }
        self.setViewControllers([viewList[index]], direction: .forward, animated: false, completion: nil)

        // FIXME: This disable scroll because of highlight swipe to delete, if you can fix this would be awesome
        for view in self.view.subviews {
            if view is UIScrollView {
                let scroll = view as! UIScrollView
                scroll.bounces = false
            }
        }

        self.setCloseButton(withConfiguration: self.readerConfig)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureNavBar()
        
        if self.index == viewList.firstIndex(of: viewControllerOne) {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Add", style: .plain, target: self, action: #selector(addBookmark(_:)))
        } else {
            self.navigationItem.rightBarButtonItem = nil
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }
    
    func configureNavBar() {
        //let navBackground = self.folioReader.isNight(self.readerConfig.nightModeMenuBackground, self.readerConfig.daysModeNavBackground)
        let navBackground = self.readerConfig.themeModeMenuBackground[self.folioReader.themeMode]
        let tintColor = self.readerConfig.tintColor
        let navText = self.readerConfig.themeModeTextColor[self.folioReader.themeMode]
        let font = UIFont(name: "Avenir-Light", size: 17)!
        setTranslucentNavigation(false, color: navBackground, tintColor: tintColor, titleColor: navText, andFont: font)
    }

    // MARK: - Segmented control changes

    @objc func didSwitchMenu(_ sender: UISegmentedControl) {
        let direction: UIPageViewController.NavigationDirection = (index > sender.selectedSegmentIndex ? .reverse : .forward)
        self.index = sender.selectedSegmentIndex
        setViewControllers([viewList[index]], direction: direction, animated: true, completion: nil)
        self.folioReader.currentAnnotationMenuIndex = index
        
        if self.index == viewList.firstIndex(of: viewControllerOne) {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Add", style: .plain, target: self, action: #selector(addBookmark(_:)))
        } else {
            self.navigationItem.rightBarButtonItem = nil
        }
    }

    // MARK: - Status Bar

    override var preferredStatusBarStyle : UIStatusBarStyle {
        return self.folioReader.isNight(.lightContent, .default)
    }
    
    // MARK: - NavBar Button
    
    @objc func addBookmark(_ sender: UIBarButtonItem) {
        folioLogger("bookmark")
        
        guard let bookmarkList = self.viewControllerOne as? FolioReaderBookmarkList else { return }
        
        sender.isEnabled = false
        bookmarkList.addBookmark() {
            sender.isEnabled = true
        }
        
    }
}

// MARK: UIPageViewControllerDelegate

extension FolioReaderAnnotationPageVC: UIPageViewControllerDelegate {

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {

        if finished && completed {
            let viewController = pageViewController.viewControllers?.last
            segmentedControl.selectedSegmentIndex = viewList.firstIndex(of: viewController!)!
        }
    }
}

// MARK: UIPageViewControllerDataSource

extension FolioReaderAnnotationPageVC: UIPageViewControllerDataSource {

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {

        let index = viewList.firstIndex(of: viewController)!
        if index == viewList.count - 1 {
            return nil
        }

        self.index = self.index + 1
        return viewList[self.index]
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {

        let index = viewList.firstIndex(of: viewController)!
        if index == 0 {
            return nil
        }

        self.index = self.index - 1
        return viewList[self.index]
    }
}

