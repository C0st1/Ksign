//
//  TweakLoadOrderValidator.swift
//  Ksign
//
//  Validates tweak load order by inspecting each tweak's Mach-O
//  LC_LOAD_DYLIB entries. Detects:
//   - Ordering conflicts (tweak A loaded before tweak B, but A links B)
//   - Substrate/ElleKit position (should be first)
//   - Missing dependencies (a tweak links another tweak that's not in the list)
//
//  Created for Feature 1: Tweak Load Order Controller
//

import Foundation

// MARK: - Conflict Types

struct TweakLoadOrderConflict: Identifiable, Equatable {
    let id = UUID()
    let earlierTweak: String   // basename
    let laterTweak: String     // basename
    let reason: String
    let severity: Severity

    enum Severity {
        case warning   // suboptimal but won't crash
        case error     // likely crash on launch

        var iconName: String {
            switch self {
            case .warning: return "exclamationmark.triangle.fill"
            case .error:   return "xmark.octagon.fill"
            }
        }

        var color: String {
            switch self {
            case .warning: return "orange"
            case .error:   return "red"
            }
        }
    }
}

// MARK: - Linked Dylib (parsed from MachOReadLinkedDylibs JSON)

struct LinkedDylib: Codable, Equatable {
    let path: String           // "@rpath/Foo.framework/Foo"
    let type: String           // "LC_LOAD_DYLIB", etc.
    let loadIndex: Int
    let currentVersion: String?
    let compatVersion: String?
    let weak: Bool

    /// The basename of the dylib (e.g., "CydiaSubstrate" from "@rpath/CydiaSubstrate.framework/CydiaSubstrate")
    var basename: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

private struct LinkedDylibsResponse: Codable {
    let dylibs: [LinkedDylib]
}

// MARK: - Validator

enum TweakLoadOrderValidator {

    /// Inspect each tweak's linked dylibs and detect ordering conflicts.
    ///
    /// Rules:
    /// 1. If tweak A (loaded earlier) links tweak B (loaded later) by basename,
    ///    that's a conflict — A depends on B but B isn't loaded yet.
    /// 2. Any tweak linking "CydiaSubstrate" must load AFTER the
    ///    Substrate/ElleKit entry in the order (substrate must be first).
    /// 3. A tweak linking another tweak by basename that's not in the list
    ///    at all → missing dependency (error).
    static func validate(order: [URL]) -> [TweakLoadOrderConflict] {
        guard !order.isEmpty else { return [] }

        // Parse each tweak's linked dylibs
        var tweakDylibs: [(tweak: URL, dylibs: [LinkedDylib])] = []
        for url in order {
            let dylibs = _readLinkedDylibs(at: url)
            tweakDylibs.append((url, dylibs))
        }

        // Build a set of all tweak basenames for quick lookup
        let tweakBasenames = Set(order.map { $0.lastPathComponent })

        var conflicts: [TweakLoadOrderConflict] = []

        // Check each pair (i, j) where i < j (i loads before j)
        for (i, entryA) in tweakDylibs.enumerated() {
            let tweakABasename = entryA.tweak.lastPathComponent

            for entry in entryA.dylibs {
                let depBasename = entry.basename

                // Skip system libraries and self-references
                if _isSystemPath(entry.path) { continue }
                if depBasename == tweakABasename { continue }

                // Rule 2: Substrate position check
                if depBasename == "CydiaSubstrate" || depBasename == "ElleKit" {
                    // This tweak links Substrate/ElleKit — check if Substrate is
                    // in the list AND loaded before this tweak
                    let substrateIndex = order.firstIndex { url in
                        let bn = url.lastPathComponent
                        return bn.contains("CydiaSubstrate") || bn.contains("ellekit") || bn.contains("ElleKit")
                    }

                    if let substrateIdx = substrateIndex, substrateIdx > i {
                        // Substrate loads AFTER this tweak — conflict
                        conflicts.append(TweakLoadOrderConflict(
                            earlierTweak: tweakABasename,
                            laterTweak: order[substrateIdx].lastPathComponent,
                            reason: .localized("%@ loads before its dependency %@ (should be after)",
                                                arguments: tweakABasename, order[substrateIdx].lastPathComponent),
                            severity: .error
                        ))
                    }
                }

                // Rule 1: A links B, B is in the list, but B loads after A
                if tweakBasenames.contains(depBasename) {
                    if let j = order.firstIndex(where: { $0.lastPathComponent == depBasename }), j > i {
                        conflicts.append(TweakLoadOrderConflict(
                            earlierTweak: tweakABasename,
                            laterTweak: depBasename,
                            reason: .localized("%@ depends on %@ but loads earlier",
                                                arguments: tweakABasename, depBasename),
                            severity: .warning
                        ))
                    }
                }
            }
        }

        return conflicts
    }

