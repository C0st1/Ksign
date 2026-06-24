//
//  TweakFolder.swift
//  Ksign
//
//  Folder model for organizing tweaks in Documents/App/Tweaks/.
//  Supports user-created folders + smart folders (All, Dylibs, Debs, Recent).
//
//  Created for Feature 3: Tweak Folders
//

import Foundation

// MARK: - TweakFile

struct TweakFile {
    /// Supported tweak file extensions
    static let supportedExtensions = ["dylib", "deb", "framework", "bundle", "appex"]

    /// Check if a file extension is a supported tweak type
    static func isTweak(_ ext: String) -> Bool {
        supportedExtensions.contains(ext.lowercased())
    }

    /// Check if a URL is a tweak file
    static func isTweak(_ url: URL) -> Bool {
        isTweak(url.pathExtension)
    }

    /// SF Symbol icon for a tweak file based on its extension
    static func icon(for ext: String) -> String {
        switch ext.lowercased() {
        case "dylib":     return "cube.box.fill"
        case "deb":       return "shippingbox.fill"
        case "framework": return "cubes.box.fill"
        case "bundle":    return "folder.badge.gearshape"
        case "appex":     return "puzzlepiece.extension.fill"
        default:          return "doc.fill"
        }
    }

    /// Human-readable type name for a tweak file
    static func typeName(for ext: String) -> String {
        switch ext.lowercased() {
        case "dylib":     return "Dylib"
        case "deb":       return "Debian Package"
        case "framework": return "Framework"
        case "bundle":    return "Bundle"
        case "appex":     return "App Extension"
        default:          return "File"
        }
    }
}

// MARK: - TweakFolder

/// Represents a user-created folder under Documents/App/Tweaks/.
/// Folders are real on-disk directories — no separate database needed.
struct TweakFolder: Identifiable, Hashable {
    let url: URL          // e.g., Documents/App/Tweaks/WhatsApp Tweaks/
    let name: String      // "WhatsApp Tweaks"
    var id: String { url.path }

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
    }

    init(name: String) {
        let dir = FileManager.default.tweaks.appendingPathComponent(name)
        self.url = dir
        self.name = name
    }

    /// All tweak files directly in this folder (non-recursive, one level only).
    var tweaks: [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { TweakFile.isTweak($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Subfolders (one level deep — no nesting beyond 2 levels to keep UI simple).
    /// Excludes .framework/.bundle/.appex directories — those are tweak files,
    /// not organizational folders.
    var subfolders: [TweakFolder] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { url in
                // Must be a directory
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                    return false
                }
                // But NOT a .framework/.bundle/.appex (those are tweak bundles, not folders)
                return !TweakFile.isTweak(url)
            }
            .map { TweakFolder(url: $0) }
            .sorted { $0.name < $1.name }
    }

    /// Number of tweaks in this folder (non-recursive).
    var tweakCount: Int { tweaks.count }

    /// Create the folder on disk if it doesn't exist.
    func create() throws {
        try FileManager.default.createDirectoryIfNeeded(at: url)
    }

    /// Delete the folder from disk.
    func delete() throws {
        try FileManager.default.removeItem(at: url)
    }

    /// Rename the folder.
    func rename(to newName: String) throws -> TweakFolder {
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        try FileManager.default.moveItem(at: url, to: newURL)
        return TweakFolder(url: newURL)
    }
}

// MARK: - SmartFolder

/// Auto-populated virtual folders based on rules.
/// Not real on-disk directories — computed from the tweaks root.
enum SmartFolder: String, CaseIterable, Identifiable {
    case all    = "All Tweaks"
    case dylibs = "Dylibs Only"
    case debs   = "Debs Only"
    case recent = "Recently Added"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .all:    return "square.grid.2x2.fill"
        case .dylibs: return "cube.box.fill"
        case .debs:   return "shippingbox.fill"
        case .recent: return "clock.arrow.circlepath"
        }
    }

    var localizedDisplayName: String {
        .localized(rawValue)
    }

    /// Returns a filtered/sorted list of tweaks from the root tweaks directory.
    /// Recursively scans all subdirectories.
    func tweaks(in rootDir: URL) -> [URL] {
        let allTweaks = Self._allTweaksRecursively(in: rootDir)
        switch self {
        case .all:
            return allTweaks.sorted { $0.lastPathComponent < $1.lastPathComponent }
        case .dylibs:
            return allTweaks
                .filter { $0.pathExtension.lowercased() == "dylib" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        case .debs:
            return allTweaks
                .filter { $0.pathExtension.lowercased() == "deb" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        case .recent:
            return allTweaks
                .sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
                .prefix(20)
                .map { $0 }
        }
    }

    /// Count of tweaks matching this smart folder's criteria.
    func count(in rootDir: URL) -> Int {
        tweaks(in: rootDir).count
    }

    /// Recursively walk the tweaks directory and collect all tweak files.
    private static func _allTweaksRecursively(in dir: URL) -> [URL] {
        var results: [URL] = []
        let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        guard let enumerator = enumerator else { return results }
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard TweakFile.isTweak(ext) else { continue }
            // For .framework and .bundle, the URL IS the directory — include it
            if ext == "framework" || ext == "bundle" {
                results.append(url)
            } else {
                // For .dylib, .deb, .appex — make sure it's a regular file
                let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                if isRegular { results.append(url) }
            }
        }
        return results
    }
}

