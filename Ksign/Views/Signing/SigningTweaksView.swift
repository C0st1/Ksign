//
//  SigningTweaksView.swift
//  Feather
//
//  Created by samara on 20.04.2025.
//
//  Modified for Feature 3: Tweak Folders — Added Tweaks now grouped by
//  source folder, Available Tweaks browsable via folder structure.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct SigningTweaksView: View {
        @State private var _isAddingPresenting = false
        @State private var _tweaksInDirectory: [URL] = []
        @State private var _enabledTweaks: Set<URL> = []
        @State private var _showFolderPicker = false
        @State private var _loadOrderConflicts: [TweakLoadOrderConflict] = []
        @State private var _isValidating = false
        @State private var _dependencyCheckResult: DependencyResolutionResult?
        @State private var _dependencyCheckTweakName: String = ""
        @State private var _isRescanning = false

        @Binding var options: Options

        // MARK: Body
        var body: some View {
                NBList(.localized("Tweaks")) {
                        NBSection(.localized("Injection")) {
                                Picker(selection: $options.injectPath) {
                                        ForEach(Options.InjectPath.allCases, id: \.rawValue) { path in
                                                Text(path.localizedDescription).tag(path)
                                        }
                                } label: {
                                        Label(.localized("Injection Path"), systemImage: "doc.badge.gearshape")
                                }
                                Picker(selection: $options.injectFolder) {
                                        ForEach(Options.InjectFolder.allCases, id: \.rawValue) { folder in
                                                Text(folder.localizedDescription).tag(folder)
                                        }
                                } label: {
                                        Label(.localized("Injection Folder"), systemImage: "folder.badge.gearshape")
                                }
                                Toggle(isOn: $options.injectIntoExtensions) {
                                        Label(.localized("Inject into Extensions"), systemImage: "syringe")
                                }
                        }

                        // Injection Order — drag-to-reorder with validation
                        if options.injectionFiles.count > 1 {
                                _injectionOrderSection
                        }

                        // Injected Tweaks — tweaks currently in the injection list
                        if !options.injectionFiles.isEmpty {
                                _injectedTweaksSection
                        }

                        // Available Tweaks — tweaks on disk NOT in the injection list
                        _availableTweaksSection
                }
                .overlay(alignment: .center) {
                        if options.injectionFiles.isEmpty && _tweaksInDirectory.isEmpty && TweakLibraryManager.shared.folders.isEmpty {
                                if #available(iOS 17, *) {
                                        ContentUnavailableView {
                                                Label(.localized("No Tweaks"), systemImage: "gear.badge.questionmark")
                                        } description: {
                                                Text(verbatim: .localized("Importing your .dylib, .deb, .framework or .appex files \n These will also be automatically added to Tweaks folder"))
                        } actions: {
                                                Button {
                                                        _isAddingPresenting = true
                                                } label: {
                                                        Text("Import").bg()
                                                }
                                        }
                                } else {
                                        Text(verbatim: .localized("Importing your .dylib, .deb, .framework or .appex files \n These will also be automatically added to Tweaks folder"))
                                                .foregroundColor(.secondary)
                                                .frame(maxWidth: .infinity, alignment: .center)
                                                .padding()
                                }
                        }
                }
                .navigationTitle(.localized("Tweaks"))
                .listStyle(.plain)
                .toolbar {
                        NBToolbarMenu(
                                systemImage: "plus",
                                style: .icon,
                                placement: .topBarTrailing
                        ) {
                                Button {
                                        _isAddingPresenting = true
                                } label: {
                                        Label(.localized("Import Tweaks"), systemImage: "tray.and.arrow.down")
                                }
                                Button {
                                        _showFolderPicker = true
                                } label: {
                                        Label(.localized("Browse Library"), systemImage: "folder")
                                }
                                Divider()
                                Button {
                                        _rescanDependencies()
                                } label: {
                                        if _isRescanning {
                                                HStack {
                                                        ProgressView().scaleEffect(0.7)
                                                        Text(verbatim: .localized("Scanning..."))
                                                }
                                        } else {
                                                Label(.localized("Re-scan Dependencies"), systemImage: "magnifyingglass")
                                        }
                                }
                                .disabled(options.injectionFiles.isEmpty || _isRescanning)
                        }
                }
                .sheet(isPresented: $_isAddingPresenting) {
                        FileImporterRepresentableView(
                                allowedContentTypes: [.item],
                                allowsMultipleSelection: true,
                                onDocumentsPicked: { urls in
                                        _importTweaksWithDependencyCheck(urls: urls)
                                }
                        )
                }
                .sheet(isPresented: $_showFolderPicker) {
                        TweakInjectionPickerView(options: $options)
                }
                .sheet(item: $_dependencyCheckResult) { result in
                        DependencyCheckSheet(
                                scanResult: result,
                                tweakName: _dependencyCheckTweakName,
                                bundleId: nil,
                                options: $options
                        )
                }
                .onAppear(perform: _loadTweaks)
        }

        // MARK: - Injection Order Section (Feature 1: Tweak Load Order Controller)

        @ViewBuilder
        private var _injectionOrderSection: some View {
                NBSection(.localized("Injection Order"), secondary: options.injectionFiles.count.description) {
                        // Drag-to-reorder list
                        ForEach(options.injectionFiles, id: \.absoluteString) { tweak in
                                _loadOrderRow(tweak)
                        }
                        .onMove { source, destination in
                                options.injectionFiles.move(fromOffsets: source, toOffset: destination)
                                _validateLoadOrder()
                        }

                        // Validation summary
                        if !_loadOrderConflicts.isEmpty {
                                _validationSummary
                        }

                        // Auto-fix button
                        if !_loadOrderConflicts.isEmpty {
                                Button {
                                        _autoFixOrder()
                                } label: {
                                        Label(.localized("Auto-fix order"), systemImage: "wand.and.stars")
                                }
                        }

                        // Manual re-validate button
                        Button {
                                _validateLoadOrder()
                        } label: {
                                if _isValidating {
                                        HStack {
                                                ProgressView().scaleEffect(0.8)
                                                Text(verbatim: .localized("Validating..."))
                                        }
                                } else {
                                        Label(.localized("Re-validate"), systemImage: "checkmark.shield")
                                }
                        }
                        .disabled(_isValidating)
                }
        }

        @ViewBuilder
        private func _loadOrderRow(_ tweak: URL) -> some View {
                let index = options.injectionFiles.firstIndex(of: tweak) ?? 0
                let basename = tweak.lastPathComponent
                let isSubstrate = basename.lowercased().contains("cydiasubstrate") || basename.lowercased().contains("ellekit")
                let hasConflict = _loadOrderConflicts.contains { $0.earlierTweak == basename || $0.laterTweak == basename }

                HStack(spacing: 10) {
                        // Position number
                        Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .center)

                        Image(systemName: TweakFile.icon(for: tweak.pathExtension))
                                .foregroundStyle(isSubstrate ? .yellow : .accentColor)
                                .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                                Text(basename)
                                        .font(.body)
                                        .lineLimit(1)
                                if isSubstrate {
                                        Text(verbatim: .localized("Substrate"))
                                                .font(.caption2)
                                                .foregroundStyle(.yellow)
                                }
                        }

                        Spacer()

                        if hasConflict {
                                Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                        }
                }
        }

        @ViewBuilder
        private var _validationSummary: some View {
                let errors = _loadOrderConflicts.filter { $0.severity == .error }
                let warnings = _loadOrderConflicts.filter { $0.severity == .warning }

                VStack(alignment: .leading, spacing: 4) {
                        if !errors.isEmpty {
                                HStack(spacing: 4) {
                                        Image(systemName: "xmark.octagon.fill")
                                                .foregroundStyle(.red)
                                        Text(verbatim: .localized("%lld errors", arguments: errors.count))
                                                .foregroundStyle(.red)
                                }
                                .font(.caption)
                        }
                        if !warnings.isEmpty {
                                HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundStyle(.orange)
                                        Text(verbatim: .localized("%lld warnings", arguments: warnings.count))
                                                .foregroundStyle(.orange)
                                }
                                .font(.caption)
                        }

                        // Show first conflict reason
                        if let first = _loadOrderConflicts.first {
                                Text(first.reason)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                        }
                }
        }

        // MARK: - Validation Actions

        private func _validateLoadOrder() {
                _isValidating = true
                DispatchQueue.global(qos: .userInitiated).async {
                        let conflicts = TweakLoadOrderValidator.validate(order: options.injectionFiles)
                        DispatchQueue.main.async {
                                _loadOrderConflicts = conflicts
                                _isValidating = false
                        }
                }
        }

        private func _autoFixOrder() {
                _isValidating = true
                DispatchQueue.global(qos: .userInitiated).async {
                        let fixed = TweakLoadOrderValidator.autoFix(order: options.injectionFiles)
                        let conflicts = TweakLoadOrderValidator.validate(order: fixed)
                        DispatchQueue.main.async {
                                options.injectionFiles = fixed
                                _loadOrderConflicts = conflicts
                                _isValidating = false
                        }
                }
        }

        // MARK: - Injected Tweaks Section (tweaks in options.injectionFiles)

        @ViewBuilder
        private var _injectedTweaksSection: some View {
                NBSection(.localized("Injected Tweaks"), secondary: options.injectionFiles.count.description) {
                        ForEach(options.injectionFiles, id: \.path) { tweak in
                                _injectedTweakRow(tweak)
                        }
                }
        }

        @ViewBuilder
        private func _injectedTweakRow(_ tweak: URL) -> some View {
                HStack(spacing: 10) {
                        Image(systemName: TweakFile.icon(for: tweak.pathExtension))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                                Text(tweak.lastPathComponent)
                                        .font(.body)
                                        .lineLimit(1)
                                // Show the source folder as a subtitle
                                if let folder = tweak.containingTweakFolder {
                                        Text(folder.name)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                } else {
                                        Text(verbatim: .localized("Root"))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                }
                        }

                        Spacer()

                        // Substrate badge
                        let bn = tweak.lastPathComponent.lowercased()
                        if bn.contains("substrate") || bn.contains("ellekit") || bn.contains("libhooker") {
                                Text(verbatim: .localized("Substrate"))
                                        .font(.caption2)
                                        .foregroundStyle(.yellow)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.yellow.opacity(0.15))
                                        .clipShape(Capsule())
                        }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        // Remove from injection list ONLY (don't delete from disk)
                        Button(role: .destructive) {
                                if let index = options.injectionFiles.firstIndex(where: { $0.path == tweak.path }) {
                                        options.injectionFiles.remove(at: index)
                                }
                                _enabledTweaks = Set(options.injectionFiles)
                                _loadTweaks()
                        } label: {
                                Label(.localized("Remove"), systemImage: "minus.circle")
                        }
                }
        }

        // MARK: - Available Tweaks Section (all tweaks on disk, toggle to inject)

        @ViewBuilder
        private var _availableTweaksSection: some View {
                let manager = TweakLibraryManager.shared

                // Show ALL loose tweaks — the toggle shows whether each is injected.
                // Don't filter out injected ones; the toggle IS the inject control.
                let allLoose = _tweaksInDirectory

                // Show if there are folders OR loose tweaks
                if !manager.folders.isEmpty || !allLoose.isEmpty {
                        NBSection(.localized("Available Tweaks")) {
                                // Smart folder shortcuts
                                NavigationLink {
                                        SmartFolderDetailView(smartFolder: .all, options: $options)
                                } label: {
                                        HStack {
                                                Image(systemName: "square.grid.2x2.fill")
                                                        .foregroundStyle(Color.accentColor)
                                                        .frame(width: 24)
                                                Text(verbatim: .localized("All Tweaks"))
                                                Spacer()
                                                Text("\(SmartFolder.all.count(in: manager.rootDirectory))")
                                                        .foregroundStyle(.secondary)
                                                        .font(.caption)
                                        }
                                }

                                // User folders (drill-down to pick tweaks)
                                ForEach(manager.folders) { folder in
                                        NavigationLink {
                                                FolderDetailView(folder: folder, options: $options)
                                        } label: {
                                                HStack {
                                                        Image(systemName: "folder.fill")
                                                                .foregroundStyle(Color.accentColor)
                                                                .frame(width: 24)
                                                        Text(folder.name)
                                                        Spacer()
                                                        Text(verbatim: .localized("%lld", arguments: folder.tweakCount))
                                                                .foregroundStyle(.secondary)
                                                                .font(.caption)
                                                }
                                        }
                                }

                                // All loose tweaks (toggle to inject/uninject)
                                ForEach(allLoose, id: \.path) { tweak in
                                        _availableTweakRow(tweak)
                                }
                        }
                }
        }

        @ViewBuilder
        private func _availableTweakRow(_ tweak: URL) -> some View {
                let injectionPaths = Set(options.injectionFiles.map { $0.path })
                let isInjected = injectionPaths.contains(tweak.path)

                HStack(spacing: 10) {
                        Image(systemName: TweakFile.icon(for: tweak.pathExtension))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 24)

                        Text(tweak.lastPathComponent)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)

                        Toggle("", isOn: Binding(
                                get: { isInjected },
                                set: { newValue in
                                        if newValue {
                                                if !options.injectionFiles.contains(where: { $0.path == tweak.path }) {
                                                        options.injectionFiles.append(tweak)
                                                        _enabledTweaks.insert(tweak)
                                                        _checkDependenciesForTweak(tweak)
                                                }
                                        } else {
                                                if let index = options.injectionFiles.firstIndex(where: { $0.path == tweak.path }) {
                                                        options.injectionFiles.remove(at: index)
                                                }
                                                _enabledTweaks.remove(tweak)
                                        }
                                }
                        ))
                        .labelsHidden()
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        // Delete from DISK (since it's not injected)
                        Button(role: .destructive) {
                                do {
                                        try FileManager.default.removeItem(at: tweak)
                                        } catch {
                                        print("Error deleting tweak: \(error)")
                                }
                                _loadTweaks()
                        } label: {
                                Label(.localized("Delete"), systemImage: "trash")
                        }
                }
        }

        private func _loadTweaks() {
                let tweaksDir = FileManager.default.tweaks
                guard let files = try? FileManager.default.contentsOfDirectory(
                        at: tweaksDir,
                        includingPropertiesForKeys: nil
                ) else {
                        TweakLibraryManager.shared.refresh()
                        return
                }

        _tweaksInDirectory = files.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "dylib" || ext == "deb" || ext == "framework" || ext == "bundle" || ext == "appex"
        }

                _enabledTweaks = Set(options.injectionFiles)
                TweakLibraryManager.shared.refresh()

                // Validate load order if there are multiple tweaks (Feature 1)
                if options.injectionFiles.count > 1 {
                        _validateLoadOrder()
                }
        }

    private func _importTweaks(urls: [URL]) {
        guard !urls.isEmpty else { return }
        let tweaksDir = FileManager.default.tweaks

        do {
            try FileManager.default.createDirectoryIfNeeded(at: tweaksDir)
        } catch {
            print("Error creating tweaks directory: \(error)")
            return
        }

        let allowedExtensions = Set(["dylib", "deb", "framework", "bundle", "appex"])

        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }

            let destinationURL = tweaksDir.appendingPathComponent(url.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: url, to: destinationURL)
                if !options.injectionFiles.contains(destinationURL) {
                    options.injectionFiles.append(destinationURL)
                }
            } catch {
                print("Error copying tweak file: \(error)")
            }
        }

        _loadTweaks()
    }

    // MARK: - Feature 2: Tweak Dependency Auto-Resolver

    /// Import tweaks AND run a dependency check on them.
    /// If any have missing deps, show the DependencyCheckSheet before finalizing.
    private func _importTweaksWithDependencyCheck(urls: [URL]) {
        guard !urls.isEmpty else { return }

        // First, do the actual import (copy files + add to injectionFiles)
        _importTweaks(urls: urls)

        // Then scan the newly-added tweaks for dependencies
        let tweaksDir = FileManager.default.tweaks
        let newTweakURLs = urls.compactMap { url -> URL? in
            let ext = url.pathExtension.lowercased()
            guard TweakFile.isTweak(ext) else { return nil }
            return tweaksDir.appendingPathComponent(url.lastPathComponent)
        }

        guard !newTweakURLs.isEmpty else { return }

        _isRescanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            // Scan each new tweak
            var allDeps: [TweakDependency] = []
            for tweakURL in newTweakURLs {
                let result = TweakDependencyResolver.resolve(
                    tweakURL: tweakURL,
                    injectionFiles: options.injectionFiles
                )
                allDeps.append(contentsOf: result.dependencies)
            }

            // Dedupe by raw path
            var seen: Set<String> = []
            let deduped = allDeps.filter { dep in
                if seen.contains(dep.rawPath) { return false }
                seen.insert(dep.rawPath)
                return true
            }

            let unresolved = deduped.filter { $0.resolution != .alreadyPresent }
            let autoResolvable = unresolved.filter { $0.resolution != .cannotResolve && $0.resolution != .alreadyPresent }

            let result = DependencyResolutionResult(
                dependencies: deduped,
                unresolved: unresolved,
                autoResolvable: autoResolvable
            )

            let tweakName = newTweakURLs.count == 1
                ? newTweakURLs[0].lastPathComponent
                : .localized("%lld tweaks", arguments: newTweakURLs.count)

            DispatchQueue.main.async {
                _dependencyCheckTweakName = tweakName
                _dependencyCheckResult = result
                _isRescanning = false
            }
        }
    }

    /// Re-scan all currently-added tweaks for dependencies (toolbar button).
    private func _rescanDependencies() {
        guard !options.injectionFiles.isEmpty else { return }

        _isRescanning = true
        let currentFiles = options.injectionFiles

        DispatchQueue.global(qos: .userInitiated).async {
            let result = TweakDependencyResolver.resolveAll(
                tweaks: currentFiles,
                injectionFiles: currentFiles
            )

            let tweakName = currentFiles.count == 1
                ? currentFiles[0].lastPathComponent
                : .localized("%lld tweaks", arguments: currentFiles.count)

            DispatchQueue.main.async {
                _dependencyCheckTweakName = tweakName
                _dependencyCheckResult = result
                _isRescanning = false
            }
        }
    }

    /// Check dependencies for a single tweak that was just toggled ON
    /// from the "Available Tweaks" section (not imported).
    /// Shows the DependencyCheckSheet if any deps are missing.
    private func _checkDependenciesForTweak(_ tweak: URL) {
        let currentFiles = options.injectionFiles
        DispatchQueue.global(qos: .userInitiated).async {
            let result = TweakDependencyResolver.resolve(
                tweakURL: tweak,
                injectionFiles: currentFiles
            )

            // Only show the sheet if there are unresolved deps —
            // don't interrupt the user with "all good" sheets.
            guard !result.unresolved.isEmpty else { return }

            DispatchQueue.main.async {
                _dependencyCheckTweakName = tweak.lastPathComponent
                _dependencyCheckResult = result
            }
        }
    }
}

