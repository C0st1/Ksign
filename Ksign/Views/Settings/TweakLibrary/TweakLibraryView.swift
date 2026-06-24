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
                                _showCreateFolder = true
                            } label: {
                                Text(.localized("Create Folder")).bg()
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            NBToolbarMenu(
                systemImage: "plus",
                style: .icon,
                placement: .topBarTrailing
            ) {
                Button {
                    _showCreateFolder = true
                } label: {
                    Label(.localized("New Folder"), systemImage: "folder.badge.plus")
                }
            }
            NBToolbarButton(role: .close)
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
        HStack(spacing: 12) {
            Image(systemName: TweakFile.icon(for: tweak.pathExtension))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(tweak.lastPathComponent)
                    .font(.body)
                    .lineLimit(1)
                Text(TweakFile.typeName(for: tweak.pathExtension))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

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

    // MARK: - Actions

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
    @StateObject private var _manager = TweakLibraryManager.shared

    var body: some View {
        NBList(folder.name, displayMode: .inline) {
            let tweaks = folder.tweaks
            if tweaks.isEmpty {
                Section {
                    if #available(iOS 17, *) {
                        ContentUnavailableView {
                            Label(.localized("Empty Folder"), systemImage: "folder")
                        } description: {
                            Text(.localized("This folder has no tweaks. Move tweaks here from the library."))
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
                Text(TweakFile.typeName(for: tweak.pathExtension))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - SmartFolderDetailView

/// Shows the contents of a smart folder (All / Dylibs / Debs / Recent).
struct SmartFolderDetailView: View {
    let smartFolder: SmartFolder
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
