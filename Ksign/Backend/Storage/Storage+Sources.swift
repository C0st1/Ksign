//
//  Storage+Sources.swift
//  Feather
//
//  Created by samara on 12.04.2025.
//

import CoreData
import AltSourceKit

// MARK: - Class extension: Sources
extension Storage {
        /// Retrieve sources in an array, we don't normally need this in swiftUI but we have it for the copy sources action
        func getSources() -> [AltSource] {
                let request: NSFetchRequest<AltSource> = AltSource.fetchRequest()
                return (try? context.fetch(request)) ?? []
        }
        
        func addSource(
                _ url: URL,
                name: String? = "Unknown",
                identifier: String,
                iconURL: URL? = nil,
                deferSave: Bool = false,
                isBuiltIn: Bool = false,
                completion: @escaping (Error?) -> Void
        ) {
                if sourceExists(identifier) {
                        completion(nil)
                        print("ignoring \(identifier)")
                        return
                }
                
                let new = AltSource(context: context)
                new.name = name
                new.date = Date()
                new.identifier = identifier
                new.sourceURL = url
                new.iconURL = iconURL
                new.setValue(isBuiltIn, forKey: "isBuiltIn")
                
                do {
                        if !deferSave {
                                try context.save()
                        }
                        completion(nil)
                } catch {
                        completion(error)
                }
        }
        
        func addSource(
                _ url: URL,
                repository: ASRepository,
                id: String = "",
                deferSave: Bool = false,
                isBuiltIn: Bool = false,
                completion: @escaping (Error?) -> Void
        ) {
                addSource(
                        url,
                        name: repository.name,
                        identifier: !id.isEmpty
                                                ? id
                                                : (repository.id ?? url.absoluteString),
                        iconURL: repository.currentIconURL,
                        deferSave: deferSave,
                        isBuiltIn: isBuiltIn,
                        completion: completion
                )
        }

        func addSources(
                repos: [URL: ASRepository],
                completion: @escaping (Error?) -> Void
        ) {
                for (url, repo) in repos {
                        addSource(
                                url,
                                repository: repo,
                                deferSave: true,
                                completion: { error in
                                        if let error {
                                                completion(error)
                                        }
                                }
                        )
                }
                
        saveContext()
        completion(nil)
        }


        func addBuiltInSources() {
                // Only add the Ksign repo by default.
                // Other sources can be added by the user via SourcesAddView.
                let ksignSourceURL = "https://raw.githubusercontent.com/C0st1/Ksign/refs/heads/main/repo.json"
                FR.handleSource(ksignSourceURL) { }
        }

        /// Suggested sources the user can optionally add from SourcesAddView.
        static let suggestedSourceURLs: [(name: String, url: String)] = [
                ("SideStore Community", "https://community-apps.sidestore.io/sidecommunity.json"),
                ("iTorrent", "https://xitrix.github.io/iTorrent/AltStore.json"),
                ("AppTesters", "https://repository.apptesters.org"),
                ("LiveContainer", "https://github.com/LiveContainer/LiveContainer/releases/download/1.0/apps.json"),
                ("Cypwn", "https://ipa.cypwn.xyz/cypwn.json"),
                ("Crystall1ne", "https://alt.crystall1ne.dev")
        ]

        func deleteSource(for source: AltSource) {
                context.delete(source)
                saveContext()
        }

        func sourceExists(_ identifier: String) -> Bool {
                let fetchRequest: NSFetchRequest<AltSource> = AltSource.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "identifier == %@", identifier)

                do {
                        let count = try context.count(for: fetchRequest)
                        return count > 0
                } catch {
                        print("Error checking if repository exists: \(error)")
                        return false
                }
        }
}
