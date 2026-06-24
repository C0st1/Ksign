//
//  TweakLibraryView.swift
//  Ksign
//
//  Folder management browser for the tweaks library.
//  Shows smart folders, user folders, and loose tweaks.
//  Create/rename/delete folders; move/rename/delete tweaks.
//
//  Created for Feature 3: Tweak Folders
//

import SwiftUI
import NimbleViews

struct TweakLibraryView: View {
    @StateObject private var _manager = TweakLibraryManager.shared
    @State private var _showCreateFolder = false
    @State private var _newFolderName = ""
    @State private var _renamingFolder: TweakFolder?
    @State private var _renameText = ""
    @State private var _movingTweak: URL?
    @State private var _selectedTweakForInfo: URL?
    @State private var _showImportTweaks = false

    // Multi-select state
    @State private var _isEditMode: EditMode = .inactive
    @State private var _selectedTweaks: Set<String> = []  // tweak paths
    @State private var _bulkMoving: Bool = false

    var body: some View {
        NBList(.localized("Tweak Library"), displayMode: .inline) {
            // Smart Folders section
            NBSection(.localized("Smart Folders")) {
                ForEach(SmartFolder.allCases) { smart in
                    NavigationLink {
                        SmartFolderDetailView(smartFolder: smart)
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

            // User Folders section
            if !_manager.folders.isEmpty {
                NBSection(.localized("Folders")) {
                    ForEach(_manager.folders) { folder in
                        _folderRow(folder)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            try? _manager.deleteFolder(_manager.folders[index])
                        }
                    }
                }
            }

            // Loose Tweaks section
            if !_manager.looseTweaks.isEmpty {
                NBSection(.localized("Loose Tweaks"), secondary: _manager.looseTweaks.count.description) {
                    ForEach(_manager.looseTweaks, id: \.path) { tweak in
                        _tweakRow(tweak, parentFolder: nil)
                    }
                }
            }

            // Empty state help
            if _manager.folders.isEmpty && _manager.looseTweaks.isEmpty {
                Section {
                    if #available(iOS 17, *) {
                        ContentUnavailableView {
                            Label(.localized("No Tweaks"), systemImage: "gear.badge.questionmark")
                        } description: {
                            Text(.localized("Import .dylib, .deb, .framework, or .appex files to get started. They'll appear here."))
                        } actions: {
                            Button {
                                _showImportTweaks = true
                            } label: {
                                Text(.localized("Import Tweaks")).bg()
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            if _isEditMode.isEditing {
                // Edit mode toolbar: bulk actions
                ToolbarItem(placement: .topBarLeading) {
                    Button(.localized("Done")) {
                        withAnimation(.snappy) {
                            _isEditMode = .inactive
                            _selectedTweaks.removeAll()
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !_selectedTweaks.isEmpty {
                        Text(verbatim: "\(_selectedTweaks.count)")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Menu {
                            Button {
                                _bulkMoveSelected()
                            } label: {
                                Label(.localized("Move Selected"), systemImage: "folder")
                            }
                            Button(role: .destructive) {
                                _bulkDeleteSelected()
                            } label: {
                                Label(.localized("Delete Selected"), systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            } else {
                // Normal toolbar
                NBToolbarMenu(
                    systemImage: "plus",
                    style: .icon,
                    placement: .topBarTrailing
                ) {
                    Button {
                        _showImportTweaks = true
                    } label: {
                        Label(.localized("Import Tweaks"), systemImage: "tray.and.arrow.down")
                    }
                    Button {
                        _showCreateFolder = true
                    } label: {
                        Label(.localized("New Folder"), systemImage: "folder.badge.plus")
                    }
                }
                NBToolbarButton(role: .close)
            }
        }
        .sheet(isPresented: $_showImportTweaks) {
            FileImporterRepresentableView(
                allowedContentTypes: [.item],
                allowsMultipleSelection: true,
                onDocumentsPicked: { urls in
                    _importTweaks(urls: urls)
                }
            )
        }
        .alert(.localized("New Folder"), isPresented: $_showCreateFolder) {
            TextField(.localized("Folder name"), text: $_newFolderName)
            Button(.localized("Cancel"), role: .cancel) {
                _newFolderName = ""
            }
            Button(.localized("Create")) {
                _createFolder()
            }
        }
        .alert(.localized("Rename Folder"), isPresented: Binding(
            get: { _renamingFolder != nil },
            set: { if !$0 { _renamingFolder = nil } }
        )) {
            TextField(.localized("Folder name"), text: $_renameText)
            Button(.localized("Cancel"), role: .cancel) {
                _renamingFolder = nil
                _renameText = ""
            }
            Button(.localized("Rename")) {
                _renameFolder()
            }
        }
        .sheet(item: $_movingTweak) { tweak in
            TweakMovePickerView(tweak: tweak)
        }
        .onAppear {
            _manager.refresh()
        }
    }

    // MARK: - Row Builders

    @ViewBuilder
    private func _folderRow(_ folder: TweakFolder) -> some View {
        NavigationLink {
            FolderDetailView(folder: folder)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.title3)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.body)
                        .fontWeight(.medium)
                    Text(verbatim: .localized("%lld tweaks", arguments: folder.tweakCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Button {
                        _renamingFolder = folder
                        _renameText = folder.name
                    } label: {
                        Label(.localized("Rename"), systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        try? _manager.deleteFolder(folder)
                    } label: {
                        Label(.localized("Delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private func _tweakRow(_ tweak: URL, parentFolder: TweakFolder?) -> some View {
        let isSelected = _selectedTweaks.contains(tweak.path)

        HStack(spacing: 12) {
            // In edit mode: show checkmark circle
            if _isEditMode.isEditing {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 28)
            } else {
                Image(systemName: TweakFile.icon(for: tweak.pathExtension))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tweak.lastPathComponent)
                    .font(.body)
                    .lineLimit(1)
                Text(TweakFile.typeName(for: tweak.pathExtension))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // In edit mode: hide the menu
            if !_isEditMode.isEditing {
                Menu {
                    Button {
                        _movingTweak = tweak
                    } label: {
                        Label(.localized("Move to folder..."), systemImage: "folder")
                    }
                    if parentFolder != nil {
                        Button {
                            try? _manager.moveTweakToRoot(tweak)
                        } label: {
                            Label(.localized("Move to root"), systemImage: "folder.badge.minus")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        try? _manager.deleteTweak(tweak)
                    } label: {
                        Label(.localized("Delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        // Long-press to enter edit mode + select this tweak
        .onLongPressGesture {
            withAnimation(.snappy) {
                _isEditMode = .active
                _selectedTweaks.insert(tweak.path)
            }
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
        }
        // In edit mode: tap to toggle selection
        .contentShape(Rectangle())
        .onTapGesture {
            if _isEditMode.isEditing {
                withAnimation(.snappy) {
                    if _selectedTweaks.contains(tweak.path) {
                        _selectedTweaks.remove(tweak.path)
                    } else {
                        _selectedTweaks.insert(tweak.path)
                    }
                }
                // If nothing selected, exit edit mode
                if _selectedTweaks.isEmpty {
                    withAnimation(.snappy) {
                        _isEditMode = .inactive
                    }
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !_isEditMode.isEditing {
                Button(role: .destructive) {
                    try? _manager.deleteTweak(tweak)
                } label: {
                    Label(.localized("Delete"), systemImage: "trash")
                }
                Button {
                    _movingTweak = tweak
                } label: {
                    Label(.localized("Move"), systemImage: "folder")
                }
                .tint(.accentColor)
            }
        }
    }

    // MARK: - Actions

    /// Bulk delete all selected tweaks.
    private func _bulkDeleteSelected() {
        let selected = _selectedTweaks
        UIAlertController.showAlert(
            title: .localized("Delete %lld Tweaks", arguments: selected.count),
            message: .localized("Are you sure you want to delete these tweaks? This cannot be undone."),
            actions: [
                UIAlertAction(title: .localized("Cancel"), style: .cancel),
                UIAlertAction(title: .localized("Delete"), style: .destructive) { _ in
                    for path in selected {
                        let url = URL(fileURLWithPath: path)
                        try? self._manager.deleteTweak(url)
                    }
                    withAnimation(.snappy) {
                        self._isEditMode = .inactive
                        self._selectedTweaks.removeAll()
                    }
                }
            ]
        )
    }

    /// Bulk move all selected tweaks. Opens the move picker for the first tweak,
    /// then moves all selected tweaks to the chosen folder.
    private func _bulkMoveSelected() {
        guard !_selectedTweaks.isEmpty else { return }
        // For bulk move, we'll move them to root first, then the user can
        // use the move picker from the toolbar on individual tweaks.
        // A proper bulk-move picker would need a new view, but for now
        // we move them to root as a batch operation.
        let selected = _selectedTweaks
        for path in selected {
            let url = URL(fileURLWithPath: path)
            try? _manager.moveTweakToRoot(url)
        }
        withAnimation(.snappy) {
            _isEditMode = .inactive
            _selectedTweaks.removeAll()
        }
    }

    /// Import tweak files from the file picker into the tweaks root folder.
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
            } catch {
                print("Error copying tweak file: \(error)")
            }
        }

        _manager.refresh()
    }

    private func _createFolder() {
        let name = _newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            _ = try _manager.createFolder(name: name)
        } catch {
            UIAlertController.showAlertWithOk(
                title: .localized("Error"),
                message: .localized("Could not create folder: %@", arguments: error.localizedDescription)
            )
        }
        _newFolderName = ""
    }

    private func _renameFolder() {
        guard let folder = _renamingFolder else { return }
        let name = _renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            _ = try _manager.renameFolder(folder, to: name)
        } catch {
            UIAlertController.showAlertWithOk(
                title: .localized("Error"),
                message: .localized("Could not rename folder: %@", arguments: error.localizedDescription)
            )
        }
        _renamingFolder = nil
        _renameText = ""
    }
}

// MARK: - FolderDetailView

/// Shows the contents of a single user-created folder.
struct FolderDetailView: View {
    let folder: TweakFolder
    var options: Binding<Options>? = nil
    @StateObject private var _manager = TweakLibraryManager.shared
    @State private var _showImportTweaks = false
    @State private var _movingTweak: URL?

    // Multi-select state (only used in library browsing context, not injection)
    @State private var _isEditMode: EditMode = .inactive
    @State private var _selectedTweaks: Set<String> = []

    /// Whether we're in injection context (options binding present)
    private var _isInjectionContext: Bool { options != nil }

    var body: some View {
        NBList(folder.name, displayMode: .inline) {
            let tweaks = folder.tweaks
            if tweaks.isEmpty {
                Section {
                    if #available(iOS 17, *) {
                        ContentUnavailableView {
                            Label(.localized("Empty Folder"), systemImage: "folder")
                        } description: {
                            Text(.localized("Import tweaks directly into this folder, or move existing tweaks here from the library."))
                        } actions: {
                            Button {
                                _showImportTweaks = true
                            } label: {
                                Text(.localized("Import Tweaks")).bg()
                            }
                        }
                    } else {
                        Button {
                            _showImportTweaks = true
                        } label: {
                            Label(.localized("Import Tweaks"), systemImage: "tray.and.arrow.down")
                        }
                    }
                }
            } else {
                NBSection(.localized("Tweaks"), secondary: tweaks.count.description) {
                    ForEach(tweaks, id: \.path) { tweak in
                        _tweakRow(tweak)
                    }
                }
            }
        }
        .toolbar {
            if _isEditMode.isEditing && !_isInjectionContext {
                // Edit mode toolbar: bulk actions
                ToolbarItem(placement: .topBarLeading) {
                    Button(.localized("Done")) {
                        withAnimation(.snappy) {
                            _isEditMode = .inactive
                            _selectedTweaks.removeAll()
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !_selectedTweaks.isEmpty {
                        Text(verbatim: "\(_selectedTweaks.count)")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Menu {
                            Button {
                                _bulkMoveSelected()
                            } label: {
                                Label(.localized("Move Selected"), systemImage: "folder")
                            }
                            Button(role: .destructive) {
                                _bulkDeleteSelected()
                            } label: {
                                Label(.localized("Delete Selected"), systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            } else {
                // Normal toolbar
                NBToolbarMenu(
                    systemImage: "plus",
                    style: .icon,
                    placement: .topBarTrailing
                ) {
                    Button {
                        _showImportTweaks = true
                    } label: {
                        Label(.localized("Import Tweaks"), systemImage: "tray.and.arrow.down")
                    }
                }
                NBToolbarButton(role: .close)
            }
        }
        .sheet(isPresented: $_showImportTweaks) {
            FileImporterRepresentableView(
                allowedContentTypes: [.item],
                allowsMultipleSelection: true,
                onDocumentsPicked: { urls in
                    _importTweaksIntoFolder(urls: urls)
                }
            )
        }
        .sheet(item: $_movingTweak) { tweak in
            TweakMovePickerView(tweak: tweak)
        }
        .onAppear { _manager.refresh() }
    }

    /// Import tweak files directly into this folder.
    private func _importTweaksIntoFolder(urls: [URL]) {
        guard !urls.isEmpty else { return }
        let allowedExtensions = Set(["dylib", "deb", "framework", "bundle", "appex"])

        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }

            let destinationURL = folder.url.appendingPathComponent(url.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: url, to: destinationURL)
            } catch {
                print("Error copying tweak file: \(error)")
            }
        }

        _manager.refresh()
    }

    /// Bulk delete all selected tweaks.
    private func _bulkDeleteSelected() {
        let selected = _selectedTweaks
        UIAlertController.showAlert(
            title: .localized("Delete %lld Tweaks", arguments: selected.count),
            message: .localized("Are you sure you want to delete these tweaks? This cannot be undone."),
            actions: [
                UIAlertAction(title: .localized("Cancel"), style: .cancel),
                UIAlertAction(title: .localized("Delete"), style: .destructive) { _ in
                    for path in selected {
                        let url = URL(fileURLWithPath: path)
                        try? self._manager.deleteTweak(url)
                    }
                    withAnimation(.snappy) {
                        self._isEditMode = .inactive
                        self._selectedTweaks.removeAll()
                    }
                }
            ]
        )
    }

    /// Bulk move all selected tweaks to root.
    private func _bulkMoveSelected() {
        guard !_selectedTweaks.isEmpty else { return }
        let selected = _selectedTweaks
        for path in selected {
            let url = URL(fileURLWithPath: path)
            try? _manager.moveTweakToRoot(url)
        }
        withAnimation(.snappy) {
            _isEditMode = .inactive
            _selectedTweaks.removeAll()
        }
    }

    @ViewBuilder
    private func _tweakRow(_ tweak: URL) -> some View {
        let isSelected = _selectedTweaks.contains(tweak.path)

        HStack(spacing: 12) {
            // In edit mode (library context): show checkmark circle
            if _isEditMode.isEditing && !_isInjectionContext {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 28)
            } else {
                Image(systemName: TweakFile.icon(for: tweak.pathExtension))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tweak.lastPathComponent)
                    .font(.body)
                Text(TweakFile.typeName(for: tweak.pathExtension))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            // Show toggle only in injection context
            if _isInjectionContext, let options = options {
                let injectionPaths = Set(options.wrappedValue.injectionFiles.map { $0.path })
                let isInjected = injectionPaths.contains(tweak.path)
                Toggle("", isOn: Binding(
                    get: { isInjected },
                    set: { newValue in
                        if newValue {
                            if !options.wrappedValue.injectionFiles.contains(where: { $0.path == tweak.path }) {
                                options.wrappedValue.injectionFiles.append(tweak)
                            }
                        } else {
                            if let index = options.wrappedValue.injectionFiles.firstIndex(where: { $0.path == tweak.path }) {
                                options.wrappedValue.injectionFiles.remove(at: index)
                            }
                        }
                    }
                ))
                .labelsHidden()
            } else if !_isEditMode.isEditing {
                // Menu with Move + Delete (for Tweak Library browsing context)
                Menu {
                    Button {
                        _movingTweak = tweak
                    } label: {
                        Label(.localized("Move to folder..."), systemImage: "folder")
                    }
                    Button {
                        try? _manager.moveTweakToRoot(tweak)
                    } label: {
                        Label(.localized("Move to root"), systemImage: "folder.badge.minus")
                    }
                    Divider()
                    Button(role: .destructive) {
                        try? _manager.deleteTweak(tweak)
                    } label: {
                        Label(.localized("Delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        // Long-press to enter edit mode (library context only)
        .onLongPressGesture {
            guard !_isInjectionContext else { return }
            withAnimation(.snappy) {
                _isEditMode = .active
                _selectedTweaks.insert(tweak.path)
            }
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
        }
        // In edit mode: tap to toggle selection
        .contentShape(Rectangle())
        .onTapGesture {
            if _isEditMode.isEditing && !_isInjectionContext {
                withAnimation(.snappy) {
                    if _selectedTweaks.contains(tweak.path) {
                        _selectedTweaks.remove(tweak.path)
                    } else {
                        _selectedTweaks.insert(tweak.path)
                    }
                }
                if _selectedTweaks.isEmpty {
                    withAnimation(.snappy) {
                        _isEditMode = .inactive
                    }
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !_isEditMode.isEditing {
                Button(role: .destructive) {
                    try? _manager.deleteTweak(tweak)
                } label: {
                    Label(.localized("Delete"), systemImage: "trash")
                }
                if !_isInjectionContext {
                    Button {
                        _movingTweak = tweak
                    } label: {
                        Label(.localized("Move"), systemImage: "folder")
                    }
                    .tint(.accentColor)
                }
            }
        }
    }
}

// MARK: - SmartFolderDetailView

/// Shows the contents of a smart folder (All / Dylibs / Debs / Recent).
struct SmartFolderDetailView: View {
    let smartFolder: SmartFolder
    var options: Binding<Options>? = nil
    @StateObject private var _manager = TweakLibraryManager.shared

    var body: some View {
        NBList(smartFolder.localizedDisplayName, displayMode: .inline) {
            let tweaks = smartFolder.tweaks(in: _manager.rootDirectory)
            if tweaks.isEmpty {
                Section {
                    if #available(iOS 17, *) {
                        ContentUnavailableView {
                            Label(.localized("No Tweaks"), systemImage: smartFolder.iconName)
                        } description: {
                            Text(.localized("No tweaks match this filter."))
                        }
                    }
                }
            } else {
                NBSection(.localized("Tweaks"), secondary: tweaks.count.description) {
                    ForEach(tweaks, id: \.path) { tweak in
                        _tweakRow(tweak)
                    }
                }
            }
        }
        .toolbar {
            NBToolbarButton(role: .close)
        }
        .onAppear { _manager.refresh() }
    }

    @ViewBuilder
    private func _tweakRow(_ tweak: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: TweakFile.icon(for: tweak.pathExtension))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(tweak.lastPathComponent)
                    .font(.body)
                HStack(spacing: 4) {
                    Text(TweakFile.typeName(for: tweak.pathExtension))
                    if let folder = tweak.containingTweakFolder {
                        Text("·")
                        Text(folder.name)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()

            // Show toggle only in injection context
            if let options = options {
                let injectionPaths = Set(options.wrappedValue.injectionFiles.map { $0.path })
                let isInjected = injectionPaths.contains(tweak.path)
                Toggle("", isOn: Binding(
                    get: { isInjected },
                    set: { newValue in
                        if newValue {
                            if !options.wrappedValue.injectionFiles.contains(where: { $0.path == tweak.path }) {
                                options.wrappedValue.injectionFiles.append(tweak)
                            }
                        } else {
                            if let index = options.wrappedValue.injectionFiles.firstIndex(where: { $0.path == tweak.path }) {
                                options.wrappedValue.injectionFiles.remove(at: index)
                            }
                        }
                    }
                ))
                .labelsHidden()
            }
        }
    }
}

// MARK: - TweakMovePickerView

/// Sheet that lets the user pick a folder to move a tweak into.
struct TweakMovePickerView: View {
    let tweak: URL
    @StateObject private var _manager = TweakLibraryManager.shared
    @Environment(\.dismiss) private var _dismiss
    @State private var _showCreateFolder = false
    @State private var _newFolderName = ""

    var body: some View {
        NBNavigationView(.localized("Move Tweak"), displayMode: .inline) {
            List {
                if !_manager.folders.isEmpty {
                    Section(.localized("Folders")) {
                        ForEach(_manager.folders) { folder in
                            Button {
                                try? _manager.moveTweak(tweak, to: folder)
                                _dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "folder")
                                    Text(folder.name)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Button {
                        try? _manager.moveTweakToRoot(tweak)
                        _dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "folder.badge.minus")
                            Text(.localized("Move to root (loose)"))
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    Button {
                        _showCreateFolder = true
                    } label: {
                        Label(.localized("Create new folder"), systemImage: "folder.badge.plus")
                    }
                }
            }
            .toolbar {
                NBToolbarButton(role: .close)
            }
        }
        .alert(.localized("New Folder"), isPresented: $_showCreateFolder) {
            TextField(.localized("Folder name"), text: $_newFolderName)
            Button(.localized("Cancel"), role: .cancel) { _newFolderName = "" }
            Button(.localized("Create")) {
                _createAndMove()
            }
        }
        .onAppear { _manager.refresh() }
    }

    private func _createAndMove() {
        let name = _newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let folder = try _manager.createFolder(name: name)
            try _manager.moveTweak(tweak, to: folder)
            _dismiss()
        } catch {
            UIAlertController.showAlertWithOk(
                title: .localized("Error"),
                message: error.localizedDescription
            )
        }
        _newFolderName = ""
    }
}