// MARK: - Extension: View
extension SigningTweaksView {
}

// MARK: - TweakInjectionPickerView

/// Folder-aware picker sheet for selecting tweaks to inject.
/// Shows smart folders + user folders + loose tweaks with multi-select.
struct TweakInjectionPickerView: View {
        @Binding var options: Options
        @Environment(\.dismiss) private var _dismiss
        @StateObject private var _manager = TweakLibraryManager.shared
        @State private var _selectedTweaks: Set<URL> = []

        var body: some View {
                NBNavigationView(.localized("Add Tweaks"), displayMode: .inline) {
                        List {
                                // Smart folders (drill-down)
                                Section(.localized("Smart Folders")) {
                                        ForEach(SmartFolder.allCases) { smart in
                                                NavigationLink {
                                                        SmartFolderPickerView(smartFolder: smart, selectedTweaks: $_selectedTweaks)
                                                } label: {
                                                        HStack {
                                                                Image(systemName: smart.iconName)
                                                                        .foregroundStyle(Color.accentColor)
                                                                        .frame(width: 24)
                                                                Text(smart.localizedDisplayName)
                                                                Spacer()
                                                                Text("\(smart.count(in: _manager.rootDirectory))")
                                                                        .foregroundStyle(.secondary)
                                                                        .font(.caption)
                                                        }
                                                }
                                        }
                                }

                                // User folders (drill-down)
                                if !_manager.folders.isEmpty {
                                        Section(.localized("Folders")) {
                                                ForEach(_manager.folders) { folder in
                                                        NavigationLink {
                                                                FolderPickerView(folder: folder, selectedTweaks: $_selectedTweaks)
                                                        } label: {
                                                                HStack {
                                                                        Image(systemName: "folder.fill")
                                                                                .foregroundStyle(Color.accentColor)
                                                                                .frame(width: 24)
                                                                        Text(folder.name)
                                                                        Spacer()
                                                                        Text("\(folder.tweakCount)")
                                                                                .foregroundStyle(.secondary)
                                                                                .font(.caption)
                                                                }
                                                        }
                                                }
                                        }
                                }

                                // Loose tweaks (direct toggle)
                                if !_manager.looseTweaks.isEmpty {
                                        Section(.localized("Loose Tweaks")) {
                                                ForEach(_manager.looseTweaks, id: \.path) { tweak in
                                                        _toggleRow(tweak)
                                                }
                                        }
                                }
                        }
                        .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                        Button(.localized("Cancel")) {
                                                _dismiss()
                                        }
                                }
                                ToolbarItem(placement: .topBarTrailing) {
                                        Button {
                                                _addSelected()
                                        } label: {
                                                Text(verbatim: .localized("Add %lld", arguments: _selectedTweaks.count))
                                        }
                                        .disabled(_selectedTweaks.isEmpty)
                                }
                        }
                }
                .onAppear { _manager.refresh() }
        }

        @ViewBuilder
        private func _toggleRow(_ tweak: URL) -> some View {
                HStack(spacing: 10) {
                        Image(systemName: TweakFile.icon(for: tweak.pathExtension))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 24)
                        Text(tweak.lastPathComponent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("", isOn: Binding(
                                get: { _selectedTweaks.contains(tweak) },
                                set: { isOn in
                                        if isOn { _selectedTweaks.insert(tweak) }
                                        else { _selectedTweaks.remove(tweak) }
                                }
                        ))
                        .labelsHidden()
                }
        }

        private func _addSelected() {
                for tweak in _selectedTweaks {
                        if !options.injectionFiles.contains(tweak) {
                                options.injectionFiles.append(tweak)
                        }
                }
                _dismiss()
        }
}

