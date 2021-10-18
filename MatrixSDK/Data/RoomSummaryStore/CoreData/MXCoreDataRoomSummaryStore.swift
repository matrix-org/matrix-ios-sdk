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
    
    private lazy var storeURL: URL = {
        guard let userId = credentials.userId else {
            fatalError("[MXCoreDataRoomSummaryStore] Credentials must provide a user identifier")
        }
        
        var cachePath: URL!
        if let appGroupIdentifier = MXSDKOptions.sharedInstance().applicationGroupIdentifier {
            cachePath = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        } else {
            cachePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        }
        let folderUrl = cachePath.appendingPathComponent(Constants.folderName).appendingPathComponent(userId)
        try? FileManager.default.createDirectory(at: folderUrl, withIntermediateDirectories: true, attributes: nil)
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
    private lazy var persistenceCoordinator: NSPersistentStoreCoordinator = {
        let result = NSPersistentStoreCoordinator(managedObjectModel: Self.managedObjectModel)
        do {
            try result.addPersistentStore(ofType: NSSQLiteStoreType,
                                          configurationName: nil,
                                          at: storeURL,
                                          options: nil)
        } catch {
            fatalError(error.localizedDescription)
        }
        return result
    }()
    
    private lazy var mainMoc: NSManagedObjectContext = {
        let result = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        result.automaticallyMergesChangesFromParent = true
        result.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        result.parent = persistentMoc
        return result
    }()
    private lazy var persistentMoc: NSManagedObjectContext = {
        let result = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        result.persistentStoreCoordinator = persistenceCoordinator
        return result
    }()
    
    public init(withCredentials credentials: MXCredentials) {
        self.credentials = credentials
        super.init()
        //  create persistent container
        _ = persistenceCoordinator
    }
    
    //  MARK: - Private
    
    private func createTempMoc() -> NSManagedObjectContext {
        let result = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        result.parent = mainMoc
        return result
    }
    
    private func fetchRoomIds(in moc: NSManagedObjectContext) -> [String] {
        let propertyName = "s_identifier"
        
        guard let property = MXRoomSummaryModel.entity().propertiesByName[propertyName] else {
            fatalError("[MXCoreDataRoomSummaryStore] Couldn't find \(propertyName) on entity \(String(describing: MXRoomSummaryModel.self)), probably property name changed")
        }
        let request = MXRoomSummaryModel.typedFetchRequest()
        request.returnsDistinctResults = true
        request.includesSubentities = false
        //  only fetch room identifiers
        request.propertiesToFetch = [property]
        do {
            let results = try moc.fetch(request)
            //  do not attempt to access other properties from the results
            return results.map({ $0.s_identifier })
        } catch {
            MXLog.error("[MXCoreDataRoomSummaryStore] fetchRoomIds failed: \(error)")
        }
        return []
    }
    
    private func fetchSummary(forRoomId roomId: String, in moc: NSManagedObjectContext) -> MXRoomSummaryModel? {
        let request = MXRoomSummaryModel.typedFetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", #keyPath(MXRoomSummaryModel.s_identifier), roomId)
        do {
            let results = try moc.fetch(request)
            return results.first
        } catch {
            MXLog.error("[MXCoreDataRoomSummaryStore] fetchSummary failed: \(error)")
        }
        return nil
    }
    
    private func saveSummary(_ summary: MXRoomSummaryProtocol) {
        let moc = createTempMoc()
        
        moc.perform { [weak self] in
            guard let self = self else { return }
            if let existing = self.fetchSummary(forRoomId: summary.roomId, in: moc) {
                existing.update(withRoomSummary: summary, in: moc)
            } else {
                MXRoomSummaryModel.insert(roomSummary: summary, into: moc)
            }
            
            self.saveIfNeeded(moc)
        }
    }
    
    private func deleteSummary(forRoomId roomId: String) {
        let moc = createTempMoc()
        
        moc.perform { [weak self] in
            guard let self = self else { return }
            if let existing = self.fetchSummary(forRoomId: roomId, in: moc) {
                moc.delete(existing)
            }
            
            self.saveIfNeeded(moc)
        }
    }
    
    private func deleteAllSummaries() {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: MXRoomSummaryModel.entityName)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        
        let moc = createTempMoc()
        
        moc.perform { [weak self] in
            guard let self = self else { return }
            do {
                try moc.execute(deleteRequest)
                
                self.saveIfNeeded(moc)
            } catch {
                MXLog.error("[MXCoreDataRoomSummaryStore] deleteAllSummaries failed: \(error)")
            }
        }
    }
    
    private func allSummaries(_ completion: @escaping ([MXRoomSummaryProtocol]) -> Void) {
        let request = MXRoomSummaryModel.typedFetchRequest()
        
        let moc = createTempMoc()
        
        moc.perform {
            do {
                let results = try moc.fetch(request)
                //  do not attempt to access other properties from the results
                let mapped = results.compactMap({ MXRoomSummary(summaryModel: $0) })
                DispatchQueue.main.async {
                    completion(mapped)
                }
            } catch {
                MXLog.error("[MXCoreDataRoomSummaryStore] fetchRoomIds failed: \(error)")
            }
        }
    }
    
    private func saveIfNeeded(_ moc: NSManagedObjectContext) {
        guard moc.hasChanges else {
            return
        }
        moc.perform { [weak self] in
            guard let self = self else { return }
            do {
                try moc.save()
                //  propogate changes to the parent context, until reaching the persistent store
                if let parent = moc.parent {
                    self.saveIfNeeded(parent)
                }
            } catch {
                moc.rollback()
                MXLog.error("[MXCoreDataRoomSummaryStore] saveIfNeeded failed: \(error)")
            }
        }
    }
    
}

//  MARK: - MXRoomSummaryStore

extension MXCoreDataRoomSummaryStore: MXRoomSummaryStore {
    
    public var rooms: [String] {
        return fetchRoomIds(in: mainMoc)
    }
    
    public func storeSummary(_ summary: MXRoomSummaryProtocol) {
        saveSummary(summary)
    }
    
    public func summary(ofRoom roomId: String) -> MXRoomSummaryProtocol? {
        if let model = fetchSummary(forRoomId: roomId, in: mainMoc) {
            return MXRoomSummary(summaryModel: model)
        }
        return nil
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
    
    var managedObjectContext: NSManagedObjectContext {
        return mainMoc
    }
    
}
