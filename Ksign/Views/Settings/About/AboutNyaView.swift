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
                        if !UserDefaults.standard.bool(forKey: "patchNotesShown_v3") {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        _showPatchNotes()
                                        UserDefaults.standard.set(true, forKey: "patchNotesShown_v3")
                                }
                        }
                }
        }
        
        private func _showPatchNotes() {
                UIAlertController.showAlertWithOk(
            title: .localized("From C0st1, Version \(Bundle.main.version)"),
            message: .localized("This version introduces:\n\n- Animated splash launch screen with theme sync\n- Adaptive splash for both light and dark modes\n- Accent color reflected in splash screen glow, shimmer and branding\n- Seamless storyboard-to-SwiftUI transition with zero flash\n- Update checker with badge notifications and background refresh\n- Pull-to-refresh in Library view\n- Dark theme persistence fix on app restart\n- Update All button for bulk app updates\n- Smart update deduplication across sources\n- Stale update cleanup when deleting apps\n- Patch notes viewer on About page\n- Rebranded to C0st1 with custom bundle ID (com.c0st1.ksign)\n- Removed donations, Telegram, and Discord from settings\n- Removed developer repo from default sources\n- GitHub Repository and About (GitHub profile) links in settings"),
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
