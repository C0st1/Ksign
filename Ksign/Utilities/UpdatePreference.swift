//
//  AppUpdatePreference.swift
//  Ksign
//
//  Per-App Update Preferences — allows users to control update behavior
//  per bundle ID: Auto-Update, Notify, or Ignore.
//
//  Created for Feature 4: Per-App Update Preferences
//

import Foundation
import SwiftUI

// MARK: - AppUpdatePreference Enum

/// Per-app update behavior preference.
/// Named `AppUpdatePreference` (not `UpdatePreference`) to avoid a name
/// collision with a type in the iOS 26 PencilKit SDK.
enum AppUpdatePreference: String, Codable, CaseIterable {
    /// Automatically download updates when detected (and optionally auto-install).
    case autoUpdate = "Auto-Update"
    /// Show the update in the updates list, but don't auto-download. (default)
    case notify = "Notify"
    /// Never show updates for this app (or for a specific version only).
<<<<<<< HEAD
=======
    case ignore = "Ignore"
>>>>>>> 5e8121a (Add 5 features + fix iOS 26 SDK build errors)

    var displayName: String {
        switch self {
        case .autoUpdate: return .localized("Auto-Update")
        case .notify:     return .localized("Notify")
        case .ignore:     return .localized("Ignore")
        }
    }

    var iconName: String {
        switch self {
        case .autoUpdate: return "arrow.triangle.2.circlepath"
        case .notify:     return "bell"
        case .ignore:     return "bell.slash"
        }
    }

    var color: Color {
        switch self {
        case .autoUpdate: return .green
        case .notify:     return .accentColor
        case .ignore:     return .red
        }
    }
}

// MARK: - UpdatePreferencesStore

/// Singleton store for per-app update preferences.
/// Persisted in UserDefaults as a JSON array of entries.
/// Thread-safe via serial queue for reads/writes.
final class UpdatePreferencesStore: ObservableObject {

    static let shared = UpdatePreferencesStore()

    // MARK: - Types

    /// A single preference entry for one bundle ID.
    struct Entry: Codable, Equatable {
        let bundleId: String
        let preference: AppUpdatePreference
        let setAt: Date
        /// If non-nil, the ignore applies only to this specific version.
        /// A different version will reset the preference to the default.
        let ignoredVersion: String?
    }

    // MARK: - Properties

    private let _key = "ksign.updatePreferences"
    private let _defaults: UserDefaults
    private let _queue = DispatchQueue(label: "ksign.updatePreferences", qos: .userInitiated)

    @Published private(set) var entries: [String: Entry] = [:]

    // MARK: - Init

    private init(defaults: UserDefaults = .standard) {
        self._defaults = defaults
        self.entries = _loadEntries()
    }

    // MARK: - Public API

    /// Get the preference for a bundle ID.
    /// Falls back to the global default if no per-app entry exists.
    func preference(for bundleId: String) -> AppUpdatePreference {
        if let entry = _entry(for: bundleId) {
            // If this is an "ignore this version only" entry, check if the
            // ignored version is still the latest. If a newer version exists,
            // we should clear the ignore and fall back to default.
            // (The version comparison happens in UpdateManager — here we just
            // return the stored preference. UpdateManager handles the "new
            // version available" logic.)
            return entry.preference
        }
        return _globalDefault()
    }

    /// Set a permanent preference (applies to all future versions).
    func set(_ preference: AppUpdatePreference, for bundleId: String) {
        let entry = Entry(
            bundleId: bundleId,
            preference: preference,
            setAt: Date(),
            ignoredVersion: nil
        )
        _save(entry: entry, for: bundleId)
    }

    /// Ignore a specific version only. When a newer version becomes available,
    /// UpdateManager will clear this and fall back to the default.
    func ignoreVersion(_ version: String, for bundleId: String) {
        let entry = Entry(
            bundleId: bundleId,
            preference: .ignore,
            setAt: Date(),
            ignoredVersion: version
        )
        _save(entry: entry, for: bundleId)
    }

    /// Clear the preference for a bundle ID (revert to global default).
    func clear(for bundleId: String) {
        _queue.sync {
            entries.removeValue(forKey: bundleId)
            _persist()
        }
        DispatchQueue.main.async { self.objectWillChange.send() }
    }

    /// Check if a specific version is explicitly ignored for a bundle ID.
    func isVersionIgnored(_ version: String, for bundleId: String) -> Bool {
        guard let entry = _entry(for: bundleId) else { return false }
<<<<<<< HEAD
        return entry.preference == .ignore && entry.ignoredVersion == version
=======
        return entry.preference == AppUpdatePreference.ignore && entry.ignoredVersion == version
>>>>>>> 5e8121a (Add 5 features + fix iOS 26 SDK build errors)
    }

    /// Get the ignored version string (if any) for a bundle ID.
    func ignoredVersion(for bundleId: String) -> String? {
        _entry(for: bundleId)?.ignoredVersion
    }

    /// All preferences as a sorted list (most recently set first).
    func allPreferences() -> [(bundleId: String, preference: AppUpdatePreference, setAt: Date, ignoredVersion: String?)] {
        entries.values
            .sorted { $0.setAt > $1.setAt }
            .map { ($0.bundleId, $0.preference, $0.setAt, $0.ignoredVersion) }
    }

    /// Bulk: set all entries to Notify (reset to default behavior).
    func resetAllToNotify() {
        _queue.sync {
            entries.removeAll()
            _persist()
        }
        DispatchQueue.main.async { self.objectWillChange.send() }
    }

    /// Bulk: clear all ignored entries (un-ignore everything).
    func clearAllIgnored() {
        _queue.sync {
<<<<<<< HEAD
            entries = entries.filter { _, entry in entry.preference != .ignore }
=======
            entries = entries.filter { _, entry in entry.preference != AppUpdatePreference.ignore }
>>>>>>> 5e8121a (Add 5 features + fix iOS 26 SDK build errors)
            _persist()
        }
        DispatchQueue.main.async { self.objectWillChange.send() }
    }

    // MARK: - Private

    private func _entry(for bundleId: String) -> Entry? {
        _queue.sync { entries[bundleId] }
    }

    private func _save(entry: Entry, for bundleId: String) {
        _queue.sync {
            entries[bundleId] = entry
            _persist()
        }
        DispatchQueue.main.async { self.objectWillChange.send() }
    }

    private func _globalDefault() -> AppUpdatePreference {
        let raw = OptionsManager.shared.options.defaultUpdatePreference
        return AppUpdatePreference(rawValue: raw) ?? .notify
    }

    private func _loadEntries() -> [String: Entry] {
        guard let data = _defaults.data(forKey: _key),
              let array = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: array.map { ($0.bundleId, $0) })
    }

    private func _persist() {
        let array = Array(entries.values)
        if let data = try? JSONEncoder().encode(array) {
            _defaults.set(data, forKey: _key)
        }
    }
}
