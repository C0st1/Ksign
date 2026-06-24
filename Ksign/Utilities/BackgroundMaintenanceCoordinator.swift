//
//  BackgroundMaintenanceCoordinator.swift
//  Ksign
//
//  Runs the full background maintenance pipeline:
//   1. Refresh all sources
//   2. Detect updates
//   3. Auto-update eligible apps (uses per-app .autoUpdate preferences)
//   4. Clean stale downloads
//   5. Check certificate expirations
//
//  Created for Feature 5: New BG Processing Task
//

import Foundation
import CoreData
import AltSourceKit
import UserNotifications
import OSLog
import NimbleJSON

/// Coordinator for the background maintenance pipeline.
/// Runs as a detached Task; cancellable via cancel().
final class BackgroundMaintenanceCoordinator {

    static let shared = BackgroundMaintenanceCoordinator()

    private var _currentTask: Task<Void, Never>?
    private let _logStore = BackgroundMaintenanceLogStore.shared

    private init() {}

    // MARK: - Public API

    /// Run the full maintenance pipeline. Calls `completion` on the main thread
    /// when done (or cancelled).
    func run(completion: @escaping (Bool) -> Void) {
        var log = BackgroundMaintenanceLog(startedAt: Date())

        _currentTask = Task.detached(priority: .background) {
            var success = true

            // Phase 1: Refresh all sources
            if Task.isCancelled {
                log.cancelled = true
                await self._finish(log: log, success: false, completion: completion)
                return
            }
            let phase1Success = await self._refreshSources(log: &log)
            if !phase1Success { success = false }

            // Phase 2: Detect updates
            if Task.isCancelled {
                log.cancelled = true
                await self._finish(log: log, success: false, completion: completion)
                return
            }
            let phase2Success = await self._detectUpdates(log: &log)
            if !phase2Success { success = false }

            // Phase 3: Auto-update eligible apps
            if Task.isCancelled {
                log.cancelled = true
                await self._finish(log: log, success: false, completion: completion)
                return
            }
            await self._autoUpdateApps(log: &log)

            // Phase 4: Clean stale downloads
            if Task.isCancelled {
                log.cancelled = true
                await self._finish(log: log, success: false, completion: completion)
                return
            }
            await self._cleanStaleDownloads(log: &log)

            // Phase 5: Check certificate expirations
            if Task.isCancelled {
                log.cancelled = true
                await self._finish(log: log, success: false, completion: completion)
                return
            }
            await self._checkCertificateExpirations(log: &log)

            await self._finish(log: log, success: success, completion: completion)
        }
    }

    /// Cancel the current maintenance run.
    func cancel() {
        _currentTask?.cancel()
        _currentTask = nil
        Logger.misc.warning("Background maintenance task cancelled")
    }

    // MARK: - Phase 1: Source Refresh

    /// Re-fetch every AltSource's ASRepository.
    /// Reads AltSource entities directly from Core Data (not from
    /// SourcesViewModel.shared.sources, which may be empty if the user
    /// hasn't opened the App Store tab yet).
    private func _refreshSources(log: inout BackgroundMaintenanceLog) async -> Bool {
        let phaseStart = Date()
        var phase = BackgroundMaintenanceLog.PhaseLog(
            name: .localized("Source Refresh"),
            startedAt: phaseStart
        )

        // Fetch AltSource entities directly from Core Data
        let sources: [AltSource] = await MainActor.run {
            let context = Storage.shared.context
            let request: NSFetchRequest<AltSource> = AltSource.fetchRequest()
            return (try? context.fetch(request)) ?? []
        }

        guard !sources.isEmpty else {
            phase.finishedAt = Date()
            phase.details = .localized("No sources to refresh")
            phase.success = true
            log.phases.append(phase)
            Logger.misc.info("Background maintenance phase 1: no sources")
            return true
        }

        var successCount = 0
        var failureCount = 0

        await withTaskGroup(of: (AltSource, ASRepository?).self) { group in
            for source in sources {
                guard let url = source.sourceURL else {
                    failureCount += 1
                    continue
                }
                group.addTask {
                    await withCheckedContinuation { continuation in
                        NBFetchService().fetch(from: url) { (result: Result<ASRepository, Error>) in
                            switch result {
                            case .success(let repo): continuation.resume(returning: (source, repo))
                            case .failure:           continuation.resume(returning: (source, nil))
                            }
                        }
                    }
                }
            }

            var refreshed: [AltSource: ASRepository] = [:]
            for await (source, repo) in group {
                if let repo {
                    refreshed[source] = repo
                    successCount += 1
                } else {
                    failureCount += 1
                }
            }

            // Merge refreshed results into SourcesViewModel so UpdateManager
            // (phase 2) can see them
            await MainActor.run {
                SourcesViewModel.shared.sources.merge(refreshed) { _, new in new }
            }
        }

        phase.finishedAt = Date()
        phase.details = String.localized(
            "%lld sources refreshed, %lld failed",
            arguments: successCount, failureCount
        )
        phase.success = failureCount == 0
        log.phases.append(phase)

        Logger.misc.info("Background maintenance phase 1: \(phase.details)")
        return phase.success
    }

    // MARK: - Phase 2: Update Detection

    /// Trigger UpdateManager to cross-reference installed apps against refreshed sources.
    private func _detectUpdates(log: inout BackgroundMaintenanceLog) async -> Bool {
        let phaseStart = Date()
        var phase = BackgroundMaintenanceLog.PhaseLog(
            name: .localized("Update Detection"),
            startedAt: phaseStart
        )

        let updateCount = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            UpdateManager.shared.forceCheckForUpdates {
                let count = UpdateManager.shared.updateCount
                continuation.resume(returning: count)
            }
        }

