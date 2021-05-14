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
            fatalError("Credentials must provide a user identifier")
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
    private lazy var managedObjectModel: NSManagedObjectModel = {
        guard let url = Bundle(for: MXRoomSummaryModel.self).url(forResource: Constants.modelName,
                                                                 withExtension: "momd") else {
            fatalError("No MXRoomSummaryStore Core Data model")
        }
        guard let result = NSManagedObjectModel(contentsOf: url) else {
            fatalError("Cannot create managed object model")
        }
        return result
    }()
    private lazy var persistenceCoordinator: NSPersistentStoreCoordinator = {
        let result = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)
        do {
            try result.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
        } catch {
            fatalError(error.localizedDescription)
        }
        return result
    }()
    private lazy var managedObjectContext: NSManagedObjectContext = {
        let result = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        result.persistentStoreCoordinator = persistenceCoordinator
        return result
    }()
    
    public init(withCredentials credentials: MXCredentials) {
        self.credentials = credentials
        super.init()
    }
    
    private func fetchSummary(forRoomId roomId: String) -> MXRoomSummaryModel? {
        let request = MXRoomSummaryModel.typedFetchRequest()
        request.predicate = NSPredicate(format: "identifier == %@", roomId)
        do {
            let results = try managedObjectContext.fetch(request)
            return results.first
        } catch {
            NSLog("[MXRoomSummaryCoreDataStore] fetchSummary failed: \(error)")
        }
        return nil
    }
    
}

extension MXRoomSummaryCoreDataStore: MXRoomSummaryStore {
    
    public func storeSummary(forRoom roomId: String, summary: MXRoomSummary) {
        if let existing = fetchSummary(forRoomId: roomId) {
            existing.update(withRoomSummary: summary, in: managedObjectContext)
        } else {
            let model = MXRoomSummaryModel.from(roomSummary: summary, in: managedObjectContext)
            managedObjectContext.insert(model)
        }

        do {
            if managedObjectContext.hasChanges {
                try managedObjectContext.save()
            }
        } catch {
            NSLog("[MXRoomSummaryCoreDataStore] storeSummary failed: \(error)")
        }
    }
    
    public func summary(ofRoom roomId: String) -> MXRoomSummary? {
        guard let result = fetchSummary(forRoomId: roomId) else {
            return nil
        }
        return MXRoomSummary(coreDataModel: result)
    }
    
}
