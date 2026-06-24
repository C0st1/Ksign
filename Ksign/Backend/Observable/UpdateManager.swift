//
//  UpdateManager.swift
//  Ksign
//
//  Update Checker - Core Orchestrator
//  Cross-references installed apps against source data to detect available updates.
//

import Foundation
import SwiftUI
import CoreData
import AltSourceKit
import UserNotifications
import OSLog

/// Represents a single available update for an installed app
struct AppUpdate: Identifiable {
    let installedApp: AppInfoPresentable
    let sourceApp: ASRepository.App
    let sourceURL: URL
    let installedVersion: String
    let availableVersion: String
    /// Version description / changelog from the source (may be nil)
    var versionDescription: String?

    var id: String { installedApp.identifier ?? UUID().uuidString }
}

/// Central update detection manager. Observes SourcesViewModel and CoreData,
/// publishes available updates for the UI to consume.
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    /// Available updates keyed by bundle identifier
    @Published var updates: [String: AppUpdate] = [:]
    @Published var isChecking: Bool = false
    /// Number of available updates (reliably published for SwiftUI)
    @Published var updateCount: Int = 0
    /// Status of the last check — nil if never checked, error message if failed
    @Published var lastCheckStatus: String? = nil

    /// Minimum interval between foreground checks (seconds)
    private let _foregroundCheckInterval: TimeInterval = 300 // 5 minutes
    private var _lastCheckTime: Date?
    /// Previous update bundle IDs for smart notification dedup
    private var _previousUpdateBundleIDs: Set<String> = []

    /// Completion handler for background tasks
    private var _backgroundCheckCompletion: (() -> Void)?

    private init() {}

    // MARK: - Public API

    /// Check for updates by cross-referencing installed apps against source data.
    /// Called on foreground transition and after source refresh.
    func checkForUpdates() {
        let now = Date()
        if let last = _lastCheckTime, now.timeIntervalSince(last) < _foregroundCheckInterval {
            return
        }
        _lastCheckTime = now

        _performCheckAsync()
    }

    /// Force check regardless of throttle interval (used after pull-to-refresh)
    func forceCheckForUpdates() {
        _lastCheckTime = Date()
        _performCheckAsync()
    }

    /// Force check with completion handler (used for background tasks)
    func forceCheckForUpdates(completion: @escaping () -> Void) {
        _lastCheckTime = Date()
        _backgroundCheckCompletion = completion
        _performCheckAsync()
    }

    /// Clear update for a specific bundle ID (after successful update install)
    func clearUpdate(for bundleId: String) {
        DispatchQueue.main.async {
            self.updates.removeValue(forKey: bundleId)
            self.updateCount = self.updates.count
        }
    }

    /// Clear all updates
    func clearAllUpdates() {
        DispatchQueue.main.async {
            self.updates.removeAll()
            self.updateCount = 0
        }
    }

    /// Check if an update is available for a specific bundle ID
    func isUpdateAvailable(for bundleId: String?) -> Bool {
        guard let bundleId = bundleId else { return false }
        return updates[bundleId] != nil
    }

    /// Get the latest available version string for a bundle ID
    func latestVersion(for bundleId: String?) -> String? {
        guard let bundleId = bundleId else { return nil }
        return updates[bundleId]?.availableVersion
    }

    /// Get the AppUpdate for a specific bundle ID
    func update(for bundleId: String?) -> AppUpdate? {
        guard let bundleId = bundleId else { return nil }
        return updates[bundleId]
    }

    // MARK: - Internal

    /// Async-safe check that avoids the DispatchQueue.main.sync deadlock.
    /// Fetches CoreData on main thread via async dispatch, then processes off-main.
    private func _performCheckAsync() {
        DispatchQueue.main.async {
            self.isChecking = true
            self.lastCheckStatus = nil
        }

        // Step 1: Capture source data (thread-safe snapshot)
        let sourcesVM = SourcesViewModel.shared
        let sources = sourcesVM.sources

        // Step 2: Fetch installed apps on main thread asynchronously to avoid deadlock
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let context = Storage.shared.context
            let signedRequest: NSFetchRequest<Signed> = Signed.fetchRequest()
            let importedRequest: NSFetchRequest<Imported> = Imported.fetchRequest()

            var installedApps: [AppInfoPresentable] = []
            if let signed = try? context.fetch(signedRequest) {
                installedApps.append(contentsOf: signed)
            }
            if let imported = try? context.fetch(importedRequest) {
                installedApps.append(contentsOf: imported)
            }

            // Step 3: Process matching on a global queue
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                self._processUpdates(installedApps: installedApps, sources: sources)
            }
        }
    }

    /// Core matching logic — runs off the main thread
    private func _processUpdates(installedApps: [AppInfoPresentable], sources: [AltSource: ASRepository]) {
        var newUpdates: [String: AppUpdate] = [:]
        var autoUpdateCandidates: [AppUpdate] = []

        // Build a map of bundle ID → best source app across all sources
        var bestSourceApp: [String: (app: ASRepository.App, sourceURL: URL)] = [:]

        for (altSource, repository) in sources {
            guard let sourceURL = altSource.sourceURL else { continue }
            let apps = repository.apps

            for app in apps {
                guard let bundleId = app.id, !bundleId.isEmpty else { continue }
                guard let version = app.currentVersion, !version.isEmpty else { continue }

                if let existing = bestSourceApp[bundleId] {
                    // Keep the one with the highest version
                    if VersionComparator.compare(version, existing.app.currentVersion ?? "0") == .orderedDescending {
                        bestSourceApp[bundleId] = (app, sourceURL)
                    }
                } else {
                    bestSourceApp[bundleId] = (app, sourceURL)
                }
            }
        }

        // Match installed apps against best source apps
        for installed in installedApps {
            guard let bundleId = installed.identifier, !bundleId.isEmpty else { continue }
            guard let installedVersion = installed.version, !installedVersion.isEmpty else { continue }

            guard let match = bestSourceApp[bundleId] else { continue }

            if VersionComparator.isUpdateAvailable(installed: installedVersion, source: match.app.currentVersion) {
                // Prefer the source the app originally came from
                // 1. Check CoreData stored source (from Signed/Imported entity)
                // 2. Fall back to SourceTracker (persisted in UserDefaults)
                var updateSourceApp = match.app
                var updateSourceURL = match.sourceURL

                let storedSourceURL = (installed as? Signed)?.source
                    ?? (installed as? Imported)?.source
                    ?? SourceTracker.shared.sourceURL(for: bundleId)

                if let storedSourceURL = storedSourceURL {
                    // Check if the stored source has a version of this app
                    for (altSource, repository) in sources {
                        guard altSource.sourceURL == storedSourceURL else { continue }
                        let apps = repository.apps
                        if let app = apps.first(where: { $0.id == bundleId }),
                           let version = app.currentVersion,
                           VersionComparator.isUpdateAvailable(installed: installedVersion, source: version) {
                            updateSourceApp = app
                            updateSourceURL = storedSourceURL
                            break
                        }
                    }
                }

                // Extract version description (changelog) from the source app
                let versionDesc = updateSourceApp.versionDescription
                    ?? updateSourceApp.currentAppVersion?.localizedDescription

                let availableVersion = updateSourceApp.currentVersion ?? installedVersion

                // Check per-app update preference
                let preference = UpdatePreferencesStore.shared.preference(for: bundleId)

                // Handle "ignore this version only" logic:
                // If the user ignored a specific version AND a newer version is now available,
                // clear the ignore so they get notified about the new version.
                if preference == .ignore,
                   let ignoredVersion = UpdatePreferencesStore.shared.ignoredVersion(for: bundleId),
                   ignoredVersion != availableVersion {
                    // A new version is available that's different from the ignored one —
                    // clear the version-specific ignore so the user gets notified.
                    UpdatePreferencesStore.shared.clear(for: bundleId)
                    // Re-read the preference (now falls back to global default)
                    let newPref = UpdatePreferencesStore.shared.preference(for: bundleId)
                    _handleUpdate(
                        preference: newPref,
                        installed: installed,
                        sourceApp: updateSourceApp,
                        sourceURL: updateSourceURL,
                        installedVersion: installedVersion,
                        availableVersion: availableVersion,
                        versionDesc: versionDesc,
                        newUpdates: &newUpdates,
                        autoUpdateCandidates: &autoUpdateCandidates
                    )
                    continue
                }

                _handleUpdate(
                    preference: preference,
                    installed: installed,
                    sourceApp: updateSourceApp,
                    sourceURL: updateSourceURL,
                    installedVersion: installedVersion,
                    availableVersion: availableVersion,
                    versionDesc: versionDesc,
                    newUpdates: &newUpdates,
                    autoUpdateCandidates: &autoUpdateCandidates
                )
            }
        }

        // Publish results on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.updates = newUpdates
            self.updateCount = newUpdates.count
            self.isChecking = false
            self.lastCheckStatus = nil

            // Smart notification: only notify if there are NEW updates
            // (bundle IDs that weren't in the previous set)
            let newBundleIDs = Set(newUpdates.keys)
            let trulyNew = newBundleIDs.subtracting(self._previousUpdateBundleIDs)
            self._previousUpdateBundleIDs = newBundleIDs

            if !trulyNew.isEmpty {
                self._sendUpdateNotification(newCount: trulyNew.count, totalCount: newUpdates.count)
            }

            // Trigger auto-downloads for apps with .autoUpdate preference
            for update in autoUpdateCandidates {
                self._startAutoDownload(for: update)
            }

            // Signal background task completion
            self._backgroundCheckCompletion?()
            self._backgroundCheckCompletion = nil
        }
    }

    /// Route an update to the appropriate bucket based on the per-app preference.
    private func _handleUpdate(
        preference: AppUpdatePreference,
        installed: AppInfoPresentable,
        sourceApp: ASRepository.App,
        sourceURL: URL,
        installedVersion: String,
        availableVersion: String,
        versionDesc: String?,
        newUpdates: inout [String: AppUpdate],
        autoUpdateCandidates: inout [AppUpdate]
    ) {
        let update = AppUpdate(
            installedApp: installed,
            sourceApp: sourceApp,
            sourceURL: sourceURL,
            installedVersion: installedVersion,
            availableVersion: availableVersion,
            versionDescription: versionDesc
        )

        switch preference {
        case .ignore:
            // Don't show in updates list, don't auto-download
            break
        case .notify:
            // Show in updates list, user taps "Update" to download
            newUpdates[installed.identifier ?? ""] = update
        case .autoUpdate:
            // Don't show in the visible updates list — it's being handled.
            // Queue it for auto-download.
            autoUpdateCandidates.append(update)
        }
    }

    /// Start an automatic download for an app with .autoUpdate preference.
    private func _startAutoDownload(for update: AppUpdate) {
        guard let downloadURL = update.sourceApp.currentDownloadUrl else {
            Logger.misc.warning("Auto-update: no download URL for \(update.installedApp.identifier ?? "?")")
            return
        }

        let bundleId = update.installedApp.identifier ?? UUID().uuidString
        let downloadId = "FeatherAutoUpdate_\(bundleId)_\(UUID().uuidString)"

        Logger.misc.info("Auto-update: starting download for \(bundleId) v\(update.availableVersion)")

        _ = DownloadManager.shared.startDownload(
            from: downloadURL,
            id: downloadId,
            sourceURL: update.sourceURL
        )

        // Send a notification that we started an auto-update
        _sendAutoUpdateNotification(for: update)
    }

    /// Notification sent when an auto-update download is triggered.
    private func _sendAutoUpdateNotification(for update: AppUpdate) {
        guard OptionsManager.shared.options.notifications else { return }

        let content = UNMutableNotificationContent()
        content.title = String.localized("Auto-Update Started")
        let appName = update.installedApp.name ?? update.installedApp.identifier ?? .localized("App")
        content.body = String.localized(
            "%@ is being updated to %@",
            arguments: appName, update.availableVersion
        )
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "autoupdate.\(update.installedApp.identifier ?? UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Notifications

    /// Send notification only for newly discovered updates (dedup)
    private func _sendUpdateNotification(newCount: Int, totalCount: Int) {
        guard OptionsManager.shared.options.checkForUpdates else { return }
        guard OptionsManager.shared.options.notifyOnUpdates else { return }
        guard OptionsManager.shared.options.notifications else { return }

        let content = UNMutableNotificationContent()
        content.title = String.localized("Updates Available")

        if newCount == totalCount {
            content.body = String.localized("\(totalCount) app\(totalCount > 1 ? "s have" : " has") updates available")
        } else {
            content.body = String.localized("\(newCount) new update\(newCount > 1 ? "s" : "") available (\(totalCount) total)")
        }
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "update.check",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("Failed to schedule update notification: \(error.localizedDescription)") }
        }
    }
}