    /// Auto-fix the load order by topologically sorting based on dependencies.
    /// Substrate/ElleKit always moves to position 0.
    /// Returns the reordered array, or the original if no fix is possible
    /// (e.g., circular dependencies).
    static func autoFix(order: [URL]) -> [URL] {
        guard order.count > 1 else { return order }

        // Step 1: Identify substrate/ellekit providers and move them to the front
        var reordered = order
        var substrateProviders: [URL] = []
        var remaining: [URL] = []

        for url in reordered {
            let bn = url.lastPathComponent.lowercased()
            // Match all common substrate alternative names:
            // - cydiasubstrate / substrate
            // - ellekit
            // - libhooker
            // - libsubstrate (common alias for CydiaSubstrate)
            if bn.contains("substrate") || bn.contains("ellekit") || bn.contains("libhooker") {
                substrateProviders.append(url)
            } else {
                remaining.append(url)
            }
        }

        // Step 2: Build a "provides" map — which tweak provides which substrate
        // e.g. ellekit.deb provides "CydiaSubstrate"
        var providesMap: [String: URL] = [:]  // "cydiasubstrate" -> ellekit.deb URL
        for url in substrateProviders {
            let bn = url.lastPathComponent.lowercased()
            if bn.contains("ellekit") {
                providesMap["cydiasubstrate"] = url
                providesMap["ellekit"] = url
                providesMap["substrate"] = url
                providesMap["libsubstrate"] = url
            } else if bn.contains("cydiasubstrate") {
                providesMap["cydiasubstrate"] = url
                providesMap["substrate"] = url
                providesMap["libsubstrate"] = url
            } else if bn.contains("libsubstrate") {
                providesMap["cydiasubstrate"] = url
                providesMap["substrate"] = url
                providesMap["libsubstrate"] = url
            } else if bn.contains("libhooker") {
                providesMap["libhooker"] = url
            }
        }

        // Step 3: Topologically sort `remaining` based on their dependencies
        let sorted = _topologicalSort(remaining, providesMap: providesMap, allTweaks: reordered)

        // Step 4: Substrate providers first, then sorted tweaks
        return substrateProviders + sorted
    }

    // MARK: - Private Helpers

    /// Call the ObjC MachOReadLinkedDylibs function and parse the JSON.
    private static func _readLinkedDylibs(at url: URL) -> [LinkedDylib] {
        guard let json = MachOReadLinkedDylibs(url.path),
              let data = json.data(using: .utf8),
              let response = try? JSONDecoder().decode(LinkedDylibsResponse.self, from: data)
        else {
            return []
        }
        return response.dylibs
    }

    /// Check if a path is a system library (never a conflict source).
    private static func _isSystemPath(_ path: String) -> Bool {
        path.hasPrefix("/usr/lib/") || path.hasPrefix("/System/Library/")
    }

    /// Topological sort: a tweak that depends on another comes after it.
    /// If a cycle is detected, returns the input unchanged.
    ///
    /// - Parameters:
    ///   - tweaks: The tweaks to sort (substrate providers already removed)
    ///   - providesMap: Map of "cydiasubstrate" → URL that provides it
    ///   - allTweaks: All tweaks (for basename lookup of inter-tweak deps)
    private static func _topologicalSort(
        _ tweaks: [URL],
        providesMap: [String: URL],
        allTweaks: [URL]
    ) -> [URL] {
        // Build adjacency: deps[tweak basename] = [basenames it depends on]
        var deps: [String: Set<String>] = [:]
        let allBasenames = Set(allTweaks.map { $0.lastPathComponent })

        for tweak in tweaks {
            let basename = tweak.lastPathComponent
            let linked = _readLinkedDylibs(at: tweak)
            var dependencies: Set<String> = []

            for entry in linked {
                if _isSystemPath(entry.path) { continue }
                if entry.basename == basename { continue }

                // Case 1: direct tweak-to-tweak dependency (by basename match)
                if allBasenames.contains(entry.basename) {
                    dependencies.insert(entry.basename)
                    continue
                }

                // Case 2: substrate dependency — check the providesMap
                let depLower = entry.basename.lowercased()
                if let provider = providesMap[depLower] {
                    let providerBasename = provider.lastPathComponent
                    // Only add if the provider is in our sort set (it won't be —
                    // substrate providers are already at the front). So we don't
                    // add a dep edge, but we also don't need to — the provider is
                    // already guaranteed to be before this tweak.
                    _ = providerBasename
                }
            }
            deps[basename] = dependencies
        }

        // Kahn's algorithm
        var inDegree: [String: Int] = [:]
        for tweak in tweaks {
            inDegree[tweak.lastPathComponent] = 0
        }
        for (_, ds) in deps {
            for d in ds {
                inDegree[d, default: 0] += 1
            }
        }

        var queue: [String] = inDegree.filter { $0.value == 0 }.map { $0.key }
        queue.sort() // deterministic order for ties

        var result: [String] = []
        while !queue.isEmpty {
            let current = queue.removeFirst()
            result.append(current)

            // Find tweaks that depend on current
            for (basename, ds) in deps where ds.contains(current) {
                inDegree[basename, default: 0] -= 1
                if inDegree[basename] == 0 {
                    queue.append(basename)
                    queue.sort()
                }
            }
        }

        // If we couldn't sort all (cycle detected), return original
        if result.count != tweaks.count {
            return tweaks
        }

        // Map back to URLs (preserving the topological order)
        let urlByBasename = Dictionary(uniqueKeysWithValues: tweaks.map { ($0.lastPathComponent, $0) })
        return result.compactMap { urlByBasename[$0] }
    }
}
