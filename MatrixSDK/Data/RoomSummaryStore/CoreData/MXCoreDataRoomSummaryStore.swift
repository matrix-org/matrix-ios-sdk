// 
// Copyright 2021 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation
import CoreData

@objcMembers
public class MXCoreDataRoomSummaryStore: NSObject {
    
    private enum Constants {
        static let modelName: String = "MXCoreDataRoomSummaryStore"
        static let folderName: String = "MXCoreDataRoomSummaryStore"
        static let storeFileName: String = "RoomSummaryStore.sqlite"
    }
    
    private let credentials: MXCredentials

    private lazy var persistenceCoordinator: NSPersistentStoreCoordinator = {
        let result = NSPersistentStoreCoordinator(managedObjectModel: Self.managedObjectModel)
        
        let options: [AnyHashable : Any] = [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true
        ]
        
        do {
            try result.addPersistentStore(ofType: NSSQLiteStoreType,
                                          configurationName: nil,
                                          at: storeURL,
                                          options: options)
        } catch {
            fatalError(error.localizedDescription)
        }
        return result
    }()
    
    private lazy var storeURL: URL = {
        guard let userId = credentials.userId else {
            fatalError("[MXCoreDataRoomSummaryStore] Credentials must provide a user identifier")
        }
        
        var cachePath: URL!
        if let container = FileManager.default.applicationGroupContainerURL() {
            cachePath = container
        } else {
            cachePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        }
        let folderUrl = cachePath.appendingPathComponent(Constants.folderName).appendingPathComponent(userId)
        try? FileManager.default.createDirectoryExcludedFromBackup(at: folderUrl)
        return folderUrl.appendingPathComponent(Constants.storeFileName)
    }()
    
    private static var managedObjectModel: NSManagedObjectModel = {
        guard let url = Bundle(for: MXCoreDataRoomSummaryStore.self).url(forResource: Constants.modelName,
                                                                         withExtension: "momd") else {
            fatalError("[MXCoreDataRoomSummaryStore] No MXRoomSummaryStore Core Data model")
        }
        guard let result = NSManagedObjectModel(contentsOf: url) else {
            fatalError("[MXCoreDataRoomSummaryStore] Cannot create managed object model")
        }
        return result
    }()
    
    /// Managed object context to be used when inserting data, whose parent context is `mainMoc`.
    private lazy var backgroundMoc: NSManagedObjectContext = {
        let result = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        result.parent = mainMoc
        return result
    }()
    
    /// Managed object context to be used on main thread for fetching data, whose parent context is `persistentMoc`.
    private lazy var mainMoc: NSManagedObjectContext = {
        let result = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        result.parent = persistentMoc
        result.automaticallyMergesChangesFromParent = true
        return result
    }()
    /// Managed object context bound to persistent store coordinator.
    private lazy var persistentMoc: NSManagedObjectContext = {
        let result = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        result.persistentStoreCoordinator = persistenceCoordinator
        return result
    }()
    
    public init(withCredentials credentials: MXCredentials) {
        self.credentials = credentials
        super.init()
        //  create main context
        _ = mainMoc
    }
    
    //  MARK: - Private
    
    private func countRooms(in moc: NSManagedObjectContext) -> Int {
        let request = MXRoomSummaryMO.typedFetchRequest()
        request.includesSubentities = false
        request.includesPropertyValues = false
        request.resultType = .countResultType
        var result = 0
        moc.performAndWait {
            do {
                result = try moc.count(for: request)
            } catch {
                MXLog.error("[MXCoreDataRoomSummaryStore] countRooms failed", context: error)
            }
        }
        return result
    }
    
    private func fetchRoomIds(in moc: NSManagedObjectContext) -> [String] {
        let propertyName = "s_identifier"
        
        guard let property = MXRoomSummaryMO.entity().propertiesByName[propertyName] else {
            fatalError("[MXCoreDataRoomSummaryStore] Couldn't find \(propertyName) on entity \(String(describing: MXRoomSummaryMO.self)), probably property name changed")
        }
        let request = MXRoomSummaryMO.genericFetchRequest()
        request.includesSubentities = false
        //  only fetch room identifiers
        request.propertiesToFetch = [property]
        //  when specific properties set, use dictionary result type for issues seen mostly on iOS 12 devices
        request.resultType = .dictionaryResultType
        var result: [String] = []
        moc.performAndWait {
            do {
                if let dictionaries = try moc.fetch(request) as? [[String: Any]] {
                    //  other properties than 'propertyName' won't exist in the dictionary
                    result = dictionaries.compactMap({ $0[propertyName] as? String })
                }
            } catch {
                MXLog.error("[MXCoreDataRoomSummaryStore] fetchRoomIds failed", context: error)
            }
        }
        return result
    }
    
    private func fetchSummary(forRoomId roomId: String, in moc: NSManagedObjectContext) -> MXRoomSummary? {
        let request = MXRoomSummaryMO.typedFetchRequest()
        request.predicate = NSPredicate(format: "%K == %@",
                                        #keyPath(MXRoomSummaryMO.s_identifier),
                                        roomId)
        var result: MXRoomSummary? = nil
        moc.performAndWait {
            do {
                let results = try moc.fetch(request)
                if let model = results.first {
                    result = MXRoomSummary(summaryModel: model)
                }
            } catch {
                MXLog.error("[MXCoreDataRoomSummaryStore] fetchSummary failed", context: error)
            }
        }
        return result
    }
    
