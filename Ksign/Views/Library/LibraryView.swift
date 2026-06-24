//
//  LibraryView.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import SwiftUI
import CoreData
import NimbleViews

// MARK: - View
struct LibraryView: View {
        @StateObject var downloadManager = DownloadManager.shared
        @ObservedObject var updateManager = UpdateManager.shared
        
        @State private var _selectedInfoAppPresenting: AnyApp?
        @State private var _selectedSigningAppPresenting: AnyApp?
        @State private var _selectedInstallAppPresenting: AnyApp?
        @State private var _selectedAppDylibsPresenting: AnyApp?
        @State private var _isBulkSigningPresenting = false
    @State private var _isBulkInstallingPresenting = false
        @State private var _isImportingPresenting = false
        @State private var _isDownloadingPresenting = false

        @State private var _alertDownloadString: String = "" // for _isDownloadingPresenting
        @State private var _searchText = ""
        @State private var _selectedTab: Int = 0 // 0 for Downloaded, 1 for Signed
        
        // MARK: Edit Mode
    @State private var _isEditMode: EditMode = .inactive
        @State private var _selectedApps: Set<String> = []
        
        @Namespace private var _namespace
        
        // horror
        private func filteredAndSortedApps<T>(from apps: FetchedResults<T>) -> [T] where T: NSManagedObject {
                apps.filter {
                        _searchText.isEmpty ||
                        (($0.value(forKey: "name") as? String)?.localizedCaseInsensitiveContains(_searchText) ?? false)
                }
        }
        
        private var _filteredSignedApps: [Signed] {
                filteredAndSortedApps(from: _signedApps)
        }
        
        private var _filteredImportedApps: [Imported] {
                filteredAndSortedApps(from: _importedApps)
        }
        
