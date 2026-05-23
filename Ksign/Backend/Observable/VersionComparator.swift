//
//  VersionComparator.swift
//  Ksign
//
//  Update Checker - Semantic Version Comparison Utility
//

import Foundation

/// Represents a parsed semantic version with support for prerelease identifiers
/// and arbitrary-length version segments (1–N segments supported).
struct ParsedVersion: Equatable {
    let segments: [Int]       // major, minor, patch, and beyond
    let prerelease: [String]?
    let build: String?

    var major: Int { segments[safe: 0] ?? 0 }
    var minor: Int { segments[safe: 1] ?? 0 }
    var patch: Int { segments[safe: 2] ?? 0 }
}

/// Compares semantic version strings, handling diverse formats found in AltSource repositories.
///
/// Supports: SemVer ("2.1.3"), two-segment ("2.1"), integer ("5"), prerelease
/// ("2.1.0-beta1"), "v" prefix ("v2.1.0"), four-segment ("2.1.0.1"),
/// and hyphenated prerelease ("2.0.0-beta-rc1").
struct VersionComparator {

    // MARK: - Public API

    /// Compare two version strings
    static func compare(_ v1: String, _ v2: String) -> ComparisonResult {
        let parsed1 = parseVersion(v1)
        let parsed2 = parseVersion(v2)

        // Compare all numeric segments (major, minor, patch, 4th, 5th, ...)
        let maxSegments = max(parsed1.segments.count, parsed2.segments.count)
        for i in 0..<maxSegments {
            let s1 = parsed1.segments[safe: i] ?? 0
            let s2 = parsed2.segments[safe: i] ?? 0
            if s1 != s2 {
                return s1 > s2 ? .orderedDescending : .orderedAscending
            }
        }

        // Same release version → prerelease rules
        // No prerelease > has prerelease (release beats prerelease)
        let hasPre1 = parsed1.prerelease != nil && !parsed1.prerelease!.isEmpty
        let hasPre2 = parsed2.prerelease != nil && !parsed2.prerelease!.isEmpty

        if !hasPre1 && hasPre2 { return .orderedDescending }
        if hasPre1 && !hasPre2 { return .orderedAscending }

        // Both have prerelease → compare segments
        if hasPre1 && hasPre2 {
            let result = comparePrerelease(parsed1.prerelease!, parsed2.prerelease!)
            if result != .orderedSame { return result }
        }

        // Fall back to build number comparison
        if let b1 = parsed1.build, let b2 = parsed2.build {
            if let n1 = Int(b1), let n2 = Int(b2) {
                if n1 != n2 {
                    return n1 > n2 ? .orderedDescending : .orderedAscending
                }
            } else {
                // Non-numeric builds: compare lexicographically as fallback
                if b1 != b2 {
                    return b1 > b2 ? .orderedDescending : .orderedAscending
                }
            }
        } else if parsed1.build != nil, parsed2.build == nil {
            // Having a build number is newer than not having one
            return .orderedDescending
        } else if parsed1.build == nil, parsed2.build != nil {
            return .orderedAscending
        }

        return .orderedSame
    }

    /// Returns true if the source version is newer than the installed version
    static func isUpdateAvailable(installed: String?, source: String?) -> Bool {
        guard let installed = installed, !installed.isEmpty,
              let source = source, !source.isEmpty else {
            return false
        }
        return compare(source, installed) == .orderedDescending
    }

    // MARK: - Parsing

    static func parseVersion(_ version: String) -> ParsedVersion {
        var cleaned = version.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip leading "v" or "V"
        if cleaned.hasPrefix("v") || cleaned.hasPrefix("V") {
            cleaned = String(cleaned.dropFirst())
        }

        // Split on "+" to extract build metadata
        var build: String? = nil
        if let plusRange = cleaned.range(of: "+") {
            build = String(cleaned[plusRange.upperBound...])
            cleaned = String(cleaned[..<plusRange.lowerBound])
        }

        // Split on "-" to extract prerelease
        var prerelease: [String]? = nil
        if let hyphenRange = cleaned.range(of: "-") {
            let preString = String(cleaned[hyphenRange.upperBound...])
            // Split on both "." and "-" for hyphenated prerelease tags like "beta-rc1"
            prerelease = preString
                .components(separatedBy: CharacterSet(charactersIn: ".-"))
                .filter { !$0.isEmpty }
            cleaned = String(cleaned[..<hyphenRange.lowerBound])
        }

        // Split on "." for version segments
        let segmentStrings = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        var segments: [Int] = []
        for s in segmentStrings {
            if let num = Int(s) {
                segments.append(num)
            } else {
                // Non-numeric segment: treat as 0 but log a warning
                // This handles versions like "2.1.x" gracefully
                segments.append(0)
            }
        }

        // Ensure at least one segment
        if segments.isEmpty {
            segments = [0]
        }

        return ParsedVersion(
            segments: segments,
            prerelease: prerelease,
            build: build
        )
    }

    // MARK: - Private

    /// Compare prerelease segments per SemVer spec:
    /// Numeric segments compared as integers, alphanumeric lexicographically,
    /// numeric < alphanumeric.
    private static func comparePrerelease(_ p1: [String], _ p2: [String]) -> ComparisonResult {
        let maxLen = max(p1.count, p2.count)
        for i in 0..<maxLen {
            // Shorter prerelease with all segments matching is less (comes before)
            if i >= p1.count { return .orderedAscending }
            if i >= p2.count { return .orderedDescending }

            let s1 = p1[i]
            let s2 = p2[i]

            let n1 = Int(s1)
            let n2 = Int(s2)

            if let n1 = n1, let n2 = n2 {
                // Both numeric → compare as integers
                if n1 != n2 { return n1 > n2 ? .orderedDescending : .orderedAscending }
            } else if n1 != nil {
                // Numeric comes before alphanumeric
                return .orderedAscending
            } else if n2 != nil {
                return .orderedDescending
            } else {
                // Both alphanumeric → compare lexicographically
                if s1 != s2 {
                    return s1 > s2 ? .orderedDescending : .orderedAscending
                }
            }
        }
        return .orderedSame
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
