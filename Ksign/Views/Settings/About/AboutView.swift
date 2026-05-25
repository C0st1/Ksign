//
//  AboutView.swift
//  Feather
//
//  Created by samara on 30.04.2025.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct AboutView: View {
        
        private let _credits: [CreditsModel] = [
                CreditsModel(name: "khcrysalis", desc: "Developer", github: "khcrysalis"),
                CreditsModel(name: "samara", desc: "Contributor", github: "samara"),
                CreditsModel(name: "Lakr Aream", desc: "Axum Core", github: "Lakr233"),
                CreditsModel(name: "SideStore", desc: "AltSourceKit", github: "SideStore"),
                CreditsModel(name: "pmtao", desc: "Contributor", github: "pmtao"),
                CreditsModel(name: "owo-shiro", desc: "Contributor", github: "owo-shiro"),
        ]
        
        // MARK: Body
        var body: some View {
                NBList(.localized("About Feather")) {
                        
                        Section {
                                VStack {
                                        Text("Feather")
                                                .font(.largeTitle)
                                                .bold()
                                                .foregroundStyle(.accent)
                                        
                                        Text("An open-source iOS sideloading app")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        
                        NBSection(.localized("Credits")) {
                                ForEach(_credits, id: \.self) { credit in
                                        _credit(name: credit.name, desc: credit.desc, github: credit.github)
                                }
                        }
                        
                        NBSection("Repository") {
                                Button(.localized("Feather on GitHub"), systemImage: "safari") {
                                        if let url = URL(string: "https://github.com/khcrysalis/Feather") {
                                                UIApplication.shared.open(url)
                                        }
                                }
                        } footer: {
                                Text("Feather is licensed under GPL-3.0")
                        }
                        
                }
        }
}

// MARK: - Extension: view
extension AboutView {
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
