//
//  FeatherApp.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import SwiftUI
import Nuke
import OSLog
import IDeviceSwift
import BackgroundTasks

@main
struct FeatherApp: App {
        @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
        let heartbeat = HeartbeatManager.shared
        @StateObject var downloadManager = DownloadManager.shared
        @StateObject var accentColorManager = AccentColorManager.shared
    @StateObject var extractManager = ExtractManager.shared
        @StateObject var logsManager = LogsManager.shared
        let storage = Storage.shared

        /// Controls the animated splash overlay visibility
        @StateObject private var splashVM = SplashViewModel()

        @AppStorage("Feather.userInterfaceStyle") private var _userInterfaceStyle: Int = UIUserInterfaceStyle.unspecified.rawValue
        @Environment(\.scenePhase) private var scenePhase

        var body: some Scene {
                WindowGroup {
                        ZStack {
                                // ── Main app content ─────────────────────────
                                VStack {
                    ExtractHeaderView(extractManager: extractManager)
                        .transition(.move(edge: .top).combined(with: .opacity))
                                        DownloadHeaderView(downloadManager: downloadManager)
                                                .transition(.move(edge: .top).combined(with: .opacity))
                                        VariedTabbarView()
                                                .environment(\.managedObjectContext, storage.context)
                                                .onOpenURL(perform: _handleURL)
                                                .transition(.move(edge: .top).combined(with: .opacity))
                                }
                                .animation(.smooth, value: downloadManager.manualDownloads.description)
                .animation(.smooth, value: extractManager.extractItems.description)
                                .onReceive(accentColorManager.objectWillChange) { _ in
                                        accentColorManager.updateGlobalTintColor()
                                }
                                .onAppear {
                                        accentColorManager.updateGlobalTintColor()
                                        _applyUserInterfaceStyle()
                                        if logsManager.isCapturing { logsManager.startCapture() }
                                }

                                // ── Splash overlay ───────────────────────────
                                if splashVM.phase != .dismissed {
                                        SplashView(vm: splashVM)
                                                .onAppear { splashVM.start() }
                                }
                        }
                        .background(Color.black.ignoresSafeArea())
                }
                .onChange(of: scenePhase) { phase in
                        if phase == .active {
                                _applyUserInterfaceStyle()
                                if OptionsManager.shared.options.checkForUpdates {
                                        UpdateManager.shared.checkForUpdates()
                                }
                        }
                }
        }

        private func _applyUserInterfaceStyle() {
                guard let style = UIUserInterfaceStyle(rawValue: _userInterfaceStyle) else { return }
                DispatchQueue.main.async {
                        UIApplication.shared.connectedScenes
                                .compactMap { $0 as? UIWindowScene }
                                .flatMap { $0.windows }
                                .forEach { $0.overrideUserInterfaceStyle = style }
                }
        }

        private func _handleURL(_ url: URL) {
                if url.scheme == "ksign" {
                        if let fullPath = url.validatedScheme(after: "/source/") {
                                FR.handleSource(fullPath) { }
                        }
                        
                        if
                                let fullPath = url.validatedScheme(after: "/install/"),
                                let downloadURL = URL(string: fullPath)
                        {
                                _ = DownloadManager.shared.startDownload(from: downloadURL, id: "FeatherManualDownload_\(UUID().uuidString)")
                        }
                } else {
                        if url.pathExtension == "ipa" || url.pathExtension == "tipa" {
                                if FileManager.default.isFileFromFileProvider(at: url) {
                                        guard url.startAccessingSecurityScopedResource() else { return }
                                        FR.handlePackageFile(url) { _ in }
                                } else {
                                        FR.handlePackageFile(url) { _ in }
                                }
                                
                                return
                        }
                        
            if url.pathExtension == "ksign" {
                UIAlertController.showAlertWithOk(title: .localized("Error"), message: .localized("Ksign certificate file (.ksign) is now unsupported from v1.5.1, please refer to use .p12 and .mobileprovision instead."))
            }
                }
        }
        
}
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        // Apply the user's appearance preference BEFORE any UI renders.
        // This prevents the white flash that occurs when the system storyboard
        // (always black now) hands off to the SwiftUI window.
        _applyAppearanceEarly()

        _createPipeline()
        _createSourcesDirectory()
        if !UserDefaults.standard.bool(forKey: "hasInitializedBuiltInSources") {
            _initializeBuiltInSources()
            UserDefaults.standard.set(true, forKey: "hasInitializedBuiltInSources")
        }
        
        _clean()
        
        _copyServerCertificates()
        _addDefaultCertificates()
        // Register background update check task
        _registerBackgroundUpdateCheck()