    /// Inline method to fetch a summary managed object. Only to be called in moc.perform blocks.
    private func fetchSummaryMO(forRoomId roomId: String, in moc: NSManagedObjectContext) -> MXRoomSummaryMO? {
        let request = MXRoomSummaryMO.typedFetchRequest()
        request.predicate = NSPredicate(format: "%K == %@",
                                        #keyPath(MXRoomSummaryMO.s_identifier),
                                        roomId)
        do {
            let results = try moc.fetch(request)
            return results.first
        } catch {
            MXLog.error("[MXCoreDataRoomSummaryStore] fetchSummary failed", context: error)
        }
        return nil
    }
    
    private func saveSummary(_ summary: MXRoomSummaryProtocol) {
        let moc = backgroundMoc
        
        moc.performAndWait { [weak self] in
            guard let self = self else { return }
            if let existing = self.fetchSummaryMO(forRoomId: summary.roomId, in: moc) {
                existing.update(withRoomSummary: summary, in: moc)
            } else {
                let model = MXRoomSummaryMO.insert(roomSummary: summary, into: moc)
                do {
                    try moc.obtainPermanentIDs(for: [model])
                } catch {
                    MXLog.error("[MXCoreDataRoomSummaryStore] saveSummary couldn't obtain permanent id", context: error)
                }
            }
            
            self.saveIfNeeded(moc)
        }
    }
    
    private func deleteSummary(forRoomId roomId: String) {
        let moc = backgroundMoc
        
        moc.performAndWait { [weak self] in
            guard let self = self else { return }
            if let existing = self.fetchSummaryMO(forRoomId: roomId, in: moc) {
                moc.delete(existing)
            }
            
            self.saveIfNeeded(moc)
        }
    }
    
    private func deleteAllSummaries() {
        let entityNames: [String] = [
            MXRoomSummaryMO.entityName,
            MXRoomLastMessageMO.entityName,
            MXUsersTrustLevelSummaryMO.entityName,
            MXRoomMembersCountMO.entityName
        ]
        
        let moc = backgroundMoc
        
        moc.performAndWait { [weak self] in
            guard let self = self else { return }
            do {
                for entityName in entityNames {
                    let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                    let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
                    try moc.execute(deleteRequest)
                }
                
                self.saveIfNeeded(moc)
            } catch {
                MXLog.error("[MXCoreDataRoomSummaryStore] deleteAllSummaries failed", context: error)
            }
        }
    }
    
    private func allSummaries(_ completion: @escaping ([MXRoomSummaryProtocol]) -> Void) {
        let request = MXRoomSummaryMO.typedFetchRequest()
        
        let moc = backgroundMoc
        
        moc.perform {
            do {
                let results = try moc.fetch(request)
                //  do not attempt to access other properties from the results
                let mapped = results.compactMap({ MXRoomSummary(summaryModel: $0) })
                DispatchQueue.main.async {
                    completion(mapped)
                }
            } catch {
                MXLog.error("[MXCoreDataRoomSummaryStore] fetchRoomIds failed", context: error)
            }
        }
    }
    
    /// Inline method to save a managed object context if needed. Only to be called in moc.perform blocks.
    private func saveIfNeeded(_ moc: NSManagedObjectContext) {
        guard moc.hasChanges else {
            return
        }

        var saved = false
        do {
            try moc.save()
            saved = true
        } catch {
            moc.rollback()
            MXLog.error("[MXCoreDataRoomSummaryStore] saveIfNeeded failed", context: error)
        }

        if saved {
            //  save all parent contexts recursively
            if let parent = moc.parent {
                parent.perform {
                    self.saveIfNeeded(parent)
                }
            }
        }
    }
    
}

//  MARK: - MXRoomSummaryStore

extension MXCoreDataRoomSummaryStore: MXRoomSummaryStore {
    
    public var rooms: [String] {
        return fetchRoomIds(in: mainMoc)
    }
    
    public var countOfRooms: UInt {
        return UInt(countRooms(in: mainMoc))
    }
    
    public func storeSummary(_ summary: MXRoomSummaryProtocol) {
        saveSummary(summary)
    }
    
    public func summary(ofRoom roomId: String) -> MXRoomSummaryProtocol? {
        return fetchSummary(forRoomId: roomId, in: mainMoc)
    }
    
    public func removeSummary(ofRoom roomId: String) {
        deleteSummary(forRoomId: roomId)
    }
    
    public func removeAllSummaries() {
        deleteAllSummaries()
    }
    
    public func fetchAllSummaries(_ completion: @escaping ([MXRoomSummaryProtocol]) -> Void) {
        allSummaries(completion)
    }
    
}

//  MARK: - CoreDataContextable

extension MXCoreDataRoomSummaryStore: CoreDataContextable {
    
    var mainManagedObjectContext: NSManagedObjectContext {
        return mainMoc
    }
    
}
