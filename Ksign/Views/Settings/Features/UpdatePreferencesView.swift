//
//  UpdatePreferencesView.swift
//  Ksign
//
//  Global manager for per-app update preferences.
//  Shows all apps with custom preferences, grouped by preference type.
//
//  Created for Feature 4: Per-App Update Preferences
//

import SwiftUI
import NimbleViews
import CoreData

struct UpdatePreferencesView: View {
    @StateObject private var _store = UpdatePreferencesStore.shared
    @StateObject private var _optionsManager = OptionsManager.shared
    @StateObject private var _updateManager = UpdateManager.shared

    // MARK: - Computed

    /// All installed apps (signed + imported) for display.
    private var _allApps: [AppInfoPresentable] {
        let context = Storage.shared.context
        let signedRequest: NSFetchRequest<Signed> = Signed.fetchRequest()
        let importedRequest: NSFetchRequest<Imported> = Imported.fetchRequest()
        var apps: [AppInfoPresentable] = []
        if let signed = try? context.fetch(signedRequest) { apps.append(contentsOf: signed) }
        if let imported = try? context.fetch(importedRequest) { apps.append(contentsOf: imported) }
        return apps
    }

    private var _autoUpdateApps: [(bundleId: String, app: AppInfoPresentable?, setAt: Date)] {
        _store.allPreferences()
            .filter { $0.preference == .autoUpdate }
            .compactMap { entry in
                let app = _allApps.first { $0.identifier == entry.bundleId }
                return (entry.bundleId, app, entry.setAt)
            }
    }

    private var _notifyApps: [(bundleId: String, app: AppInfoPresentable?, setAt: Date)] {
        _store.allPreferences()
            .filter { $0.preference == .notify }
            .compactMap { entry in
                let app = _allApps.first { $0.identifier == entry.bundleId }
                return (entry.bundleId, app, entry.setAt)
            }
    }

    private var _ignoredApps: [(bundleId: String, app: AppInfoPresentable?, setAt: Date, ignoredVersion: String?)] {
        _store.allPreferences()
            .filter { $0.preference == AppUpdatePreference.ignore }
            .compactMap { entry in
                let app = _allApps.first { $0.identifier == entry.bundleId }
                return (entry.bundleId, app, entry.setAt, entry.ignoredVersion)
            }
    }

    // MARK: - Body

    var body: some View {
        NBList(.localized("Update Preferences")) {
            // Default preference section
            Section {
                Picker(.localized("Default for new apps"), selection: $_optionsManager.options.defaultUpdatePreference) {
                    ForEach(AppUpdatePreference.allCases, id: \.rawValue) { pref in
                        Label(pref.displayName, systemImage: pref.iconName)
                            .tag(pref.rawValue)
                    }
                }
            } footer: {
                Text(verbatim: .localized("Apps without a specific preference will use this default."))
            }
            .onChange(of: _optionsManager.options.defaultUpdatePreference) { _ in
                _optionsManager.saveOptions()
            }

            // Auto-Update section
            if !_autoUpdateApps.isEmpty {
                NBSection(
                    .localized("Auto-Update"),
                    secondary: _autoUpdateApps.count.description,
                    systemName: "arrow.triangle.2.circlepath"
                ) {
                    ForEach(_autoUpdateApps, id: \.bundleId) { entry in
                        _appRow(
                            bundleId: entry.bundleId,
                            app: entry.app,
                            preference: .autoUpdate,
                            setAt: entry.setAt,
                            ignoredVersion: nil
                        )
                    }
                }
            }

            // Notify section
            if !_notifyApps.isEmpty {
                NBSection(
                    .localized("Notify"),
                    secondary: _notifyApps.count.description,
                    systemName: "bell"
                ) {
                    ForEach(_notifyApps, id: \.bundleId) { entry in
                        _appRow(
                            bundleId: entry.bundleId,
                            app: entry.app,
                            preference: .notify,
                            setAt: entry.setAt,
                            ignoredVersion: nil
                        )
                    }
                }
            }

            // Ignored section
            if !_ignoredApps.isEmpty {
                NBSection(
                    .localized("Ignored"),
                    secondary: _ignoredApps.count.description,
                    systemName: "bell.slash"
                ) {
                    ForEach(_ignoredApps, id: \.bundleId) { entry in
                        _appRow(
                            bundleId: entry.bundleId,
                            app: entry.app,
                            preference: .ignore,
                            setAt: entry.setAt,
                            ignoredVersion: entry.ignoredVersion
                        )
                    }
                }
            }

            // Bulk actions
            if !_store.allPreferences().isEmpty {
                Section {
                    Button(.localized("Reset all to Notify"), role: .destructive) {
                        _store.resetAllToNotify()
                    }
                    Button(.localized("Clear all ignored")) {
                        _store.clearAllIgnored()
                    }
                }
            }

            // Help footer
            Section {
                EmptyView()
            } footer: {
                Text(verbatim: .localized("Per-app update preferences override the global default. Tap any app to change its preference."))
            }
        }
        .toolbar {
            NBToolbarButton(role: .close)
        }
    }

    // MARK: - Row Builder

    @ViewBuilder
    private func _appRow(
        bundleId: String,
        app: AppInfoPresentable?,
        preference: AppUpdatePreference,
        setAt: Date,
        ignoredVersion: String?
    ) -> some View {
        Menu {
            ForEach(AppUpdatePreference.allCases, id: \.rawValue) { pref in
                Button {
                    _store.set(pref, for: bundleId)
                } label: {
                    Label(pref.displayName, systemImage: pref.iconName)
                }
            }

            Divider()

            Button(.localized("Clear preference"), role: .destructive) {
                _store.clear(for: bundleId)
            }
        } label: {
            HStack(spacing: 12) {
                // App icon (or placeholder)
                if let app = app {
                    FRAppIconView(app: app, size: 40)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(uiColor: .quaternarySystemFill))
                        .frame(width: 40, height: 40)
                        .overlay(Image(systemName: "questionmark.app").foregroundStyle(.secondary))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(app?.name ?? bundleId)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        if let ignoredVersion = ignoredVersion {
                            Text(verbatim: .localized("Ignored v%@", arguments: ignoredVersion))
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            Text(verbatim: .localized("Set %@", arguments: setAt.formatted(date: .abbreviated, time: .omitted)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Image(systemName: preference.iconName)
                    .foregroundStyle(preference.color)
                    .font(.body)
            }
        }
    }
}
