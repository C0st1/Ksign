//
//  BackgroundMaintenanceLog.swift
//  Ksign
//
//  Log struct for background maintenance runs.
//  Only the last run is kept (overwritten each time).
//
//  Created for Feature 5: New BG Processing Task
//

import Foundation

/// Represents a single background maintenance run.
struct BackgroundMaintenanceLog: Codable, Equatable {

    /// One phase of the maintenance pipeline.
    struct PhaseLog: Codable, Equatable, Identifiable {
        let id: UUID
        let name: String           // "Source Refresh", "Update Detection", etc.
        let startedAt: Date
        let finishedAt: Date?
        let details: String        // "Refreshed 7 sources, 2 failed"
        let success: Bool

        init(name: String, startedAt: Date, finishedAt: Date? = nil, details: String = "", success: Bool = true) {
            self.id = UUID()
            self.name = name
            self.startedAt = startedAt
            self.finishedAt = finishedAt
            self.details = details
            self.success = success
        }

        var duration: TimeInterval? {
            guard let finishedAt else { return nil }
            return finishedAt.timeIntervalSince(startedAt)
        }
    }

    let startedAt: Date
    var finishedAt: Date?
    var success: Bool
    var phases: [PhaseLog]
    var error: String?
    var cancelled: Bool

    init(startedAt: Date = Date()) {
        self.startedAt = startedAt
        self.finishedAt = nil
        self.success = false
        self.phases = []
        self.error = nil
        self.cancelled = false
    }

    var totalDuration: TimeInterval? {
        guard let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }

    var phaseCount: Int { phases.count }
    var completedPhaseCount: Int { phases.filter { $0.finishedAt != nil }.count }
}

// MARK: - Persistence

/// Singleton that persists the last maintenance log to UserDefaults.
/// Only the most recent log is kept — older logs are overwritten.
final class BackgroundMaintenanceLogStore: ObservableObject {

    static let shared = BackgroundMaintenanceLogStore()

    private let _key = "ksign.lastMaintenanceLog"
    private let _defaults: UserDefaults

    @Published private(set) var lastLog: BackgroundMaintenanceLog?

    private init(defaults: UserDefaults = .standard) {
        self._defaults = defaults
        self.lastLog = _load()
    }

    /// Save a completed log (called by BackgroundMaintenanceCoordinator when done).
    func save(_ log: BackgroundMaintenanceLog) {
        if let data = try? JSONEncoder().encode(log) {
            _defaults.set(data, forKey: _key)
        }
        DispatchQueue.main.async {
            self.lastLog = log
            self.objectWillChange.send()
        }
    }

    /// Clear the stored log.
    func clear() {
        _defaults.removeObject(forKey: _key)
        DispatchQueue.main.async {
            self.lastLog = nil
            self.objectWillChange.send()
        }
    }

    private func _load() -> BackgroundMaintenanceLog? {
        guard let data = _defaults.data(forKey: _key),
              let log = try? JSONDecoder().decode(BackgroundMaintenanceLog.self, from: data)
        else { return nil }
        return log
    }
}