        // MARK: Fetch
        @FetchRequest(
                entity: Signed.entity(),
                sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)],
                animation: .snappy
        ) private var _signedApps: FetchedResults<Signed>
        
        @FetchRequest(
                entity: Imported.entity(),
                sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)],
                animation: .snappy
        ) private var _importedApps: FetchedResults<Imported>
        
        // MARK: Body
    var body: some View {
                NBNavigationView(.localized("Library")) {
                        VStack(spacing: 0) {
                                Picker("", selection: $_selectedTab) {
                                        Text(.localized("Downloaded Apps")).tag(0)
                                        Text(.localized("Signed Apps")).tag(1)
                                }
                                .pickerStyle(SegmentedPickerStyle())
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                
                                NBListAdaptable {
                                        // Updates Available section
                                        if !updateManager.updates.isEmpty {
                                                NBSection(
                                                        .localized("Updates Available"),
                                                        secondary: updateManager.updateCount.description
                                                ) {
                                                        // Update All row
                                                        if updateManager.updateCount > 1 {
                                                                HStack {
                                                                        Spacer()
                                                                        Button {
                                                                                _updateAllApps()
                                                                        } label: {
                                                                                HStack(spacing: 6) {
                                                                                        Image(systemName: "arrow.triangle.2.circlepath")
                                                                                                .font(.subheadline.bold())
                                                                                        Text(.localized("Update All"))
                                                                                                .font(.subheadline.bold())
                                                                                }
                                                                                .foregroundStyle(.white)
                                                                                .padding(.horizontal, 16)
                                                                                .padding(.vertical, 7)
                                                                                .background(Color.orange)
                                                                                .clipShape(Capsule())
                                                                        }
                                                                        .buttonStyle(.borderless)
                                                                        Spacer()
                                                                }
                                                                .padding(.vertical, 4)
                                                        }

                                                        ForEach(Array(updateManager.updates.values), id: \.id) { update in
                                                                VStack(alignment: .leading, spacing: 4) {
                                                                        HStack(spacing: 10) {
                                                                                VStack(alignment: .leading, spacing: 2) {
                                                                                        Text(update.installedApp.name ?? .localized("Unknown"))
                                                                                                .font(.body)
                                                                                                .fontWeight(.medium)
                                                                                        HStack(spacing: 4) {
                                                                                                Text(update.installedVersion)
                                                                                                        .font(.caption)
                                                                                                        .foregroundStyle(.secondary)
                                                                                                Image(systemName: "arrow.right")
                                                                                                        .font(.caption2)
                                                                                                        .foregroundStyle(.secondary)
                                                                                                Text(update.availableVersion)
                                                                                                        .font(.caption)
                                                                                                        .foregroundStyle(.orange)
                                                                                        }
                                                                                }
                                                                                Spacer()
                                                                                Button {
                                                                                        if let url = update.sourceApp.currentDownloadUrl {
                                                                                                _ = downloadManager.startDownload(from: url, id: update.sourceApp.currentUniqueId, sourceURL: update.sourceURL)
                                                                                        }
                                                                                } label: {
                                                                                        Text(.localized("Update"))
                                                                                                .font(.subheadline.bold())
                                                                                                .foregroundStyle(.white)
                                                                                                .padding(.horizontal, 16)
                                                                                                .padding(.vertical, 4)
                                                                                                .background(Color.orange)
                                                                                                .clipShape(Capsule())
                                                                                }
                                                                                .buttonStyle(.borderless)
                                                                                // Per-app update preference menu
                                                                                _updatePreferenceMenu(for: update)
                                                                        }

                                                                        // Show changelog / what's new if available
                                                                        if let changelog = update.versionDescription, !changelog.isEmpty {
                                                                                Text(changelog)
                                                                                        .font(.caption)
                                                                                        .foregroundStyle(.secondary)
                                                                                        .lineLimit(3)
                                                                                        .padding(.top, 2)
                                                                        }
                                                                }
                                                                .padding(.vertical, 4)
                                                        }
                                                }
                                        }
                                        if _selectedTab == 0 {
                                                NBSection(
                                                        .localized("Downloaded Apps"),
                                                        secondary: _filteredImportedApps.count.description
                                                ) {
                                                        ForEach(_filteredImportedApps, id: \.uuid) { app in
                                                                LibraryCellView(
                                                                        app: app,
                                                                        selectedInfoAppPresenting: $_selectedInfoAppPresenting,
                                                                        selectedSigningAppPresenting: $_selectedSigningAppPresenting,
                                                                        selectedInstallAppPresenting: $_selectedInstallAppPresenting,
                                                                        selectedAppDylibsPresenting: $_selectedAppDylibsPresenting,
                                                                        selectedApps: $_selectedApps
                                                                )
                                                                .compatMatchedTransitionSource(id: app.uuid ?? "", ns: _namespace)
                                                        }
                                                }
                                        } else {
                                                NBSection(
                                                        .localized("Signed Apps"),
                                                        secondary: _filteredSignedApps.count.description
                                                ) {
                                                        ForEach(_filteredSignedApps, id: \.uuid) { app in
                                                                LibraryCellView(
                                                                        app: app,
                                                                        selectedInfoAppPresenting: $_selectedInfoAppPresenting,
                                                                        selectedSigningAppPresenting: $_selectedSigningAppPresenting,
                                                                        selectedInstallAppPresenting: $_selectedInstallAppPresenting,
                                                                        selectedAppDylibsPresenting: $_selectedAppDylibsPresenting,
                                                                        selectedApps: $_selectedApps
                                                                )
                                                                .compatMatchedTransitionSource(id: app.uuid ?? "", ns: _namespace)
                                                        }
                                                }
                                        }
                                }
                        }
                        .searchable(text: $_searchText, placement: .platform())
            .overlay {
                if
                    _filteredSignedApps.isEmpty,
                    _filteredImportedApps.isEmpty
                {
                    if #available(iOS 17, *) {
                        ContentUnavailableView {
                            Label(.localized("No Apps"), systemImage: "questionmark.app.fill")
                        } description: {
                            Text(.localized("Get started by importing your first IPA file."))
                        } actions: {
                            Menu {
                                _importActions()
                            } label: {
                                Text("Import").bg()
                            }
                        }
                    }
                }
            }
                        .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                if _isEditMode.isEditing {
                                        ToolbarItemGroup(placement: .topBarTrailing) {
                        if _selectedTab == 0 {
                            Button {
                                _isBulkSigningPresenting = true
                            } label: {
                                NBButton(.localized("Sign"), systemImage: "signature", style: .icon)
                            }
                            .disabled(_selectedApps.isEmpty)
                        } else {
                            Button {
                                _isBulkInstallingPresenting = true
                            } label: {
                                NBButton(.localized("Install"), systemImage: "square.and.arrow.down")
                            }
                            .disabled(_selectedApps.isEmpty)
                        }
                                                Button {
                                                        _bulkDeleteSelectedApps()
                                                } label: {
                                                        NBButton(.localized("Delete"), systemImage: "trash", style: .icon)
                                                }
                                                .disabled(_selectedApps.isEmpty)
                                        }
                                } else {
                                        NBToolbarMenu(
                                                systemImage: "plus",
                                                style: .icon,
                                                placement: .topBarTrailing
                                        ) {
                        _importActions()
                    }
                                }
                        }
            .environment(\.editMode, $_isEditMode)
                        .sheet(item: $_selectedInfoAppPresenting) { app in
                                LibraryInfoView(app: app.base)
                        }
                        .sheet(item: $_selectedInstallAppPresenting) { app in
                                InstallPreviewView(app: app.base, isSharing: app.archive)
                                        .presentationDetents([.height(200)])
                                        .presentationDragIndicator(.visible)                                    }
                        .fullScreenCover(item: $_selectedSigningAppPresenting) { app in
                                SigningView(app: app.base, signAndInstall: app.signAndInstall)
                                        .compatNavigationTransition(id: app.base.uuid ?? "", ns: _namespace)
                        }
                        .fullScreenCover(item: $_selectedAppDylibsPresenting) { app in
                DylibsView(app: app.base)
                                        .compatNavigationTransition(id: app.base.uuid ?? "", ns: _namespace)
                        }
                        .fullScreenCover(isPresented: $_isBulkSigningPresenting) {
                                BulkSigningView(apps: _selectedApps.compactMap { id in
                                        (_importedApps.first(where: { $0.uuid == id }) as AppInfoPresentable?)
                                        ?? (_signedApps.first(where: { $0.uuid == id }) as AppInfoPresentable?)
                                })
                                .compatNavigationTransition(id: _selectedApps.joined(separator: ","), ns: _namespace)
                                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ksign.bulkSigningFinished"))) { notification in
                                        _selectedTab = 1
                                }
                        }
            .sheet(isPresented: $_isBulkInstallingPresenting) {
                BulkInstallPreviewView(apps: _selectedApps.compactMap { id in
                    (_importedApps.first(where: { $0.uuid == id }) as AppInfoPresentable?)
                    ?? (_signedApps.first(where: { $0.uuid == id }) as AppInfoPresentable?)
                })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
                        .sheet(isPresented: $_isImportingPresenting) {
                                FileImporterRepresentableView(
                                        allowedContentTypes:  [.ipa, .tipa],
                                        allowsMultipleSelection: true,
                                        onDocumentsPicked: { urls in
                                                guard !urls.isEmpty else { return }
                                                
                                                for ipas in urls {
                                                        let id = "FeatherManualDownload_\(UUID().uuidString)"
                                                        let dl = downloadManager.startArchive(from: ipas, id: id)
                                                        downloadManager.handlePachageFile(url: ipas, dl: dl) { err in
                                                                if let error = err {
                                                                        UIAlertController.showAlertWithOk(title: "Error", message: .localized("Whoops!, something went wrong when extracting the file. \nMaybe try switching the extraction library in the settings?"))
                                                                }
                                                        }
                                                }
                                        }
                                )
                        }
                        .alert(.localized("Import from URL"), isPresented: $_isDownloadingPresenting) {
                                TextField(.localized("URL"), text: $_alertDownloadString)
                                Button(.localized("Cancel"), role: .cancel) {
                                        _alertDownloadString = ""
                                }
                                Button(.localized("OK")) {
                                        if let url = URL(string: _alertDownloadString) {
                                                _ = downloadManager.startDownload(from: url, id: "FeatherManualDownload_\(UUID().uuidString)")
                                        }
                                }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("feather.installApp"))) { notification in
                if let app = _signedApps.first {
                    _selectedInstallAppPresenting = AnyApp(base: app)
                                }
                        }
                }
                .onChange(of: _isEditMode) { state in
            if !state.isEditing {
                DispatchQueue.main.asyncAfter(deadline: .now()) {
                    withAnimation{
                        _selectedApps.removeAll()
                    }
                }
            }
        }
        }
        
        /// Download all available updates at once
        private func _updateAllApps() {
                for update in updateManager.updates.values {
                        if let url = update.sourceApp.currentDownloadUrl {
                                _ = downloadManager.startDownload(from: url, id: update.sourceApp.currentUniqueId, sourceURL: update.sourceURL)
                        }
                }
        }
}

