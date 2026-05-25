//
//  SourceTracker.swift
//  Ksign
//
//  Update Checker - Source URL Tracking
//  Persists bundleID → sourceURL mapping so updates come from the correct source.
//

import Foundation

/// Tracks which source URL each installed app came from.
/// Uses UserDefaults for lightweight persistence.
/// When an app is downloaded from a source, its bundleID and sourceURL are recorded.
/// This allows UpdateManager to prefer the correct source when checking for updates,
/// even for apps that were sideloaded or whose CoreData `source` field is nil.
final class SourceTracker {
    static let shared = SourceTracker()

    private let _defaults = UserDefaults.standard
    private let _key = "ksign.sourceTracker.mapping"

    /// In-memory cache of bundleID → sourceURL string
    private var _mapping: [String: String]

    private init() {
        if let stored = _defaults.dictionary(forKey: _key) as? [String: String] {
            _mapping = stored
        } else {
            _mapping = [:]
        }
    }

    // MARK: - Public API

    /// Record that an app with the given bundle ID came from the specified source URL
    func recordSource(bundleId: String, sourceURL: URL) {
        _mapping[bundleId] = sourceURL.absoluteString
        _persist()
    }

    /// Record source for multiple apps at once (batch operation after source fetch)
    func recordSources(_ entries: [(bundleId: String, sourceURL: URL)]) {
        for entry in entries {
            _mapping[entry.bundleId] = entry.sourceURL.absoluteString
        }
        _persist()
    }

    /// Get the stored source URL for a bundle ID, if any
    func sourceURL(for bundleId: String) -> URL? {
        guard let urlString = _mapping[bundleId] else { return nil }
        return URL(string: urlString)
    }

    /// Remove the tracking entry for a bundle ID (e.g., when app is uninstalled)
    func removeSource(for bundleId: String) {
        _mapping.removeValue(forKey: bundleId)
        _persist()
    }

    /// Remove all tracking entries
    func removeAll() {
        _mapping.removeAll()
        _persist()
    }

    /// Get all tracked bundle IDs
    var allTrackedBundleIDs: Set<String> {
        Set(_mapping.keys)
    }

    // MARK: - Private

    private func _persist() {
        _defaults.set(_mapping, forKey: _key)
    }
}
