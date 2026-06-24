//
//  AppFeaturesView.swift
//  Ksign
//
//  Created by Nagata Asami on 10/10/25.
//

import SwiftUI
import NimbleViews
import UserNotifications
import BackgroundTasks
import OSLog

struct AppFeaturesView: View {
    @StateObject private var _optionsManager = OptionsManager.shared
    @State private var _showMaintenanceLog = false
    @State private var _isRunningMaintenance = false

    var body: some View {
        NBList(.localized("App Features")) {
            Section {
                Toggle(isOn: $_optionsManager.options.backgroundAudio) {
                    Label(.localized("Keep app running in background"), systemImage: "arrow.trianglehead.2.clockwise")
                }
            } footer: {
                Text(.localized("This will keep the app running even when you close it, helpful with download or installing ipa."))
            }
            Section {
                Toggle(isOn: $_optionsManager.options.signingLogs) {
                    Label(.localized("Show logs when signing"), systemImage: "terminal")
                }
            } footer: {
                Text(.localized("This will show the logs of the signing process when you start signing."))
            }
            Section {
                Toggle(isOn: $_optionsManager.options.notifications) {
                    Label(.localized("Notify when download is completed"), systemImage: "bell")
                }
                .onChange(of: _optionsManager.options.notifications) { enabled in
                    _notificationsAuthorization(enabled)
                }
            } footer: {
                Text(.localized("This will notify you when the download is completed."))
            }
            Section {
                Toggle(isOn: $_optionsManager.options.saveAppStoreDownloadsToDownloadsFolder) {
                    Label(.localized("Save App Store downloads to Downloads folder"), systemImage: "square.and.arrow.down.fill")
                }
            } footer: {
                Text(.localized("This will save the App Store downloads to the Downloads folder, turning this off will help reduce disk usage."))
            }
            Section {
                Toggle(isOn: $_optionsManager.options.checkForUpdates) {
                    Label(.localized("Check for Updates"), systemImage: "arrow.trianglehead.2.clockwise")
                }
                if _optionsManager.options.checkForUpdates {
                    Toggle(isOn: $_optionsManager.options.notifyOnUpdates) {
                        Label(.localized("Notify on Updates"), systemImage: "bell.badge")
                    }
                    .disabled(!_optionsManager.options.notifications)
                    Toggle(isOn: $_optionsManager.options.backgroundUpdateCheck) {
                        Label(.localized("Background Update Check"), systemImage: "arrow.down.circle")
                    }
                    NavigationLink {
                        UpdatePreferencesView()
                    } label: {
                        Label(.localized("Per-App Update Preferences"), systemImage: "slider.horizontal.3")
                    }
                }
            } footer: {
                Text(.localized("Automatically check for app updates when sources are refreshed. Notifications require download notifications to be enabled. Per-app preferences override the global default."))
            }

            // Background Maintenance section (new)
            _backgroundMaintenanceSection
        }
        .onChange(of: _optionsManager.options) { _ in
            _optionsManager.saveOptions()
        }
        .sheet(isPresented: $_showMaintenanceLog) {
            BackgroundMaintenanceLogView()
        }
    }

    // MARK: - Background Maintenance Section

    @ViewBuilder
    private var _backgroundMaintenanceSection: some View {
        Section {
            Toggle(isOn: $_optionsManager.options.backgroundMaintenanceEnabled) {
                Label(.localized("Background Maintenance"), systemImage: "gear.arrow.2.circlepath")
            }
            .disabled(!_optionsManager.options.checkForUpdates || !_optionsManager.options.backgroundUpdateCheck)

            if _optionsManager.options.backgroundMaintenanceEnabled
                && _optionsManager.options.checkForUpdates
                && _optionsManager.options.backgroundUpdateCheck {

                Toggle(isOn: $_optionsManager.options.backgroundMaintenanceRequiresCharging) {
                    Label(.localized("Require charging"), systemImage: "bolt.fill")
                }

                Picker(.localized("Interval"), selection: $_optionsManager.options.backgroundMaintenanceInterval) {
                    Text(.localized("Every 6 hours")).tag(6)
                    Text(.localized("Every 12 hours")).tag(12)
                    Text(.localized("Every 24 hours")).tag(24)
                }

                Toggle(isOn: $_optionsManager.options.autoInstallAutoUpdates) {
                    Label(.localized("Auto-install auto-updated apps"), systemImage: "square.and.arrow.down")
                }

                // Last run info
                if let lastLog = BackgroundMaintenanceLogStore.shared.lastLog {
                    LabeledContent(.localized("Last run")) {
                        Text(lastLog.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent(.localized("Status")) {
                        HStack(spacing: 4) {
                            Image(systemName: lastLog.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(lastLog.success ? .green : .red)
                            Text(lastLog.cancelled ? .localized("Cancelled") : (lastLog.success ? .localized("Success") : .localized("Failed")))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button {
                    _runMaintenanceNow()
                } label: {
                    HStack {
                        if _isRunningMaintenance {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(.localized("Run now"))
                    }
                }
                .disabled(_isRunningMaintenance)

                NavigationLink {
                    BackgroundMaintenanceLogView()
                } label: {
                    Label(.localized("View last run log"), systemImage: "doc.text")
                }
            }
        } header: {
            Text(.localized("Background Maintenance"))
        } footer: {
            Text(.localized("Runs full source refresh, update detection, auto-updates, stale-download cleanup, and certificate expiry checks. Requires 'Check for Updates' and 'Background Update Check' to be enabled."))
        }
    }

    /// Trigger an immediate background maintenance run.
    /// Submits a BGProcessingTaskRequest with earliestBeginDate = 1 second from now.
    /// iOS may still defer it slightly, but usually runs within a few seconds.
    private func _runMaintenanceNow() {
        _isRunningMaintenance = true

        let request = BGProcessingTaskRequest(identifier: "com.ksign.backgroundMaintenance")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 1)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false // don't require charging for manual runs

        do {
            try BGTaskScheduler.shared.submit(request)
            Logger.misc.info("Manual background maintenance run requested")

            // Also run directly for immediate feedback (the BG task will run separately)
            BackgroundMaintenanceCoordinator.shared.run { success in
                DispatchQueue.main.async {
                    _isRunningMaintenance = false
                    if success {
                        _showMaintenanceLog = true
                    }
                }
            }
        } catch {
            Logger.misc.error("Could not submit manual maintenance request: \(error)")
            DispatchQueue.main.async {
                _isRunningMaintenance = false
                UIAlertController.showAlertWithOk(
                    title: .localized("Error"),
                    message: .localized("Could not start maintenance: %@", arguments: error.localizedDescription)
                )
            }
        }
    }

    private func _notificationsAuthorization(_ enabled: Bool) {
        guard enabled else { return }
        
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    DispatchQueue.main.async {
                        if !granted {
                            _optionsManager.options.notifications = false
                        }
                    }
                }
            case .denied:
                DispatchQueue.main.async {
                    _optionsManager.options.notifications = false
                    
                    let cancel = UIAlertAction(title: .localized("Cancel"), style: .cancel)
                    let ok = UIAlertAction(title: .localized("Open Settings"), style: .default) { _ in
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    UIAlertController.showAlert(
                        title: .localized("You have denied!"),
                        message: .localized("Please open settings and grant permission to send notifications."),
                        actions: [cancel, ok]
                    )
                }
            case .authorized, .provisional, .ephemeral:
                break
            @unknown default:
                break
            }
        }
    }
}