        phase.finishedAt = Date()
        phase.details = String.localized("%lld updates detected", arguments: updateCount)
        phase.success = true
        log.phases.append(phase)

        Logger.misc.info("Background maintenance phase 2: \(phase.details)")
        return true
    }

    // MARK: - Phase 3: Auto-Update

    /// Apps with .autoUpdate preference are already auto-downloaded by UpdateManager
    /// during phase 2's check. Here we just log how many were triggered.
    private func _autoUpdateApps(log: inout BackgroundMaintenanceLog) async {
        let phaseStart = Date()
        var phase = BackgroundMaintenanceLog.PhaseLog(
            name: .localized("Auto-Update"),
            startedAt: phaseStart
        )

        // Count apps with .autoUpdate preference that have updates available
        let allPrefs = UpdatePreferencesStore.shared.allPreferences()
        let autoUpdateBundleIds = Set(allPrefs.filter { $0.preference == .autoUpdate }.map { $0.bundleId })

        // The actual downloads were triggered by UpdateManager._processUpdates
        // (which runs auto-update candidates). Here we just count how many
        // auto-update apps exist for logging purposes.
        let autoUpdateCount = autoUpdateBundleIds.count

        phase.finishedAt = Date()
        phase.details = String.localized(
            "%lld apps configured for auto-update",
            arguments: autoUpdateCount
        )
        phase.success = true
        log.phases.append(phase)

        Logger.misc.info("Background maintenance phase 3: \(phase.details)")
    }

    // MARK: - Phase 4: Stale Download Cleanup

    /// Remove downloaded IPAs older than 30 days from Documents/Downloads.
    private func _cleanStaleDownloads(log: inout BackgroundMaintenanceLog) async {
        let phaseStart = Date()
        var phase = BackgroundMaintenanceLog.PhaseLog(
            name: .localized("Stale Download Cleanup"),
            startedAt: phaseStart
        )

        let downloadsDir = URL.documentsDirectory.appendingPathComponent("Downloads")
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600) // 30 days ago
        var cleanedCount = 0

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: downloadsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            phase.finishedAt = Date()
            phase.details = .localized("Downloads directory not found")
            phase.success = true
            log.phases.append(phase)
            return
        }

        for fileURL in contents where fileURL.pathExtension.lowercased() == "ipa" {
            if let modDate = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               modDate < cutoff {
                try? FileManager.default.removeItem(at: fileURL)
                cleanedCount += 1
                Logger.misc.info("Cleaned stale download: \(fileURL.lastPathComponent)")
            }
        }

        phase.finishedAt = Date()
        phase.details = String.localized("%lld stale files cleaned", arguments: cleanedCount)
        phase.success = true
        log.phases.append(phase)

        Logger.misc.info("Background maintenance phase 4: \(phase.details)")
    }

    // MARK: - Phase 5: Certificate Expiry Check

    /// Notify the user about certificates expiring within 7 days.
    private func _checkCertificateExpirations(log: inout BackgroundMaintenanceLog) async {
        let phaseStart = Date()
        var phase = BackgroundMaintenanceLog.PhaseLog(
            name: .localized("Certificate Expiry Check"),
            startedAt: phaseStart
        )

        let context = Storage.shared.context
        let request: NSFetchRequest<CertificatePair> = CertificatePair.fetchRequest()

        guard let certs = try? context.fetch(request) else {
            phase.finishedAt = Date()
            phase.details = .localized("Could not fetch certificates")
            phase.success = false
            log.phases.append(phase)
            return
        }

        let now = Date()
        let warningThreshold = now.addingTimeInterval(7 * 24 * 3600) // 7 days
        var expiringCount = 0

        for cert in certs where !cert.revoked {
            guard let expiration = cert.expiration else { continue }

            if expiration < warningThreshold && expiration > now {
                expiringCount += 1
                await MainActor.run {
                    self._sendCertExpiryNotification(cert: cert, expiration: expiration)
                }
            }
        }

        phase.finishedAt = Date()
        phase.details = String.localized(
            "%lld certificates expiring soon",
            arguments: expiringCount
        )
        phase.success = true
        log.phases.append(phase)

        Logger.misc.info("Background maintenance phase 5: \(phase.details)")
    }

    // MARK: - Notifications

    private func _sendCertExpiryNotification(cert: CertificatePair, expiration: Date) {
        guard OptionsManager.shared.options.notifications else { return }

        let content = UNMutableNotificationContent()
        content.title = String.localized("Certificate Expiring Soon")

        let nickname = cert.nickname ?? .localized("Certificate")
        let daysLeft = max(0, Int(expiration.timeIntervalSinceNow / 86400))
        content.body = String.localized(
            "%@ expires in %lld days. Renew and re-sign your apps.",
            arguments: nickname, daysLeft
        )
        content.sound = .default
        content.userInfo = ["certUUID": cert.uuid ?? ""]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "certExpiry.\(cert.uuid ?? UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Finish

    private func _finish(
        log: BackgroundMaintenanceLog,
        success: Bool,
        completion: @escaping (Bool) -> Void
    ) async {
        var finalLog = log
        finalLog.finishedAt = Date()
        finalLog.success = success
        _logStore.save(finalLog)

        await MainActor.run {
            Logger.misc.info("Background maintenance finished: success=\(success)")
            completion(success)
        }
    }
}