// MARK: - TweakLibraryManager

/// Singleton that manages the tweaks directory structure.
/// Provides helpers for listing folders, creating folders, moving tweaks, etc.
final class TweakLibraryManager: ObservableObject {

    static let shared = TweakLibraryManager()

    private init() {}

    /// The root tweaks directory: Documents/App/Tweaks/
    var rootDirectory: URL { FileManager.default.tweaks }

    /// Ensure the root directory exists.
    func ensureRootExists() {
        try? FileManager.default.createDirectoryIfNeeded(at: rootDirectory)
    }

    /// All user-created folders (top-level subdirectories of the tweaks root).
    @Published var folders: [TweakFolder] = []

    /// Loose tweaks (tweak files directly in the root, not in any folder).
    @Published var looseTweaks: [URL] = []

    /// Refresh the folders + looseTweaks from disk.
    func refresh() {
        ensureRootExists()
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var newFolders: [TweakFolder] = []
        var newLoose: [URL] = []

        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            // .framework/.bundle/.appex are directories BUT they are tweak bundles,
            // not organizational folders — treat them as loose tweaks.
            if isDir && !TweakFile.isTweak(url) {
                newFolders.append(TweakFolder(url: url))
            } else if TweakFile.isTweak(url) {
                newLoose.append(url)
            }
        }

        DispatchQueue.main.async {
            self.folders = newFolders.sorted { $0.name < $1.name }
            self.looseTweaks = newLoose.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
    }

    /// Create a new folder.
    func createFolder(name: String) throws -> TweakFolder {
        let folder = TweakFolder(name: name)
        try folder.create()
        refresh()
        return folder
    }

    /// Delete a folder.
    func deleteFolder(_ folder: TweakFolder) throws {
        try folder.delete()
        refresh()
    }

    /// Rename a folder.
    func renameFolder(_ folder: TweakFolder, to newName: String) throws -> TweakFolder {
        let renamed = try folder.rename(to: newName)
        refresh()
        return renamed
    }

    /// Move a tweak file to a folder.
    func moveTweak(_ tweak: URL, to folder: TweakFolder) throws {
        let dest = folder.url.appendingPathComponent(tweak.lastPathComponent)
        try? FileManager.default.removeItem(at: dest) // overwrite if exists
        try FileManager.default.moveItem(at: tweak, to: dest)
        refresh()
    }

    /// Move a tweak file to the root (loose).
    func moveTweakToRoot(_ tweak: URL) throws {
        let dest = rootDirectory.appendingPathComponent(tweak.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tweak, to: dest)
        refresh()
    }

    /// Delete a tweak file.
    func deleteTweak(_ tweak: URL) throws {
        try FileManager.default.removeItem(at: tweak)
        refresh()
    }

    /// Total tweak count across all folders + loose.
    func totalTweakCount() -> Int {
        SmartFolder.all.count(in: rootDirectory)
    }
}

// MARK: - URL Helpers

extension URL {
    /// The modification date of the file, if available.
    var modificationDate: Date? {
        try? resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// The folder containing this tweak (relative to the tweaks root).
    /// Returns nil if the tweak is loose (directly in the root).
    var containingTweakFolder: TweakFolder? {
        let tweaksRoot = FileManager.default.tweaks
        let parent = deletingLastPathComponent()
        guard parent.path != tweaksRoot.path else { return nil }
        // Only return the immediate parent if it's a subdirectory of tweaks root
        guard parent.path.hasPrefix(tweaksRoot.path) else { return nil }
        return TweakFolder(url: parent)
    }
}
