//
//  SuggestedSourcesViewModel.swift
//  Ksign
//
//  Created by Nagata Asami on 25.06.2025.
//

import Foundation
import AltSourceKit
import NimbleJSON
import SwiftUI

// MARK: - ViewModel
@MainActor
final class SuggestedSourcesViewModel: ObservableObject {

    // MARK: Types
    struct SuggestedSource: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let url: String
        var iconURL: URL?
        var isLoading: Bool = true
        var isAdded: Bool = false
        var fetchFailed: Bool = false

        static func == (lhs: SuggestedSource, rhs: SuggestedSource) -> Bool {
            lhs.id == rhs.id
        }
    }

    // MARK: Properties
    @Published private(set) var sources: [SuggestedSource] = []
    @Published private(set) var isFetching: Bool = false

    private let _dataService = NBFetchService()

    // MARK: Init
    init() {
        sources = Storage.suggestedSourceURLs.map {
            SuggestedSource(name: $0.name, url: $0.url)
        }
        _refreshAddedStates()
    }

    // MARK: Public
    /// Fetches the source manifest for every suggested source in parallel
    /// so we can populate each row with the source's actual icon.
    func fetchAllMetadata() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        let snapshot = sources
        let dataService = _dataService

        let results: [(Int, URL?)] = await withTaskGroup(of: (Int, URL?).self) { group in
            for (index, source) in snapshot.enumerated() {
                guard let url = URL(string: source.url) else {
                    // mark as failed immediately so the row doesn't stay in loading
                    group.addTask { (index, nil) }
                    continue
                }
                group.addTask {
                    await withCheckedContinuation { (continuation: CheckedContinuation<(Int, URL?), Never>) in
                        Task { @MainActor in
                            dataService.fetch<ASRepository>(from: url) { (result: Result<ASRepository, Error>) in
                                switch result {
                                case .success(let repo):
                                    continuation.resume(returning: (index, repo.currentIconURL))
                                case .failure:
                                    continuation.resume(returning: (index, nil))
                                }
                            }
                        }
                    }
                }
            }

            var collected: [(Int, URL?)] = []
            for await item in group {
                collected.append(item)
            }
            return collected
        }

        for (index, iconURL) in results {
            guard index < sources.count else { continue }
            sources[index].iconURL = iconURL
            sources[index].isLoading = false
            sources[index].fetchFailed = (iconURL == nil)
        }
    }

    /// Re-checks which suggested sources are already present in the user's library.
    func refreshAddedStates() {
        _refreshAddedStates()
    }

    /// Adds a suggested source to the user's library. Updates the row optimistically
    /// and reverts on failure. Note: `FR.handleSource` does not call its completion
    /// on the "already added" or failure paths (it shows an alert instead), so we
    /// schedule a deferred state refresh to catch those cases.
    func addSource(_ suggestion: SuggestedSource) {
        guard let idx = sources.firstIndex(where: { $0.id == suggestion.id }) else { return }
        guard !sources[idx].isAdded else { return }
        let url = sources[idx].url
        let suggestionId = sources[idx].id

        // optimistic update
        sources[idx].isAdded = true

        FR.handleSource(url) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self._refreshAddedState(for: suggestionId)
            }
        }

        // Safety net: if FR.handleSource never calls its completion (e.g. on
        // "already added" or network failure), re-sync the row state after a
        // short delay so the user doesn't see a stuck "Added" checkmark.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?._refreshAddedState(for: suggestionId)
        }
    }

    // MARK: Private
    private func _refreshAddedStates() {
        let existingURLs = Set(
            Storage.shared.getSources().compactMap { $0.sourceURL?.absoluteString }
        )
        for i in sources.indices {
            sources[i].isAdded = existingURLs.contains(sources[i].url)
        }
    }

    private func _refreshAddedState(for suggestionId: UUID) {
        let existingURLs = Set(
            Storage.shared.getSources().compactMap { $0.sourceURL?.absoluteString }
        )
        guard let idx = sources.firstIndex(where: { $0.id == suggestionId }) else { return }
        sources[idx].isAdded = existingURLs.contains(sources[idx].url)
    }
}