#if SERVER
        // fallback just in case xd
        _downloadSSLCertificates()
#endif
        return true
    }
    
    /// Applies the user's preferred appearance (dark/light/system) as early as
    /// possible in the launch cycle so that the first SwiftUI frame already
    /// respects the chosen theme. The storyboard is always black so the
    /// handoff is seamless; the SplashView then smoothly blends to the
    /// app's actual theme color.
    private func _applyAppearanceEarly() {
        let raw = UserDefaults.standard.integer(forKey: "Feather.userInterfaceStyle")
        let style = UIUserInterfaceStyle(rawValue: raw) ?? .unspecified
        DispatchQueue.main.async {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .forEach { window in
                    window.overrideUserInterfaceStyle = style
                    // Window starts black to match the storyboard;
                    // SplashView smoothly transitions it to the theme color.
                    window.backgroundColor = .black
                }
        }
    }

    private func _initializeBuiltInSources() { 
        Storage.shared.addBuiltInSources()
    }
    
    private func _registerBackgroundUpdateCheck() {
        // Quick periodic update check (BGAppRefreshTask — ~30s runtime)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.ksign.updateCheck",
            using: nil
        ) { task in
            self._handleBackgroundUpdateCheck(task as! BGAppRefreshTask)
        }
        _scheduleBackgroundUpdateCheck()

        // Full background maintenance (BGProcessingTask — multi-minute runtime)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.ksign.backgroundMaintenance",
            using: nil
        ) { task in
            self._handleBackgroundMaintenance(task as! BGProcessingTask)
        }
        _scheduleBackgroundMaintenance()
    }

    private func _handleBackgroundUpdateCheck(_ task: BGAppRefreshTask) {
        _scheduleBackgroundUpdateCheck()

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        guard OptionsManager.shared.options.checkForUpdates,
              OptionsManager.shared.options.backgroundUpdateCheck else {
            task.setTaskCompleted(success: true)
            return
        }

        UpdateManager.shared.forceCheckForUpdates {
            task.setTaskCompleted(success: true)
        }
    }

    private func _scheduleBackgroundUpdateCheck() {
        guard OptionsManager.shared.options.checkForUpdates,
              OptionsManager.shared.options.backgroundUpdateCheck else { return }

        let request = BGAppRefreshTaskRequest(identifier: "com.ksign.updateCheck")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule background update check: \(error)")
        }
    }

    // MARK: - Background Maintenance (BGProcessingTask)

    /// Handle the full background maintenance pipeline.
    /// Runs: source refresh → update detection → auto-update → cleanup → cert check.
    private func _handleBackgroundMaintenance(_ task: BGProcessingTask) {
        // Always reschedule the next run
        _scheduleBackgroundMaintenance()

        // Set up expiration — if iOS reclaims our time, clean up gracefully
        task.expirationHandler = {
            BackgroundMaintenanceCoordinator.shared.cancel()
            task.setTaskCompleted(success: false)
        }

        // Guard: only run if user has it enabled
        guard OptionsManager.shared.options.checkForUpdates,
              OptionsManager.shared.options.backgroundUpdateCheck,
              OptionsManager.shared.options.backgroundMaintenanceEnabled else {
            task.setTaskCompleted(success: true)
            return
        }

        Logger.misc.info("Background maintenance task started")

        // Run the full maintenance pipeline
        BackgroundMaintenanceCoordinator.shared.run { success in
            DispatchQueue.main.async {
                task.setTaskCompleted(success: success)
            }
        }
    }

    /// Schedule the next background maintenance run.
    /// Uses BGProcessingTaskRequest — supports multi-minute runtime,
    /// can require network + charging.
    private func _scheduleBackgroundMaintenance() {
        guard OptionsManager.shared.options.checkForUpdates,
              OptionsManager.shared.options.backgroundUpdateCheck,
              OptionsManager.shared.options.backgroundMaintenanceEnabled else { return }

        let request = BGProcessingTaskRequest(identifier: "com.ksign.backgroundMaintenance")

        // Interval (hours) — default 12
        let intervalHours = max(6, OptionsManager.shared.options.backgroundMaintenanceInterval)
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(intervalHours * 3600))

        // Require network (for source refresh + downloads)
        request.requiresNetworkConnectivity = true

        // Require charging (configurable — heavy task)
        request.requiresExternalPower = OptionsManager.shared.options.backgroundMaintenanceRequiresCharging

        do {
            try BGTaskScheduler.shared.submit(request)
            Logger.misc.info("Background maintenance scheduled for +\(intervalHours)h")
        } catch {
            Logger.misc.error("Could not schedule background maintenance: \(error)")
        }
    }
    
    private func _createPipeline() {
        DataLoader.sharedUrlCache.diskCapacity = 0
        
        let pipeline = ImagePipeline {
            let dataLoader: DataLoader = {
                let config = URLSessionConfiguration.default
                config.urlCache = nil
                return DataLoader(configuration: config)
            }()
            let dataCache = try? DataCache(name: "com.c0st1.ksign.datacache") // disk cache
            let imageCache = Nuke.ImageCache() // memory cache
            dataCache?.sizeLimit = 500 * 1024 * 1024
            imageCache.costLimit = 100 * 1024 * 1024
            $0.dataCache = dataCache
            $0.imageCache = imageCache
            $0.dataLoader = dataLoader
            $0.dataCachePolicy = .automatic
            $0.isStoringPreviewsInMemoryCache = false
        }
        
        ImagePipeline.shared = pipeline
    }
    
    private func _createSourcesDirectory() {
        let fileManager = FileManager.default
        
        let appDirectory = URL.documentsDirectory.appendingPathComponent("App")
        try? fileManager.createDirectoryIfNeeded(at: appDirectory)
        
        let directories = ["Signed", "Unsigned", "Archives", "Server", "Tweaks"].map {
            appDirectory.appendingPathComponent($0)
        }
        
        for url in directories {
            try? fileManager.createDirectoryIfNeeded(at: url)
        }
    }
    
    private func _clean() {
        let fileManager = FileManager.default
        let tmpDirectory = fileManager.temporaryDirectory
        
        if let files = try? fileManager.contentsOfDirectory(atPath: tmpDirectory.path()) {
            for file in files {
                try? fileManager.removeItem(atPath: tmpDirectory.appendingPathComponent(file).path())
            }
        }
    }
    
    private func _copyServerCertificates() {
        let fileManager = FileManager.default
        let serverDirectory = URL.documentsDirectory.appendingPathComponent("App/Server")
        
        try? fileManager.createDirectoryIfNeeded(at: serverDirectory)
        
        let filesToCopy = ["server.crt", "server.pem", "commonName.txt"]
        
        for fileName in filesToCopy {
            guard let bundleURL = Bundle.main.url(forResource: fileName.components(separatedBy: ".").first!, withExtension: fileName.components(separatedBy: ".").last!) else {
                print("File \(fileName) not found in app bundle")
                continue
            }
            
            let destinationURL = serverDirectory.appendingPathComponent(fileName)
            
            try? fileManager.removeItem(at: destinationURL)
            
            do {
                try fileManager.copyItem(at: bundleURL, to: destinationURL)
            } catch {
                print("Error copying \(fileName): \(error)")
            }
        }
    }
    
    private func _addDefaultCertificates() {
            guard
                UserDefaults.standard.bool(forKey: "feather.didImportDefaultCertificates") == false,
                let signingAssetsURL = Bundle.main.url(forResource: "signing-assets", withExtension: nil)
            else {
                return
            }
            
            do {
                let folderContents = try FileManager.default.contentsOfDirectory(
                    at: signingAssetsURL,
                    includingPropertiesForKeys: nil,
                    options: .skipsHiddenFiles
                )
                
                for folderURL in folderContents {
                    guard folderURL.hasDirectoryPath else { continue }
                    
                    let certName = folderURL.lastPathComponent
                    
                    let p12Url = folderURL.appendingPathComponent("cert.p12")
                    let provisionUrl = folderURL.appendingPathComponent("cert.mobileprovision")
                    let passwordUrl = folderURL.appendingPathComponent("cert.txt")
                    
                    guard
                        FileManager.default.fileExists(atPath: p12Url.path),
                        FileManager.default.fileExists(atPath: provisionUrl.path),
                        FileManager.default.fileExists(atPath: passwordUrl.path)
                    else {
                        Logger.misc.warning("Skipping \(certName): missing required files")
                        continue
                    }
                    
                    let password = try String(contentsOf: passwordUrl, encoding: .utf8)
                    
                    FR.handleCertificateFiles(
                        p12URL: p12Url,
                        provisionURL: provisionUrl,
                        p12Password: password,
                        certificateName: certName,
                    ) { _ in
                        
                    }
                }
                UserDefaults.standard.set(true, forKey: "feather.didImportDefaultCertificates")
            } catch {
                Logger.misc.error("Failed to list signing-assets: \(error)")
            }
        }

#if SERVER
    private func _downloadSSLCertificates() {
        let serverURL = "https://backloop.dev/pack.json"
        
        FR.downloadSSLCertificates(from: serverURL) { success in
            if success {
                print("SSL certificates downloaded successfully")
            } else {
                print("Failed to download SSL certificates")
            }
        }
    }
#endif
}
