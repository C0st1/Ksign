//
//  LibraryInfoView.swift
//  Feather
//
//  Created by samara on 14.04.2025.
//

import SwiftUI
import NimbleViews
import Zsign

// MARK: - View
struct LibraryInfoView: View {
        var app: AppInfoPresentable
        
        // MARK: Body
    var body: some View {
                NBNavigationView(app.name ?? "", displayMode: .inline) {
                        List {
                                Section {} header: {
                                        FRAppIconView(app: app)
                                                .frame(maxWidth: .infinity, alignment: .center)
                                }
                                
                                _infoSection(for: app)
                                _certSection(for: app)
                                _bundleSection(for: app)
                                _executableSection(for: app)
                                _updatePreferencesSection(for: app)
                                
                                Section {
                                        Button(.localized("Open App Files"), systemImage: "folder") {
                                                UIApplication.open(Storage.shared.getUuidDirectory(for: app)!.toSharedDocumentsURL()!)
                                        }
                                }
                        }
                        .toolbar {
                                NBToolbarButton(role: .close)
                        }
                }
    }
}

// MARK: - Extension: View
extension LibraryInfoView {
        @ViewBuilder
        private func _infoSection(for app: AppInfoPresentable) -> some View {
                NBSection(.localized("Info")) {
                        if let name = app.name {
                                _infoCell(.localized("Name"), desc: name)
                        }
                        
                        if let ver = app.version {
                                _infoCell(.localized("Version"), desc: ver)
                        }
                        
                        if let id = app.identifier {
                                _infoCell(.localized("Identifier"), desc: id)
                        }
                        
                        if let date = app.date {
                                _infoCell(.localized("Date Added"), desc: date.formatted())
                        }
                }
        }
        
        @ViewBuilder
        private func _certSection(for app: AppInfoPresentable) -> some View {
                if let cert = Storage.shared.getCertificate(from: app) {
                        NBSection(.localized("Certificate")) {
                                CertificatesCellView(
                                        cert: cert
                                )
                        }
                }
        }
        
        @ViewBuilder
        private func _bundleSection(for app: AppInfoPresentable) -> some View {
                NBSection(.localized("Bundle")) {
                        NavigationLink(.localized("Alternative Icons")) {
                                SigningAlternativeIconView(app: app, appIcon: .constant(nil), isModifing: .constant(false))
                        }
                        NavigationLink(.localized("Frameworks & PlugIns")) {
                                SigningFrameworksView(app: app, options: .constant(nil))
                        }
                }
        }
        
        @ViewBuilder
        private func _executableSection(for app: AppInfoPresentable) -> some View {
                NBSection(.localized("Executable")) {
                        NavigationLink(.localized("Dylibs")) {
                                SigningDylibView(app: app, options: .constant(nil))
                        }
                }
        }

        /// Per-app update preferences section — shows current preference,
        /// latest available version, and lets the user change the preference.
        @ViewBuilder
        private func _updatePreferencesSection(for app: AppInfoPresentable) -> some View {
                let bundleId = app.identifier ?? ""
                let preference = UpdatePreferencesStore.shared.preference(for: bundleId)
                let availableVersion = UpdateManager.shared.latestVersion(for: bundleId)
                let hasUpdate = UpdateManager.shared.isUpdateAvailable(for: bundleId)
                let ignoredVersion = UpdatePreferencesStore.shared.ignoredVersion(for: bundleId)

                NBSection(.localized("Updates")) {
                        // Current preference (tappable to change)
                        Menu {
                                ForEach(AppUpdatePreference.allCases, id: \.rawValue) { pref in
                                        Button {
                                                UpdatePreferencesStore.shared.set(pref, for: bundleId)
                                        } label: {
                                                Label(pref.displayName, systemImage: pref.iconName)
                                        }
                                }

                                Divider()

                                if hasUpdate, let avail = availableVersion {
                                        Button {
                                                UpdatePreferencesStore.shared.ignoreVersion(avail, for: bundleId)
                                        } label: {
                                                Label(.localized("Ignore v%@ only", arguments: avail), systemImage: "bell.slash.fill")
                                        }
                                }

                                if preference != _globalDefaultPreference() {
                                        Button(role: .destructive) {
                                                UpdatePreferencesStore.shared.clear(for: bundleId)
                                        } label: {
                                                Label(.localized("Clear preference"), systemImage: "arrow.counterclockwise")
                                        }
                                }
                        } label: {
                                LabeledContent(.localized("Update Preference")) {
                                        HStack(spacing: 4) {
                                                Image(systemName: preference.iconName)
                                                        .foregroundStyle(preference.color)
                                                Text(preference.displayName)
                                                        .foregroundStyle(.primary)
                                                Image(systemName: "chevron.up.chevron.down")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                        }
                                }
                        }

                        if hasUpdate, let avail = availableVersion {
                                _infoCell(.localized("Latest available"), desc: avail)
                                if let installed = app.version {
                                        _infoCell(.localized("Installed"), desc: installed)
                                }
                        } else {
                                _infoCell(.localized("Status"), desc: .localized("Up to date"))
                        }

                        if let ignored = ignoredVersion {
                                _infoCell(.localized("Ignored version"), desc: ignored)
                                        .foregroundStyle(.red)
                        }
                }
        }

        /// Read the global default preference.
        private func _globalDefaultPreference() -> AppUpdatePreference {
                let raw = OptionsManager.shared.options.defaultUpdatePreference
                return AppUpdatePreference(rawValue: raw) ?? .notify
        }
        
        @ViewBuilder
        private func _infoCell(_ title: String, desc: String) -> some View {
                LabeledContent(title) {
                        Text(desc)
                }
        }
}
