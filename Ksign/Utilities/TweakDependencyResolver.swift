//
//  TweakDependencyResolver.swift
//  Ksign
//
//  Pre-flight scanner that detects missing dependencies when a tweak
//  is added to the injection list. Categorizes deps and offers one-tap
//  resolution (Inject ElleKit for CydiaSubstrate, find on disk, etc.).
//
//  Created for Feature 2: Tweak Dependency Auto-Resolver
//

import Foundation

// MARK: - TweakDependency

/// Represents a single dependency of a tweak, with its resolution status.
struct TweakDependency: Identifiable, Equatable {
    let id = UUID()
    let tweakURL: URL                  // the tweak that has this dep
    let rawPath: String                // "@rpath/CydiaSubstrate.framework/CydiaSubstrate"
    let resolvedPath: URL?             // on-disk path if found, nil if missing
    let category: Category
    let resolution: Resolution

    /// The basename of the dependency (e.g., "CydiaSubstrate")
    var basename: String {
        URL(fileURLWithPath: rawPath).lastPathComponent
    }

    /// The tweak that has this dependency (basename)
    var tweakBasename: String {
        tweakURL.lastPathComponent
    }

    enum Category: Equatable {
        case substrate           // CydiaSubstrate.framework
        case ellekit             // ElleKit.dylib
        case libhooker           // libhooker.dylib
        case tweakDependency     // another tweak in the user's list
        case systemLibrary       // /usr/lib/... (never missing)
        case bundledFramework    // already in the .app bundle
        case unknown             // can't categorize
    }

    enum Resolution: Equatable {
        case alreadyPresent      // no action needed
        case injectEllekit       // add ellekit.deb (bundled) — for CydiaSubstrate deps
        case addToInjectionList(URL)  // add a specific file
        case cannotResolve       // user must find manually
    }
}

// MARK: - DependencyResolutionResult

/// Result of scanning one or more tweaks for missing dependencies.
struct DependencyResolutionResult: Identifiable {
    let id = UUID()
    let dependencies: [TweakDependency]
    var unresolved: [TweakDependency]   // subset that needs user action
    var autoResolvable: [TweakDependency] // subset we can fix with one tap
}

// MARK: - TweakDependencyResolver

enum TweakDependencyResolver {

    /// Scan a tweak for its dependencies and categorize each one.
    /// - Parameters:
    ///   - tweakURL: The tweak file to scan
    ///   - injectionFiles: Current injection list (to detect tweak-to-tweak deps)
    /// - Returns: A result with all deps, unresolved ones, and auto-resolvable ones.
    static func resolve(
        tweakURL: URL,
        injectionFiles: [URL]
    ) -> DependencyResolutionResult {
        let dylibs = _readLinkedDylibs(at: tweakURL)

        var deps: [TweakDependency] = []
        let injectionBasenames = Set(injectionFiles.map { $0.lastPathComponent })

        for dylib in dylibs {
            // Skip weak links — they won't crash if missing
            if dylib.weak { continue }

            let category = _categorize(
                rawPath: dylib.path,
                injectionFiles: injectionFiles,
                injectionBasenames: injectionBasenames
            )

            let resolution = _resolution(for: category, rawPath: dylib.path)

            deps.append(TweakDependency(
                tweakURL: tweakURL,
                rawPath: dylib.path,
                resolvedPath: nil, // we don't resolve on-disk paths here; categorization handles it
                category: category,
                resolution: resolution
            ))
        }

        let unresolved = deps.filter { $0.resolution != .alreadyPresent }
        let autoResolvable = unresolved.filter {
            $0.resolution == .injectEllekit || $0.resolution != .cannotResolve && $0.resolution != .alreadyPresent
        }

        return DependencyResolutionResult(
            dependencies: deps,
            unresolved: unresolved,
            autoResolvable: autoResolvable
        )
    }

