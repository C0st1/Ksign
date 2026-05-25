//
//  DownloadButtonView.swift
//  Feather
//
//  Created by samsam on 7/25/25.
//

import SwiftUI
import Combine
import AltSourceKit
import NimbleViews

struct DownloadButtonView: View {
	let app: ASRepository.App
	let sourceURL: URL?
	@ObservedObject private var downloadManager = DownloadManager.shared
	@ObservedObject private var updateManager = UpdateManager.shared

	@State private var downloadProgress: Double = 0
	@State private var cancellable: AnyCancellable?

	private var installState: InstallState {
		if downloadManager.getDownload(by: app.currentUniqueId) != nil {
			return .downloading
		}
		// Only show "Update" if THIS specific source app version is newer
		// than the currently installed version. This prevents showing "Update"
		// on older source entries when multiple versions of the same app exist.
		if let bundleId = app.id,
		   let update = updateManager.update(for: bundleId),
		   let sourceVersion = app.currentVersion,
		   VersionComparator.isUpdateAvailable(installed: update.installedVersion, source: sourceVersion) {
			return .update
		}
		return .get
	}

	enum InstallState {
		case get
		case update
		case downloading
	}

	var body: some View {
		ZStack {
			switch installState {
			case .downloading:
				ZStack {
					Circle()
						.trim(from: 0, to: downloadProgress)
						.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
						.rotationEffect(.degrees(-90))
						.frame(width: 31, height: 31)
						.animation(.smooth, value: downloadProgress)

					Image(systemName: downloadProgress >= 0.75 ? "archivebox" : "square.fill")
						.foregroundStyle(.tint)
						.font(.footnote).bold()
				}
				.onTapGesture {
					if let currentDownload = downloadManager.getDownload(by: app.currentUniqueId) {
						if downloadProgress <= 0.75 {
							downloadManager.cancelDownload(currentDownload)
						}
					}
				}
				.compatTransition()
			case .update:
				Button {
					if let url = app.currentDownloadUrl {
						_ = downloadManager.startDownload(from: url, id: app.currentUniqueId, sourceURL: sourceURL)
					}
				} label: {
					Text(.localized("Update"))
						.lineLimit(0)
						.font(.headline.bold())
						.foregroundStyle(.white)
						.padding(.horizontal, 24)
						.padding(.vertical, 6)
						.background(Color.orange)
						.clipShape(Capsule())
				}
				.buttonStyle(.borderless)
				.compatTransition()
			case .get:
				Button {
					if let url = app.currentDownloadUrl {
						_ = downloadManager.startDownload(from: url, id: app.currentUniqueId, sourceURL: sourceURL)
					}
				} label: {
					Text(.localized("Get"))
						.lineLimit(0)
						.font(.headline.bold())
						.foregroundStyle(Color.accentColor)
						.padding(.horizontal, 24)
						.padding(.vertical, 6)
						.background(Color(uiColor: .quaternarySystemFill))
						.clipShape(Capsule())
				}
				.buttonStyle(.borderless)
				.compatTransition()
			}
		}
		.onAppear(perform: setupObserver)
		.onDisappear { cancellable?.cancel() }
		.onChange(of: downloadManager.downloads.description) { _ in
			setupObserver()
		}
		.animation(.easeInOut(duration: 0.3), value: downloadManager.getDownload(by: app.currentUniqueId) != nil)
	}

	private func setupObserver() {
		cancellable?.cancel()
		guard let download = downloadManager.getDownload(by: app.currentUniqueId) else {
			downloadProgress = 0
			return
		}
		downloadProgress = download.overallProgress

		let publisher = Publishers.CombineLatest(
			download.$progress,
			download.$unpackageProgress
		)

		cancellable = publisher.sink { _, _ in
			downloadProgress = download.overallProgress
		}
	}
}
