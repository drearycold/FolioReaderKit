import UIKit
import FolioEPUBCore

enum FolioReaderSearchListState: Equatable {
    case initial
    case loading
    case noResults
    case results
    case truncated
}

final class FolioReaderSearchList: UITableViewController, UISearchResultsUpdating, UISearchBarDelegate {
    struct SearchSection {
        let title: String
        var results: [FolioReaderLocatorResult]
    }

    private let folioReader: FolioReader
    private let readerConfig: FolioReaderConfig
    private let resolver: FolioReaderSearching
    private var searchTask: Task<Void, Never>?
    private var queryGeneration = 0
    private var queryText = ""
    private var statusContainer = UIView()
    private var statusLabel = UILabel()
    private var activityIndicator = UIActivityIndicatorView(style: .medium)

    private(set) var state: FolioReaderSearchListState = .initial
    private(set) var sections = [SearchSection]()
    private(set) var searchController: UISearchController!

    init(folioReader: FolioReader, readerConfig: FolioReaderConfig, resolver: FolioReaderSearching? = nil) {
        self.folioReader = folioReader
        self.readerConfig = readerConfig
        self.resolver = resolver ?? folioReader.makeSearchResolver() ?? FolioReaderSearchResolver(book: FRBook())
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init with coder not supported")
    }

    deinit {
        searchTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = readerConfig.localizedSearchTitle
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: kReuseCellIdentifier)
        tableView.backgroundColor = readerConfig.themeModeMenuBackground[folioReader.themeMode]
        tableView.separatorColor = folioReader.isNight(readerConfig.nightModeSeparatorColor, readerConfig.menuSeparatorColor)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64

        let controller = UISearchController(searchResultsController: nil)
        controller.searchResultsUpdater = self
        controller.searchBar.delegate = self
        controller.searchBar.placeholder = readerConfig.localizedSearchPlaceholder
        controller.searchBar.autocapitalizationType = .none
        controller.searchBar.autocorrectionType = .no
        controller.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = controller
        navigationItem.hidesSearchBarWhenScrolling = false
        searchController = controller
        definesPresentationContext = true

        configureStatusView()
        updateStatus()
        setCloseButton(withConfiguration: readerConfig, folioReader: folioReader)
    }

    func updateSearchResults(for searchController: UISearchController) {
        scheduleSearch(for: searchController.searchBar.text ?? "")
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        scheduleSearch(for: "")
    }

    private func scheduleSearch(for rawText: String) {
        queryGeneration += 1
        let generation = queryGeneration
        searchTask?.cancel()

        queryText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        sections.removeAll()
        tableView.reloadData()

        guard queryText.isEmpty == false else {
            state = .initial
            updateStatus()
            return
        }

        state = .loading
        updateStatus()

        let displayLimit = max(0, readerConfig.searchResultLimit)
        let requestLimit = displayLimit == Int.max ? displayLimit : displayLimit + 1
        let query = FolioReaderSearchQuery(text: queryText, limit: requestLimit)
        let resolver = self.resolver
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }

            let results = await resolver.search(query)
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                guard let self = self, self.queryGeneration == generation else { return }
                self.apply(results: results, displayLimit: displayLimit)
            }
        }
    }

    private func apply(results: [FolioReaderLocatorResult], displayLimit: Int) {
        let isTruncated = displayLimit > 0 && results.count > displayLimit
        let displayedResults = Array(results.prefix(displayLimit))
        sections.removeAll()
        for result in displayedResults {
            if let lastIndex = sections.indices.last, sections[lastIndex].results.first?.page == result.page {
                sections[lastIndex].results.append(result)
            } else {
                sections.append(SearchSection(title: sectionTitle(for: result), results: [result]))
            }
        }

        if displayedResults.isEmpty {
            state = .noResults
        } else if isTruncated {
            state = .truncated
        } else {
            state = .results
        }
        updateStatus()
        tableView.reloadData()
    }

    private func sectionTitle(for result: FolioReaderLocatorResult) -> String {
        if result.tocPath.isEmpty == false {
            return result.tocPath.joined(separator: " › ")
        }
        return "\(readerConfig.localizedSearchChapter) \(result.page)"
    }

    private func configureStatusView() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 52))
        container.autoresizingMask = .flexibleWidth
        statusContainer = container

        statusLabel = UILabel(frame: CGRect(x: 20, y: 0, width: container.bounds.width - 40, height: 52))
        statusLabel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = UIFont(name: "Avenir-Light", size: 15) ?? .systemFont(ofSize: 15)
        statusLabel.textColor = folioReader.isNight(readerConfig.menuTextColor, UIColor.darkGray)
        container.addSubview(statusLabel)

        activityIndicator.center = CGPoint(x: 28, y: 26)
        container.addSubview(activityIndicator)
        tableView.tableHeaderView = container
    }

    private func updateStatus() {
        guard isViewLoaded else { return }
        switch state {
        case .initial:
            statusContainer.frame.size.height = 52
            statusLabel.text = readerConfig.localizedSearchInitial
            statusLabel.isHidden = false
            activityIndicator.stopAnimating()
        case .loading:
            statusContainer.frame.size.height = 52
            statusLabel.text = readerConfig.localizedSearchLoading
            statusLabel.isHidden = false
            activityIndicator.startAnimating()
        case .noResults:
            statusContainer.frame.size.height = 52
            statusLabel.text = readerConfig.localizedSearchNoResults
            statusLabel.isHidden = false
            activityIndicator.stopAnimating()
        case .results:
            statusContainer.frame.size.height = 0
            statusLabel.text = nil
            statusLabel.isHidden = true
            activityIndicator.stopAnimating()
        case .truncated:
            statusContainer.frame.size.height = 52
            statusLabel.text = readerConfig.localizedSearchResultsTruncated
            statusLabel.isHidden = false
            activityIndicator.stopAnimating()
        }
        tableView.tableHeaderView = statusContainer
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[safe: section]?.results.count ?? 0
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[safe: section]?.title
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: kReuseCellIdentifier, for: indexPath)
        guard let result = sections[safe: indexPath.section]?.results[safe: indexPath.row] else { return cell }

        let context = result.context ?? result.text ?? ""
        let attributedText = NSMutableAttributedString(string: context)
        let fullRange = NSRange(location: 0, length: attributedText.length)
        attributedText.addAttribute(.font, value: UIFont(name: "Avenir-Light", size: 16) ?? .systemFont(ofSize: 16), range: fullRange)
        attributedText.addAttribute(.foregroundColor,
                                    value: folioReader.isNight(readerConfig.menuTextColor, UIColor.black),
                                    range: fullRange)
        for range in FolioReaderTextLocator.matchingRanges(of: queryText, in: context) {
            let nsRange = NSRange(range, in: context)
            attributedText.addAttribute(.font, value: UIFont(name: "Avenir-Black", size: 17) ?? .boldSystemFont(ofSize: 17), range: nsRange)
            attributedText.addAttribute(.foregroundColor, value: readerConfig.tintColor, range: nsRange)
        }
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.attributedText = attributedText
        cell.backgroundColor = .clear
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let result = sections[safe: indexPath.section]?.results[safe: indexPath.row],
              let cfi = result.cfi,
              let readerCenter = folioReader.readerCenter else { return }

        readerCenter.currentPage?.pushNavigateWebViewScrollPositions()
        folioReader.saveReaderState()
        dismiss(animated: true) { [weak readerCenter] in
            readerCenter?.changePageWith(page: result.page, andFragment: cfi, animated: true)
        }
    }
}