extension LibraryView {
    @ViewBuilder
    private func _importActions() -> some View {
        Button(.localized("Import from Files"), systemImage: "folder") {
            _isImportingPresenting = true
        }
        Button(.localized("Import from URL"), systemImage: "globe") {
            _isDownloadingPresenting = true
        }
    }

    /// Per-app update preference menu (⋯) shown on each update row.
    /// Lets the user set Auto-Update / Notify / Ignore for this specific app,
    /// or "Ignore this version" (version-specific ignore).
    @ViewBuilder
    private func _updatePreferenceMenu(for update: AppUpdate) -> some View {
        let bundleId = update.installedApp.identifier ?? ""
        let currentPref = UpdatePreferencesStore.shared.preference(for: bundleId)

        Menu {
            Section(.localized("Update Preference")) {
                ForEach(AppUpdatePreference.allCases, id: \.rawValue) { pref in
                    Button {
                        UpdatePreferencesStore.shared.set(pref, for: bundleId)
                        // If we just set it to ignore, force a re-check so the row disappears
                        if pref == AppUpdatePreference.ignore {
                            updateManager.clearUpdate(for: bundleId)
                        }
                    } label: {
                        Label(pref.displayName, systemImage: pref.iconName)
                    }
                }
            }

            Section {
                // "Ignore this version only" — different from "Ignore all updates"
                Button {
                    UpdatePreferencesStore.shared.ignoreVersion(update.availableVersion, for: bundleId)
                    updateManager.clearUpdate(for: bundleId)
                } label: {
                    Label {
                        Text(verbatim: .localized("Ignore v%@ only", arguments: update.availableVersion))
                    } icon: {
                        Image(systemName: "bell.slash.fill")
                    }
                }

                // Clear preference (revert to global default)
                if UpdatePreferencesStore.shared.preference(for: bundleId) != _globalDefaultPreference() {
                    Button(role: .destructive) {
                        UpdatePreferencesStore.shared.clear(for: bundleId)
                    } label: {
                        Label(.localized("Clear preference"), systemImage: "arrow.counterclockwise")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
                .foregroundStyle(currentPref == AppUpdatePreference.ignore ? .red : (currentPref == .autoUpdate ? .green : .secondary))
        }
        .buttonStyle(.borderless)
    }

    /// Read the global default preference (for comparison in the menu).
    private func _globalDefaultPreference() -> AppUpdatePreference {
        let raw = OptionsManager.shared.options.defaultUpdatePreference
        return AppUpdatePreference(rawValue: raw) ?? .notify
    }
}


// MARK: - Extension: View (Edit Mode Functions)
extension LibraryView {
        private func _bulkDeleteSelectedApps() {
                let appsToDelete = _selectedApps
                
                withAnimation(.easeInOut(duration: 0.5)) {
                        for appUUID in appsToDelete {
                                if let signedApp = _signedApps.first(where: { $0.uuid == appUUID }) {
                                        Storage.shared.deleteApp(for: signedApp)
                                } else if let importedApp = _importedApps.first(where: { $0.uuid == appUUID }) {
                                        Storage.shared.deleteApp(for: importedApp)
                                }
                        }
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        _selectedApps.removeAll()
                }
        }
}