    /// Scan multiple tweaks at once (used for the "Re-scan" button).
    static func resolveAll(
        tweaks: [URL],
        injectionFiles: [URL]
    ) -> DependencyResolutionResult {
        var allDeps: [TweakDependency] = []
        for tweak in tweaks {
            let result = resolve(tweakURL: tweak, injectionFiles: injectionFiles)
            allDeps.append(contentsOf: result.dependencies)
        }

        // Dedupe by raw path (multiple tweaks may link the same dep)
        var seen: Set<String> = []
        let deduped = allDeps.filter { dep in
            if seen.contains(dep.rawPath) { return false }
            seen.insert(dep.rawPath)
            return true
        }

        let unresolved = deduped.filter { $0.resolution != .alreadyPresent }
        let autoResolvable = unresolved.filter { $0.resolution != .cannotResolve && $0.resolution != .alreadyPresent }

        return DependencyResolutionResult(
            dependencies: deduped,
            unresolved: unresolved,
            autoResolvable: autoResolvable
        )
    }

    // MARK: - Categorization

    private static func _categorize(
        rawPath: String,
        injectionFiles: [URL],
        injectionBasenames: Set<String>
    ) -> TweakDependency.Category {
        // 1. System libraries — always available on-device
        if rawPath.hasPrefix("/usr/lib/") || rawPath.hasPrefix("/System/Library/") {
            return .systemLibrary
        }

        // 2. Check if it's in the injection list (by basename match)
        let basename = URL(fileURLWithPath: rawPath).lastPathComponent
        if injectionBasenames.contains(basename) {
            return .tweakDependency
        }

        // 3. Known substrate alternatives
        switch basename {
        case "CydiaSubstrate":
            return .substrate
        case "ElleKit", "ellekit":
            return .ellekit
        case "libhooker":
            return .libhooker
        default:
            return .unknown
        }
    }

    /// Determine the resolution for a categorized dependency.
    private static func _resolution(
        for category: TweakDependency.Category,
        rawPath: String
    ) -> TweakDependency.Resolution {
        switch category {
        case .systemLibrary, .tweakDependency:
            return .alreadyPresent

        case .substrate, .ellekit:
            // Bundle the ellekit.deb from the app's main bundle
            if let ellekitURL = Bundle.main.url(forResource: "ellekit", withExtension: "deb") {
                return .injectEllekit
            }
            return .cannotResolve

        case .libhooker:
            // libhooker isn't bundled — user must find it
            return .cannotResolve

        case .bundledFramework:
            return .alreadyPresent

        case .unknown:
            // Try to find in the user's Tweaks directory
            let tweaksDir = FileManager.default.tweaks
            let basename = URL(fileURLWithPath: rawPath).lastPathComponent
            let candidate = tweaksDir.appendingPathComponent(basename)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return .addToInjectionList(candidate)
            }
            return .cannotResolve
        }
    }

    // MARK: - Mach-O Parsing (reuses MachOReadLinkedDylibs from Feature 1)

    /// Call the ObjC MachOReadLinkedDylibs function and parse the JSON.
    private static func _readLinkedDylibs(at url: URL) -> [LinkedDylib] {
        guard let json = MachOReadLinkedDylibs(url.path),
              let data = json.data(using: .utf8)
        else {
            return []
        }

        // LinkedDylibsResponse is private in TweakLoadOrderValidator,
        // so we decode inline here.
        struct Response: Codable {
            let dylibs: [LinkedDylib]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            return []
        }
        return response.dylibs
    }
}

// MARK: - IgnoredDepsStore

/// Per-app store of ignored dependencies so the re-scan doesn't keep nagging.
/// Keyed by bundle ID, stored in UserDefaults.
struct IgnoredDepsStore {

    /// Get the set of ignored dep paths for a bundle ID.
    static func ignored(for bundleId: String) -> Set<String> {
        let key = "ksign.ignoredDeps.\(bundleId)"
        let array = UserDefaults.standard.array(forKey: key) as? [String] ?? []
        return Set(array)
    }

    /// Ignore a specific dep path for a bundle ID.
    static func ignore(_ rawPath: String, for bundleId: String) {
        let key = "ksign.ignoredDeps.\(bundleId)"
        var current = ignored(for: bundleId)
        current.insert(rawPath)
        UserDefaults.standard.set(Array(current), forKey: key)
    }

    /// Clear all ignored deps for a bundle ID.
    static func clear(for bundleId: String) {
        let key = "ksign.ignoredDeps.\(bundleId)"
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Check if a dep path is ignored for a bundle ID.
    static func isIgnored(_ rawPath: String, for bundleId: String) -> Bool {
        ignored(for: bundleId).contains(rawPath)
    }
}