// MARK: - FolderPickerView (drill-down for user folders)

struct FolderPickerView: View {
        let folder: TweakFolder
        @Binding var selectedTweaks: Set<URL>
        @Environment(\.dismiss) private var _dismiss

        var body: some View {
                List {
                        let tweaks = folder.tweaks
                        if tweaks.isEmpty {
                                Section {
                                        Text(verbatim: .localized("This folder is empty."))
                                                .foregroundStyle(.secondary)
                                }
                        } else {
                                Section(.localized("Tweaks")) {
                                        ForEach(tweaks, id: \.path) { tweak in
                                                _toggleRow(tweak)
                                        }
                                }
                        }
                }
                .navigationTitle(folder.name)
                .navigationBarTitleDisplayMode(.inline)
        }

        @ViewBuilder
        private func _toggleRow(_ tweak: URL) -> some View {
                HStack(spacing: 10) {
                        Image(systemName: TweakFile.icon(for: tweak.pathExtension))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 24)
                        Text(tweak.lastPathComponent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("", isOn: Binding(
                                get: { selectedTweaks.contains(tweak) },
                                set: { isOn in
                                        if isOn { selectedTweaks.insert(tweak) }
                                        else { selectedTweaks.remove(tweak) }
                                }
                        ))
                        .labelsHidden()
                }
        }
}

