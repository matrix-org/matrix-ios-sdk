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
public class MXRoomSummaryCoreDataStore: NSObject {
    
    private enum Constants {
        static let modelName: String = "MXRoomSummaryStore"
        static let folderName: String = "RoomSummaryStore"
        static let storeFileName: String = "RoomSummaryStore.sqlite"
    }
    
    private let credentials: MXCredentials
    
    private lazy var storeURL: URL = {
        guard let userId = credentials.userId else {
            fatalError("[MXRoomSummaryCoreDataStore] Credentials must provide a user identifier")
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
    private lazy var storeDescription: NSPersistentStoreDescription = {
        let result = NSPersistentStoreDescription(url: storeURL)
        result.type = NSSQLiteStoreType
        result.shouldAddStoreAsynchronously = false
        return result
    }()
    private lazy var managedObjectModel: NSManagedObjectModel = {
        guard let url = Bundle(for: MXRoomSummaryModel.self).url(forResource: Constants.modelName,
                                                                 withExtension: "momd") else {
            fatalError("[MXRoomSummaryCoreDataStore] No MXRoomSummaryStore Core Data model")
        }
        guard let result = NSManagedObjectModel(contentsOf: url) else {
            fatalError("[MXRoomSummaryCoreDataStore] Cannot create managed object model")
        }
        return result
    }()
    private lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "", managedObjectModel: managedObjectModel)
        container.persistentStoreDescriptions = [storeDescription]
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                fatalError("[MXRoomSummaryCoreDataStore] Unresolved error \(error), \(error.userInfo)")
            }
        }
        return container
    }()
    private lazy var writerMoc: NSManagedObjectContext = {
        return persistentContainer.newBackgroundContext()
    }()
    private var readerMoc: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    public init(withCredentials credentials: MXCredentials) {
        self.credentials = credentials
        super.init()
    }
    
    private func fetchRoomIds() -> [String] {
        let request = MXRoomSummaryModel.typedFetchRequest()
        do {
            let results = try readerMoc.fetch(request)
            return results.map({ $0.s_identifier })
        } catch {
            MXLog.error("[MXRoomSummaryCoreDataStore] fetchRoomIds failed: \(error)")
        }
        return []
    }
    
    private func fetchSummary(forRoomId roomId: String) -> MXRoomSummaryModel? {
        let request = MXRoomSummaryModel.typedFetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", #keyPath(MXRoomSummaryModel.s_identifier), roomId)
        do {
            let results = try readerMoc.fetch(request)
            return results.first
        } catch {
            MXLog.error("[MXRoomSummaryCoreDataStore] fetchSummary failed: \(error)")
        }
        return nil
    }
    
}

extension MXRoomSummaryCoreDataStore: MXRoomSummaryStore {
    
    public var rooms: [String] {
        return fetchRoomIds()
    }
    
    public func storeSummary(forRoom roomId: String, summary: MXRoomSummaryProtocol) {
        if let existing = fetchSummary(forRoomId: roomId), let existingInWriter = writerMoc.object(with: existing.objectID) as? MXRoomSummaryModel {
            existingInWriter.update(withRoomSummary: summary, in: writerMoc)
        } else {
            MXRoomSummaryModel.insert(roomSummary: summary, into: writerMoc)
        }

        do {
            if writerMoc.hasChanges {
                try writerMoc.save()
            }
        } catch {
            MXLog.error("[MXRoomSummaryCoreDataStore] storeSummary failed: \(error)")
        }
    }
    
    public func summary(ofRoom roomId: String) -> MXRoomSummaryProtocol? {
        return fetchSummary(forRoomId: roomId)
    }
    
}
