//
//  DependencyCheckSheet.swift
//  Ksign
//
//  Modal sheet shown when a tweak is added to the injection list.
//  Lists all dependencies, highlights missing ones, offers one-tap resolution.
//
//  Created for Feature 2: Tweak Dependency Auto-Resolver
//

import SwiftUI
import NimbleViews

struct DependencyCheckSheet: View {
    let scanResult: DependencyResolutionResult
    let tweakName: String
    let bundleId: String?
    @Binding var options: Options
    @Environment(\.dismiss) private var _dismiss

    @State private var _resolvedDeps: Set<UUID> = []   // dep IDs that have been resolved
    @State private var _ignoredDeps: Set<UUID> = []    // dep IDs the user chose to ignore

    var body: some View {
        NBNavigationView(.localized("Dependency Check"), displayMode: .inline) {
            List {
                // Header section
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: .localized("Adding: %@", arguments: tweakName))
                            .font(.headline)
                        if scanResult.unresolved.isEmpty {
                            Label(.localized("All dependencies satisfied"), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.subheadline)
                        } else {
                            Label {
                                Text(verbatim: .localized("%lld dependencies need attention", arguments: scanResult.unresolved.count))
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                            }
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                        }
                    }
                }

                // Dependencies list
                Section(.localized("Dependencies")) {
                    ForEach(scanResult.dependencies) { dep in
                        _depRow(dep)
                    }
                }

                // Action buttons
                Section {
                    // Add tweak + auto-resolvable deps
                    let autoCount = scanResult.autoResolvable.filter { !_resolvedDeps.contains($0.id) && !_ignoredDeps.contains($0.id) }.count
                    let hasUnresolved = !scanResult.unresolved.isEmpty
                    let allResolved = scanResult.unresolved.allSatisfy { _resolvedDeps.contains($0.id) || _ignoredDeps.contains($0.id) }

                    if hasUnresolved && !allResolved {
                        Button {
                            _addAllAutoResolvable()
                        } label: {
                            Label {
                                Text(verbatim: .localized("Add tweak + %lld deps", arguments: autoCount))
                            } icon: {
                                Image(systemName: "plus.circle.fill")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(autoCount == 0)
                    }

                    // Add tweak only (ignore missing deps)
                    Button {
                        _ignoreAllMissing()
                        _dismiss()
                    } label: {
                        Text(verbatim: .localized("Add tweak only"))
                    }

                    // Cancel
                    Button(role: .cancel) {
                        _dismiss()
                    } label: {
                        Text(verbatim: .localized("Cancel"))
                    }
                }
            }
            .toolbar {
                NBToolbarButton(role: .close)
            }
        }
    }

    // MARK: - Row Builder

    @ViewBuilder
    private func _depRow(_ dep: TweakDependency) -> some View {
        let isResolved = _resolvedDeps.contains(dep.id)
        let isIgnored = _ignoredDeps.contains(dep.id)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: _icon(for: dep, isResolved: isResolved, isIgnored: isIgnored))
                    .foregroundStyle(_color(for: dep, isResolved: isResolved, isIgnored: isIgnored))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(dep.rawPath)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(_statusLabel(for: dep, isResolved: isResolved, isIgnored: isIgnored))
                        .font(.caption)
                        .foregroundStyle(_color(for: dep, isResolved: isResolved, isIgnored: isIgnored))
                }

                Spacer()

                // Action button for unresolved deps
                if dep.resolution != .alreadyPresent && !isResolved && !isIgnored {
                    _actionButton(for: dep)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func _actionButton(for dep: TweakDependency) -> some View {
        switch dep.resolution {
        case .injectEllekit:
            Button {
                _injectElleKit()
                _resolvedDeps.insert(dep.id)
            } label: {
                Label(.localized("Inject ElleKit"), systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        case .addToInjectionList(let url):
            Button {
                if !options.injectionFiles.contains(url) {
                    options.injectionFiles.append(url)
                }
                _resolvedDeps.insert(dep.id)
            } label: {
                Label(.localized("Add"), systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        case .cannotResolve:
            Button {
                if let bundleId = bundleId {
                    IgnoredDepsStore.ignore(dep.rawPath, for: bundleId)
                }
                _ignoredDeps.insert(dep.id)
            } label: {
                Label(.localized("Skip"), systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.orange)

        case .alreadyPresent:
            EmptyView()
        }
    }

    // MARK: - Icons & Colors

    private func _icon(for dep: TweakDependency, isResolved: Bool, isIgnored: Bool) -> String {
        if isResolved { return "checkmark.circle.fill" }
        if isIgnored { return "xmark.circle.fill" }
        switch dep.category {
        case .systemLibrary:    return "gearshape"
        case .tweakDependency:  return "link"
        case .substrate:        return "exclamationmark.triangle.fill"
        case .ellekit:          return "star.fill"
        case .libhooker:        return "exclamationmark.triangle.fill"
        case .bundledFramework: return "shippingbox"
        case .unknown:          return "questionmark.circle"
        }
    }

    private func _color(for dep: TweakDependency, isResolved: Bool, isIgnored: Bool) -> Color {
        if isResolved { return .green }
        if isIgnored { return .secondary }
        switch dep.category {
        case .systemLibrary, .tweakDependency, .bundledFramework:
            return .secondary
        case .substrate, .ellekit, .libhooker, .unknown:
            return .orange
        }
    }

    private func _statusLabel(for dep: TweakDependency, isResolved: Bool, isIgnored: Bool) -> String {
        if isResolved { return .localized("Resolved") }
        if isIgnored { return .localized("Ignored") }
        switch dep.category {
        case .systemLibrary:
            return .localized("System library — always available")
        case .tweakDependency:
            return .localized("Already in injection list")
        case .substrate:
            return .localized("NOT FOUND — inject ElleKit as substitute")
        case .ellekit:
            return .localized("NOT FOUND — inject ElleKit")
        case .libhooker:
            return .localized("NOT FOUND — find on disk")
        case .bundledFramework:
            return .localized("Already in bundle")
        case .unknown:
            return .localized("NOT FOUND")
        }
    }

    // MARK: - Bulk Actions

    private func _addAllAutoResolvable() {
        for dep in scanResult.autoResolvable where !_resolvedDeps.contains(dep.id) && !_ignoredDeps.contains(dep.id) {
            switch dep.resolution {
            case .injectEllekit:
                _injectElleKit()
                _resolvedDeps.insert(dep.id)
            case .addToInjectionList(let url):
                if !options.injectionFiles.contains(url) {
                    options.injectionFiles.append(url)
                }
                _resolvedDeps.insert(dep.id)
            default:
                break
            }
        }
    }

    private func _ignoreAllMissing() {
        for dep in scanResult.unresolved where !_resolvedDeps.contains(dep.id) {
            if let bundleId = bundleId {
                IgnoredDepsStore.ignore(dep.rawPath, for: bundleId)
            }
            _ignoredDeps.insert(dep.id)
        }
    }

    private func _injectElleKit() {
        if let ellekitURL = Bundle.main.url(forResource: "ellekit", withExtension: "deb") {
            if !options.injectionFiles.contains(ellekitURL) {
                options.injectionFiles.append(ellekitURL)
            }
        }
    }
}