// MARK: - SmartFolderPickerView (drill-down for smart folders)

struct SmartFolderPickerView: View {
        let smartFolder: SmartFolder
        @Binding var selectedTweaks: Set<URL>
        @StateObject private var _manager = TweakLibraryManager.shared

        var body: some View {
                List {
                        let tweaks = smartFolder.tweaks(in: _manager.rootDirectory)
                        if tweaks.isEmpty {
                                Section {
                                        Text(verbatim: .localized("No tweaks match this filter."))
                                                .foregroundStyle(.secondary)
                                }
                        } else {
                                Section(.localized("Tweaks")) {
                                        ForEach(tweaks, id: \.path) { tweak in
                                                _toggleRow(tweak)
                                        }
                                }
                        }
                }
                .navigationTitle(smartFolder.localizedDisplayName)
                .navigationBarTitleDisplayMode(.inline)
                .onAppear { _manager.refresh() }
        }

        @ViewBuilder
        private func _toggleRow(_ tweak: URL) -> some View {
                HStack(spacing: 10) {
                        Image(systemName: TweakFile.icon(for: tweak.pathExtension))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                                Text(tweak.lastPathComponent)
                                if let folder = tweak.containingTweakFolder {
                                        Text(folder.name)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("", isOn: Binding(
                                get: { selectedTweaks.contains(tweak) },
                                set: { isOn in
                                        if isOn { selectedTweaks.insert(tweak) }
                                        else { selectedTweaks.remove(tweak) }
                                }
                        ))
                        .labelsHidden()
                }
        }
}
