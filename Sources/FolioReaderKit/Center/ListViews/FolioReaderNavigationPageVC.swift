//
//  PageViewController.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 14/07/16.
//  Copyright © 2016 FolioReader. All rights reserved.
//

import UIKit

class FolioReaderNavigationPageVC: UIPageViewController {

    var segmentedControl: UISegmentedControl!
    var viewList = [UIViewController]()
    var segmentedControlItems = [String]()
    
    var viewControllerZero: UIViewController!
    var viewControllerOne: UIViewController!
    var viewControllerTwo: UIViewController!
    var viewControllerThree: UIViewController!

    var index: Int
    fileprivate var readerConfig: FolioReaderConfig
    fileprivate var folioReader: FolioReader

    // MARK: Init

    init(folioReader: FolioReader, readerConfig: FolioReaderConfig) {
        self.folioReader = folioReader
        self.readerConfig = readerConfig
        self.index = self.folioReader.currentNavigationMenuIndex
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
        segmentedControl.addTarget(self, action: #selector(FolioReaderNavigationPageVC.didSwitchMenu(_:)), for: UIControl.Event.valueChanged)
        segmentedControl.selectedSegmentIndex = index
//        segmentedControl.setWidth(100, forSegmentAt: 0)
//        segmentedControl.setWidth(100, forSegmentAt: 1)
        self.navigationItem.titleView = segmentedControl

        viewList = [viewControllerOne, viewControllerTwo, viewControllerThree]

        viewControllerOne.didMove(toParent: self)
        viewControllerTwo.didMove(toParent: self)
        viewControllerThree.didMove(toParent: self)
        
        if self.folioReader.structuralStyle == .bundle || self.folioReader.structuralStyle == .topic {
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
    }

    func configureNavBar() {
        //let navBackground = self.folioReader.isNight(self.readerConfig.nightModeMenuBackground, self.readerConfig.daysModeNavBackground)
        let navBackground = self.readerConfig.themeModeMenuBackground[self.folioReader.themeMode]
        let tintColor = self.readerConfig.tintColor
        let navText = self.readerConfig.themeModeTextColor[self.folioReader.themeMode]
        let font = UIFont(name: "Avenir-Light", size: 17)!
        setTranslucentNavigation(false, color: navBackground, tintColor: tintColor, titleColor: navText, andFont: font)
        
        if self.index == viewList.firstIndex(of: viewControllerZero) {
            switch self.folioReader.structuralStyle {
            case .bundle:
                self.navigationItem.rightBarButtonItem = UIBarButtonItem(
                    title: self.folioReader.currentNavigationMenuBookListSyle == .Grid ? "List" : "Grid",
                    style: .plain,
                    target: self,
                    action: #selector(switchBookListStyle(_:))
                )
            case .topic:
                self.navigationItem.rightBarButtonItem = UIBarButtonItem(
                    title: "Random",
                    style: .plain,
                    target: self,
                    action: #selector(randomTopic(_:))
                )
            case .atom:
                break
            }
        } else {
            self.navigationItem.rightBarButtonItem = nil
        }
    }

    // MARK: - Segmented control changes

    @objc func didSwitchMenu(_ sender: UISegmentedControl) {
        let direction: UIPageViewController.NavigationDirection = (index > sender.selectedSegmentIndex ? .reverse : .forward)
        self.index = sender.selectedSegmentIndex
        setViewControllers([viewList[index]], direction: direction, animated: true, completion: nil)
        self.folioReader.currentNavigationMenuIndex = index
        configureNavBar()
    }

    // MARK: - Status Bar

    override var preferredStatusBarStyle : UIStatusBarStyle {
        return self.folioReader.isNight(.lightContent, .default)
    }
    
    // MARK: - NavBar Button
    
    @objc func switchBookListStyle(_ sender: UIBarButtonItem) {
        if self.folioReader.currentNavigationMenuBookListSyle == .Grid {
            self.folioReader.currentNavigationMenuBookListSyle = .List
        } else {
            self.folioReader.currentNavigationMenuBookListSyle = .Grid
        }
        configureNavBar()
        guard let bookList = self.viewControllerZero as? FolioReaderBookList else { return }
        //bookList.collectionViewLayout.invalidateLayout()
        bookList.collectionView.reloadData()
    }
    
    @objc func randomTopic(_ sender: UIBarButtonItem) {
        guard let bookList = self.viewControllerZero as? FolioReaderBookList else { return }
        bookList.pickRandomTopic()
    }
    
}

// MARK: UIPageViewControllerDelegate

extension FolioReaderNavigationPageVC: UIPageViewControllerDelegate {

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {

        if finished && completed {
            let viewController = pageViewController.viewControllers?.last
            segmentedControl.selectedSegmentIndex = viewList.firstIndex(of: viewController!)!
        }
    }
}

// MARK: UIPageViewControllerDataSource

extension FolioReaderNavigationPageVC: UIPageViewControllerDataSource {

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

