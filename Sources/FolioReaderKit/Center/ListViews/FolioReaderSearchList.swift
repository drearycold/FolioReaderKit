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

    private struct ScrollSnapshot {
        let resultID: String
        let offset: CGFloat
    }

    private let folioReader: FolioReader
    private let readerConfig: FolioReaderConfig
    private let resolver: FolioReaderSearching
    private let session: FolioReaderSearchSession
    private let historyStore: FolioReaderSearchHistoryStore
    private var searchTask: Task<Void, Never>?
    private var queryGeneration = 0
    private var queryText = ""
    private var currentAnchor: FolioReaderSearchAnchor?
    private var isExpanding = false
    private var hasPendingQuery = false
    private var statusContainer = UIView()
    private var statusLabel = UILabel()
    private var activityIndicator = UIActivityIndicatorView(style: .medium)
    private var loadEarlierButton = UIButton(type: .system)
    private var loadLaterButton = UIButton(type: .system)

    private(set) var state: FolioReaderSearchListState = .initial
    private(set) var sections = [SearchSection]()
    private(set) var history = [String]()
    private(set) var searchController: UISearchController!

    private var batchSize: Int {
        max(1, readerConfig.searchResultLimit)
    }

    private func saturatedIncrement(_ value: Int) -> Int {
        value == Int.max ? Int.max : value + 1
    }

    private var isShowingHistory: Bool {
        queryText.isEmpty && state == .initial
    }

    init(folioReader: FolioReader, readerConfig: FolioReaderConfig, resolver: FolioReaderSearching? = nil) {
        self.folioReader = folioReader
        self.readerConfig = readerConfig
        self.resolver = resolver ?? folioReader.makeSearchResolver() ?? FolioReaderSearchResolver(book: FRBook())
        self.session = folioReader.readerCenter?.searchSession ?? FolioReaderSearchSession()
        self.historyStore = FolioReaderSearchHistoryStore(
            provider: folioReader.delegate?.folioReaderPreferenceProvider?(folioReader),
            identifier: readerConfig.identifier
        )
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
        configureExpansionButtons()
        history = historyStore.load()
        restoreSession()
        setCloseButton(withConfiguration: readerConfig,
                       folioReader: folioReader,
                       action: #selector(closeSearch(_:)))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollToCurrentAnchor()
    }

    @objc func closeSearch(_ sender: UIBarButtonItem) {
        if session.isComplete && queryText == session.query {
            recordCurrentQuery()
        }
        stopSearching()
        navigationController?.dismiss(animated: true)
    }

    private func stopSearching() {
        queryGeneration += 1
        searchTask?.cancel()
        searchController?.searchResultsUpdater = nil
        searchController?.searchBar.delegate = nil
        searchController?.searchBar.resignFirstResponder()
        searchController?.isActive = false
    }

    func updateSearchResults(for searchController: UISearchController) {
        scheduleSearch(for: searchController.searchBar.text ?? "")
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        scheduleSearch(for: "")
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        recordCurrentQuery()
        searchBar.resignFirstResponder()
    }

    private func scheduleSearch(for rawText: String) {
        queryGeneration += 1
        let generation = queryGeneration
        searchTask?.cancel()
        isExpanding = false

        queryText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if queryText.isEmpty {
            hasPendingQuery = false
            sections.removeAll()
            state = .initial
            updateStatus()
            tableView.reloadData()
            return
        }

        hasPendingQuery = true
        state = .loading
        updateStatus()

        let query = queryText
        let anchor = folioReader.readerCenter?.currentSearchAnchor
        currentAnchor = anchor
        let resolver = self.resolver
        let batchSize = self.batchSize
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }

            let forward = await resolver.search(FolioReaderSearchQuery(
                text: query,
                limit: saturatedIncrement(batchSize),
                anchor: anchor,
                direction: .forward
            ))
            guard Task.isCancelled == false else { return }

            let forwardResults = Array(forward.prefix(batchSize))
            let hasMoreForward = forward.count > batchSize
            var backwardResults = [FolioReaderLocatorResult]()
            var hasMoreBackward = false

            if hasMoreForward == false && forwardResults.count < batchSize {
                let remaining = batchSize - forwardResults.count
                let backward = await resolver.search(FolioReaderSearchQuery(
                    text: query,
                    limit: saturatedIncrement(remaining),
                    anchor: anchor,
                    direction: .backward
                ))
                guard Task.isCancelled == false else { return }
                backwardResults = Array(backward.suffix(remaining))
                hasMoreBackward = backward.count > remaining
            } else {
                let backwardProbe = await resolver.search(FolioReaderSearchQuery(
                    text: query,
                    limit: 1,
                    anchor: anchor,
                    direction: .backward
                ))
                guard Task.isCancelled == false else { return }
                hasMoreBackward = backwardProbe.isEmpty == false
            }

            let results = Self.mergedResults(forwardResults + backwardResults)
            await MainActor.run {
                guard let self = self,
                      self.queryGeneration == generation else { return }
                self.applyCompletedSearch(query: query,
                                         results: results,
                                         hasMoreBackward: hasMoreBackward,
                                         hasMoreForward: hasMoreForward)
            }
        }
    }

    private func applyCompletedSearch(query: String,
                                      results: [FolioReaderLocatorResult],
                                      hasMoreBackward: Bool,
                                      hasMoreForward: Bool) {
        session.update(query: query,
                       results: results,
                       hasMoreBackward: hasMoreBackward,
                       hasMoreForward: hasMoreForward)
        isExpanding = false
        queryText = query
        sections = makeSections(from: results)
        state = results.isEmpty ? .noResults : (hasMoreBackward || hasMoreForward ? .truncated : .results)
        hasPendingQuery = false
        updateStatus()
        tableView.reloadData()
        scrollToCurrentAnchor()
    }

    private func restoreSession() {
        guard session.isComplete, session.query.isEmpty == false else {
            updateStatus()
            tableView.reloadData()
            return
        }

        queryText = session.query
        searchController.searchBar.text = session.query
        currentAnchor = folioReader.readerCenter?.currentSearchAnchor
        sections = makeSections(from: session.results)
        state = session.results.isEmpty ? .noResults : (session.hasMoreBackward || session.hasMoreForward ? .truncated : .results)
        hasPendingQuery = false
        updateStatus()
        tableView.reloadData()
    }

    private func recordCurrentQuery() {
        guard queryText.isEmpty == false else { return }
        historyStore.record(queryText)
        history = historyStore.load()
        if isShowingHistory {
            tableView.reloadData()
        }
    }

    private func startExpansion(direction: FolioReaderSearchDirection) {
        guard isExpanding == false,
              hasPendingQuery == false,
              session.isComplete,
              session.query.isEmpty == false else { return }

        let hasMore = direction == .backward ? session.hasMoreBackward : session.hasMoreForward
        guard hasMore else { return }
        let boundaryResult = direction == .backward ? session.results.first : session.results.last
        guard let boundaryResult else { return }

        let snapshot = scrollSnapshot()
        isExpanding = true
        queryGeneration += 1
        let generation = queryGeneration
        searchTask?.cancel()
        state = .loading
        updateStatus()

        let query = FolioReaderSearchQuery(
            text: session.query,
            limit: saturatedIncrement(batchSize),
            anchor: FolioReaderSearchAnchor(page: boundaryResult.page, cfi: boundaryResult.cfi),
            direction: direction
        )
        let resolver = self.resolver
        searchTask = Task { [weak self] in
            let fetched = await resolver.search(query)
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                guard let self = self,
                      self.queryGeneration == generation else { return }
                self.applyExpansion(fetched: fetched,
                                    direction: direction,
                                    snapshot: snapshot)
            }
        }
    }

    @objc func loadEarlierResults() {
        startExpansion(direction: .backward)
    }

    @objc func loadLaterResults() {
        startExpansion(direction: .forward)
    }

    private func applyExpansion(fetched: [FolioReaderLocatorResult],
                                direction: FolioReaderSearchDirection,
                                snapshot: ScrollSnapshot?) {
        let displayed = direction == .backward
            ? Array(fetched.suffix(batchSize))
            : Array(fetched.prefix(batchSize))
        let hasMore = fetched.count > batchSize
        if direction == .backward {
            session.hasMoreBackward = hasMore
        } else {
            session.hasMoreForward = hasMore
        }
        session.results = Self.mergedResults(session.results + displayed)
        isExpanding = false
        sections = makeSections(from: session.results)
        state = session.hasMoreBackward || session.hasMoreForward ? .truncated : .results
        updateStatus()
        tableView.reloadData()
        restoreScrollSnapshot(snapshot)
    }

    private func makeSections(from results: [FolioReaderLocatorResult]) -> [SearchSection] {
        var sections = [SearchSection]()
        for result in results {
            if let lastIndex = sections.indices.last,
               sections[lastIndex].results.first?.page == result.page {
                sections[lastIndex].results.append(result)
            } else {
                sections.append(SearchSection(title: sectionTitle(for: result), results: [result]))
            }
        }
        return sections
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

    private func configureExpansionButtons() {
        loadEarlierButton.setTitle(readerConfig.localizedSearchLoadEarlier, for: .normal)
        loadEarlierButton.addTarget(self, action: #selector(loadEarlierResults), for: .touchUpInside)
        loadEarlierButton.frame = CGRect(x: 16, y: 0, width: tableView.bounds.width - 32, height: 44)
        loadEarlierButton.autoresizingMask = .flexibleWidth

        loadLaterButton.setTitle(readerConfig.localizedSearchLoadLater, for: .normal)
        loadLaterButton.addTarget(self, action: #selector(loadLaterResults), for: .touchUpInside)
        loadLaterButton.frame = CGRect(x: 16, y: 0, width: tableView.bounds.width - 32, height: 44)
        loadLaterButton.autoresizingMask = .flexibleWidth
    }

    private func updateStatus() {
        guard isViewLoaded else { return }
        let hasEarlier = session.isComplete && hasPendingQuery == false && session.hasMoreBackward && sections.isEmpty == false
        let hasLater = session.isComplete && hasPendingQuery == false && session.hasMoreForward && sections.isEmpty == false

        switch state {
        case .initial:
            statusLabel.text = history.isEmpty ? readerConfig.localizedSearchInitial : readerConfig.localizedSearchRecent
            statusLabel.isHidden = false
            activityIndicator.stopAnimating()
        case .loading:
            statusLabel.text = readerConfig.localizedSearchLoading
            statusLabel.isHidden = false
            activityIndicator.startAnimating()
        case .noResults:
            statusLabel.text = readerConfig.localizedSearchNoResults
            statusLabel.isHidden = false
            activityIndicator.stopAnimating()
        case .results:
            statusLabel.text = nil
            statusLabel.isHidden = true
            activityIndicator.stopAnimating()
        case .truncated:
            statusLabel.text = readerConfig.localizedSearchResultsTruncated
            statusLabel.isHidden = false
            activityIndicator.stopAnimating()
        }

        loadEarlierButton.isHidden = !hasEarlier
        loadLaterButton.isHidden = !hasLater
        let showHeader = hasEarlier || state != .results
        statusContainer.frame.size.height = showHeader ? 52 : 0
        statusLabel.frame.size.height = 52
        activityIndicator.center = CGPoint(x: 28, y: 26)
        tableView.tableHeaderView = statusContainer

        if hasEarlier && loadEarlierButton.superview == nil {
            statusContainer.addSubview(loadEarlierButton)
        }
        if hasEarlier {
            loadEarlierButton.frame.origin.y = 4
            statusLabel.frame.origin.y = 48
            statusContainer.frame.size.height = 96
        } else {
            statusLabel.frame.origin.y = 0
        }

        let footerHeight: CGFloat = hasLater ? 52 : 1
        let footer = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: footerHeight))
        footer.autoresizingMask = .flexibleWidth
        if hasLater {
            loadLaterButton.frame = CGRect(x: 16, y: 4, width: footer.bounds.width - 32, height: 44)
            footer.addSubview(loadLaterButton)
        }
        tableView.tableFooterView = footer
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        if isShowingHistory {
            return history.isEmpty ? 0 : 1
        }
        return sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isShowingHistory {
            return history.count
        }
        return sections[safe: section]?.results.count ?? 0
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if isShowingHistory {
            return readerConfig.localizedSearchRecent
        }
        return sections[safe: section]?.title
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: kReuseCellIdentifier, for: indexPath)
        cell.backgroundColor = .clear
        if isShowingHistory {
            cell.textLabel?.attributedText = nil
            cell.textLabel?.text = history[safe: indexPath.row]
            cell.textLabel?.font = UIFont(name: "Avenir-Light", size: 16) ?? .systemFont(ofSize: 16)
            cell.textLabel?.textColor = folioReader.isNight(readerConfig.menuTextColor, UIColor.black)
            return cell
        }

        guard let result = sections[safe: indexPath.section]?.results[safe: indexPath.row] else { return cell }
        let context = result.context ?? result.text ?? ""
        let attributedText = NSMutableAttributedString(string: context)
        let fullRange = NSRange(location: 0, length: attributedText.length)
        attributedText.addAttribute(.font,
                                    value: UIFont(name: "Avenir-Light", size: 16) ?? .systemFont(ofSize: 16),
                                    range: fullRange)
        attributedText.addAttribute(.foregroundColor,
                                    value: folioReader.isNight(readerConfig.menuTextColor, UIColor.black),
                                    range: fullRange)
        for range in FolioReaderTextLocator.matchingRanges(of: queryText, in: context) {
            let nsRange = NSRange(range, in: context)
            attributedText.addAttribute(.font,
                                        value: UIFont(name: "Avenir-Black", size: 17) ?? .boldSystemFont(ofSize: 17),
                                        range: nsRange)
            attributedText.addAttribute(.foregroundColor, value: readerConfig.tintColor, range: nsRange)
        }
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.attributedText = attributedText
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard hasPendingQuery == false, isExpanding == false else { return }
        tableView.deselectRow(at: indexPath, animated: true)
        if isShowingHistory {
            guard let query = history[safe: indexPath.row] else { return }
            searchController.searchBar.text = query
            scheduleSearch(for: query)
            return
        }

        guard let result = sections[safe: indexPath.section]?.results[safe: indexPath.row],
              let cfi = result.cfi,
              let readerCenter = folioReader.readerCenter else { return }

        recordCurrentQuery()
        readerCenter.currentPage?.pushNavigateWebViewScrollPositions()
        folioReader.saveReaderState()
        stopSearching()
        let dismissalController = navigationController ?? self
        dismissalController.dismiss(animated: true) { [weak readerCenter] in
            readerCenter?.changePageWith(page: result.page, andFragment: cfi, animated: true)
        }
    }

    // MARK: - Result ordering and scroll preservation

    private static func resultID(_ result: FolioReaderLocatorResult) -> String {
        "\(result.page)|\(result.cfi ?? "")"
    }

    private static func mergedResults(_ values: [FolioReaderLocatorResult]) -> [FolioReaderLocatorResult] {
        var unique = [String: FolioReaderLocatorResult]()
        for result in values {
            unique[resultID(result)] = result
        }
        return unique.values.sorted { lhs, rhs in
            if lhs.page != rhs.page { return lhs.page < rhs.page }
            guard let leftCFI = lhs.cfi, let rightCFI = rhs.cfi else {
                return (lhs.cfi ?? "") < (rhs.cfi ?? "")
            }
            return FolioReaderTextLocator.compare(cfi: leftCFI, isBeforeOrEqualTo: rightCFI) && leftCFI != rightCFI
        }
    }

    private func scrollToCurrentAnchor() {
        guard session.isComplete, sections.isEmpty == false else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let indexPath = self.indexPathNearestCurrentAnchor() else { return }
            self.tableView.scrollToRow(at: indexPath, at: .middle, animated: false)
        }
    }

    private func indexPathNearestCurrentAnchor() -> IndexPath? {
        guard let anchor = currentAnchor else {
            return sections.first.map { _ in IndexPath(row: 0, section: 0) }
        }

        var fallback: IndexPath?
        for (sectionIndex, section) in sections.enumerated() {
            for (rowIndex, result) in section.results.enumerated() {
                let indexPath = IndexPath(row: rowIndex, section: sectionIndex)
                fallback = indexPath
                if isAtOrAfter(result, anchor: anchor) {
                    return indexPath
                }
            }
        }
        return fallback
    }

    private func isAtOrAfter(_ result: FolioReaderLocatorResult, anchor: FolioReaderSearchAnchor) -> Bool {
        guard let anchorPage = anchor.page else { return true }
        if result.page != anchorPage { return result.page > anchorPage }
        guard let anchorCFI = anchor.cfi else { return true }
        guard let resultCFI = result.cfi else { return false }
        return FolioReaderTextLocator.compare(cfi: anchorCFI, isBeforeOrEqualTo: resultCFI)
    }

    private func scrollSnapshot() -> ScrollSnapshot? {
        guard let indexPath = tableView.indexPathsForVisibleRows?.first,
              let result = sections[safe: indexPath.section]?.results[safe: indexPath.row] else { return nil }
        let rect = tableView.rectForRow(at: indexPath)
        return ScrollSnapshot(resultID: Self.resultID(result), offset: tableView.contentOffset.y - rect.minY)
    }

    private func restoreScrollSnapshot(_ snapshot: ScrollSnapshot?) {
        guard let snapshot else { return }
        tableView.layoutIfNeeded()
        for (sectionIndex, section) in sections.enumerated() {
            for (rowIndex, result) in section.results.enumerated()
                where Self.resultID(result) == snapshot.resultID {
                let indexPath = IndexPath(row: rowIndex, section: sectionIndex)
                let rect = tableView.rectForRow(at: indexPath)
                tableView.setContentOffset(CGPoint(x: tableView.contentOffset.x,
                                                    y: rect.minY + snapshot.offset), animated: false)
                return
            }
        }
    }
}
