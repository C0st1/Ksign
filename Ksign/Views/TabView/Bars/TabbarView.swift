//
//  TabbarView.swift
//  feather
//
//  Created by samara on 23.03.2025.
//

import SwiftUI

struct TabbarView: View {
	@State private var selectedTab: TabEnum = .sources
	@ObservedObject private var updateManager = UpdateManager.shared

	var body: some View {
		TabView(selection: $selectedTab) {
			ForEach(TabEnum.defaultTabs, id: \.hashValue) { tab in
				TabEnum.view(for: tab)
					.tabItem {
						Label(tab.title, systemImage: tab.icon)
					}
					.tag(tab)
					.badge(_badgeCount(for: tab))
			}
		}
	}

	private func _badgeCount(for tab: TabEnum) -> Int {
		let count = updateManager.updateCount
		if count > 0 && (tab == .appstore || tab == .library) {
			return count
		}
		return 0
	}
}
