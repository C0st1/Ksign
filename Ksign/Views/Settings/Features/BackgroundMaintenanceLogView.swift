//
//  BackgroundMaintenanceLogView.swift
//  Ksign
//
//  Shows the last background maintenance run's phase-by-phase log.
//
//  Created for Feature 5: New BG Processing Task
//

import SwiftUI
import NimbleViews

struct BackgroundMaintenanceLogView: View {
    @StateObject private var _logStore = BackgroundMaintenanceLogStore.shared

    var body: some View {
        NBList(.localized("Maintenance Log"), displayMode: .inline) {
            if let log = _logStore.lastLog {
                // Summary section
                NBSection(.localized("Summary")) {
                    _infoCell(.localized("Started"), desc: log.startedAt.formatted(date: .abbreviated, time: .standard))
                    if let finished = log.finishedAt {
                        _infoCell(.localized("Finished"), desc: finished.formatted(date: .abbreviated, time: .standard))
                    }
                    if let duration = log.totalDuration {
                        _infoCell(.localized("Duration"), desc: String.localized("%lld seconds", arguments: Int(duration)))
                    }
                    _infoCell(
                        .localized("Status"),
                        desc: log.cancelled ? .localized("Cancelled") : (log.success ? .localized("Success") : .localized("Failed"))
                    )
                    _infoCell(.localized("Phases"), desc: String.localized("%lld of %lld completed", arguments: log.completedPhaseCount, log.phaseCount))
                }

                // Error section (if any)
                if let error = log.error {
                    NBSection(.localized("Error")) {
                        Text(error)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }

                // Phases section
                NBSection(.localized("Phases")) {
                    ForEach(log.phases) { phase in
                        _phaseRow(phase)
                    }
                }

                // Clear button
                Section {
                    Button(.localized("Clear log"), role: .destructive) {
                        _logStore.clear()
                    }
                }
            } else {
                Section {
                    ContentUnavailableView {
                        Label(.localized("No maintenance runs yet"), systemImage: "clock.badge.questionmark")
                    } description: {
                        Text(.localized("Background maintenance hasn't run yet. It will run automatically based on your settings."))
                    }
                }
            }
        }
        .toolbar {
            NBToolbarButton(role: .close)
        }
    }

    // MARK: - Row Builders

    @ViewBuilder
    private func _phaseRow(_ phase: BackgroundMaintenanceLog.PhaseLog) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: phase.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(phase.success ? .green : .red)
                Text(phase.name)
                    .font(.body)
                    .fontWeight(.medium)
                Spacer()
                if let duration = phase.duration {
                    Text(String.localized("%.1fs", arguments: duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(phase.details)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Image(systemName: "play.circle")
                    .font(.caption2)
                Text(phase.startedAt.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                if let finished = phase.finishedAt {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                    Image(systemName: "checkmark.circle")
                        .font(.caption2)
                    Text(finished.formatted(date: .omitted, time: .standard))
                        .font(.caption2)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func _infoCell(_ title: String, desc: String) -> some View {
        LabeledContent(title) {
            Text(desc)
                .foregroundStyle(.primary)
        }
    }
}
