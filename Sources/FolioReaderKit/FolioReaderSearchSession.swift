import Foundation

/// The in-memory state shared by every search presentation for one reader.
final class FolioReaderSearchSession {
    var query = ""
    var results = [FolioReaderLocatorResult]()
    var hasMoreBackward = false
    var hasMoreForward = false
    var isComplete = false

    func reset() {
        query = ""
        results.removeAll()
        hasMoreBackward = false
        hasMoreForward = false
        isComplete = false
    }

    func update(query: String,
                results: [FolioReaderLocatorResult],
                hasMoreBackward: Bool,
                hasMoreForward: Bool) {
        self.query = query
        self.results = results
        self.hasMoreBackward = hasMoreBackward
        self.hasMoreForward = hasMoreForward
        self.isComplete = true
    }
}

final class FolioReaderSearchHistoryStore {
    private let provider: FolioReaderPreferenceProvider?
    private let key: String
    private let maxCount = 100

    init(provider: FolioReaderPreferenceProvider?, identifier: String?) {
        self.provider = provider
        self.key = Self.preferenceKey(for: identifier)
    }

    static func preferenceKey(for identifier: String?) -> String {
        let readerIdentifier = identifier?.isEmpty == false ? identifier! : "default"
        return "FolioReaderKit.searchHistory.\(readerIdentifier)"
    }

    func load() -> [String] {
        guard let provider = provider,
              let data = provider.preference(stringFor: key, default: "").data(using: .utf8),
              let history = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Array(history.prefix(maxCount))
    }

    func record(_ rawQuery: String) {
        guard let provider = provider else { return }
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return }

        var history = load()
        history.removeAll { isEquivalent($0, query) }
        history.insert(query, at: 0)
        let encoded = (try? JSONEncoder().encode(Array(history.prefix(maxCount))))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        provider.preference(setString: encoded, for: key)
    }

    private func isEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
