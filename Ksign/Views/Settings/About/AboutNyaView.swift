//
//  AboutNyaView.swift
//  Ksign
//
//  Created by Nagata Asami on 23/5/25.
//

import SwiftUI
import NimbleViews
import NimbleJSON

// MARK: - View
struct AboutNyaView: View {
        private let _dataService = NBFetchService()
        
        @State private var shouldShowPatchNotes = false
        
        // MARK: Body
        var body: some View {
                NBList(.localized("About")) {
            Section {
                VStack {
                    Image(uiImage: (UIImage(named: Bundle.main.iconFileName ?? ""))! )
                        .appIconStyle(size: 72)
                    
                    Text(Bundle.main.exec)
                        .font(.largeTitle)
                        .bold()
                        .foregroundStyle(.accent)
                    
                    HStack(spacing: 4) {
                        Text("Version")
                        Text(Bundle.main.version)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    
                    Button {
                        _showPatchNotes()
                    } label: {
                        Text("Show patch notes").bg()
                    }
                    .font(.footnote)
                    .padding(.top, 4)
                    .tint(.accent)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(EmptyView())
                        
                        NBSection(.localized("Credits")) {
                                _credit(name: "C0st1", desc: "Developer", github: "C0st1")
                        }
                        
                        NBSection("Special thanks!") {
                                Group {
                                        Text(.localized("This couldn't have been done without the original Feather devs! ❤️"))
                                                .foregroundStyle(.secondary)
                                                .padding(.vertical, 2)
                                }
                                .transition(.slide)
                        }
            
            NBSection("Acknowledgements") {
                NavigationLink(destination: AboutView()) {
                    HStack {
                        Text("About the original Feather")
                        Spacer()
                    }
                }
            } footer: {
                Text(Bundle.main.bundleIdentifier ?? "")
            }
                }
                .onAppear {
                        // Show patch notes when navigating to this view if they haven't been shown before
                        if !UserDefaults.standard.bool(forKey: "patchNotesShown_v4") {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        _showPatchNotes()
                                        UserDefaults.standard.set(true, forKey: "patchNotesShown_v4")
                                }
                        }
                }
        }

        private func _showPatchNotes() {
                UIAlertController.showAlertWithOk(
            title: .localized("From C0st1, Version \(Bundle.main.version)"),
            message: .localized("This version introduces 5 new features:\n\n- Tweak Load Order Controller: Drag-to-reorder injected tweaks with real-time validation. Auto-fix detects ordering conflicts and moves Substrate/ElleKit to position 0.\n\n- Tweak Dependency Auto-Resolver: Scans tweak Mach-O dependencies and detects missing ones (e.g. CydiaSubstrate). One-tap Inject ElleKit resolution.\n\n- Tweak Folders: Organize tweaks into folders. Smart Folders (All, Dylibs, Debs, Recent). Move tweaks between folders. Folder-aware injection picker.\n\n- Per-App Update Preferences: Auto-Update, Notify, or Ignore per app. Version-specific ignore. Global default in Settings.\n\n- Background Maintenance: 5-phase BGProcessingTask (Source Refresh, Update Detection, Auto-Update, Stale Cleanup, Cert Expiry Check) every 6/12/24h. Detailed log viewer.\n\nAlso includes:\n- Fixed progress bar black on light theme\n- Fixed .framework/.bundle showing as folders\n- Update check now fetches sources automatically\n- MachOReadLinkedDylibs() for Mach-O parsing"),
                        isCancel: true,
                        thankYou: true
                )
        }
}

// MARK: - Extension: view
extension AboutNyaView {
        @ViewBuilder
        private func _credit(
                name: String?,
                desc: String?,
                github: String
        ) -> some View {
                FRIconCellView(
                        title: name ?? github,
                        subtitle: desc ?? "",
                        iconUrl: URL(string: "https://github.com/\(github).png")!,
                        trailing: AnyView(
                                Image(systemName: "arrow.up.right")
                                        .foregroundStyle(.secondary)
                        )
                )
                .onTapGesture {
                        if let url = URL(string: "https://github.com/\(github)") {
                                UIApplication.shared.open(url)
                        }
                }
        }
}
