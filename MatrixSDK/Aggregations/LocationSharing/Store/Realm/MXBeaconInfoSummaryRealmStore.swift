// 
// Copyright 2022 The Matrix.org Foundation C.I.C
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
import Realm

@objcMembers
public class MXBeaconInfoSummaryRealmStore: NSObject {

    // MARK: - Constants
    
    private enum Database {
        static let folderName = "BeaconInfoSummaries"
        static let filename = "BeaconInfoSummaries"
        
        // TODO: Use a private modulemap to import private Objective-C files in Swift. To be able to use `MXRealmHelper` here.
        static let fileExtension = "realm"
    }
    
    private enum BeaconInfoSummaryPredicate {
        
        static func identifier(_ identifier: String) -> NSPredicate {
            return NSPredicate(format: "%K = %@",
                               #keyPath(MXRealmBeaconInfoSummary.identifier), identifier)
        }
        
        static func room(_ roomId: String) -> NSPredicate {
            return NSPredicate(format: "%K = %@",
                               #keyPath(MXRealmBeaconInfoSummary.roomId), roomId)
        }
        
        static func user(_ userId: String) -> NSPredicate {
            return NSPredicate(format: "%K = %@",
                                        #keyPath(MXRealmBeaconInfoSummary.userId), userId)
        }
    }
    
    // MARK: - Properties
    
    private unowned let session: MXSession
    private let mapper: MXRealmBeaconMapper
    
    private var realm: RLMRealm? {
        guard let userId = self.session.myUserId else {
            return nil
        }
        return self.realmStore(for: userId)
    }
    
    // MARK: - Setup
    
    public init(session: MXSession) {
        self.session = session
        self.mapper = MXRealmBeaconMapper(session: session)

        super.init()
    }
    
    // MARK: - Private
    
    private func realmStore(for userId: String) -> RLMRealm? {
        do {
            let configuration = try self.realmConfiguration(for: userId)
            
            let realm = try RLMRealm(configuration: configuration)
            
            return realm
        } catch {
        
            MXLog.error("[MXBeaconInfoSummaryRealmStore] failed to create Realm store", context: error)
            return nil
        }
    }
    
    private func realmConfiguration(for userId: String) throws -> RLMRealmConfiguration {
        let realmConfiguration = RLMRealmConfiguration.default()
        
        let realmFileURL = try self.getStoreURL(for: userId)

        realmConfiguration.fileURL = realmFileURL
        realmConfiguration.deleteRealmIfMigrationNeeded = true

        // Manage only our objects in this realm
        realmConfiguration.objectClasses = [
            MXRealmBeaconInfoSummary.self,
            MXRealmBeaconInfo.self,
            MXRealmBeacon.self
        ]

        return realmConfiguration
    }
    
    private func getStoreURL(for userId: String) throws -> URL {
        
        let userDirectoryURL: URL
        
        do {
            
            let rootDirectoryURL: URL
            
            // Store the Realm file in the shared container if possible
            if let containerURL = FileManager.default.applicationGroupContainerURL() {
                rootDirectoryURL = containerURL
            } else {
                rootDirectoryURL = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            }
            
            userDirectoryURL = rootDirectoryURL.appendingPathComponent(userId)
            
        } catch {
            MXLog.error("[MXBeaconInfoSummaryRealmStore] Fail to get user directory")
            
            throw error
        }
        
        let realmFileFolderURL = userDirectoryURL.appendingPathComponent(Database.folderName, isDirectory: true)
        let realmFileURL = realmFileFolderURL.appendingPathComponent(Database.filename, isDirectory: false).appendingPathExtension(Database.fileExtension)
        
        do {
            try FileManager.default.createDirectory(at: realmFileFolderURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            MXLog.error("[MXBeaconInfoSummaryRealmStore] Fail to create Realm folder", context: error)
            throw error
        }
        
        return realmFileURL
    }
    
    private func realmBeaconInfoSummaryResults(in realm: RLMRealm, with roomId: String) -> RLMResults<MXRealmBeaconInfoSummary> {
        let roomPredicate = BeaconInfoSummaryPredicate.room(roomId)
        return self.realmBeaconInfoSummaryResults(in: realm, with: roomPredicate)
    }
    
    private func realmBeaconInfoSummaryResults(in realm: RLMRealm, with predicate: NSPredicate) -> RLMResults<MXRealmBeaconInfoSummary> {
        
        guard let realmSummaries = MXRealmBeaconInfoSummary.objects(in: realm, with: predicate) as? RLMResults<MXRealmBeaconInfoSummary> else {
            fatalError()
        }
        return realmSummaries
    }
    
    private func beaconInfoSummaries(from realmBeaconInfoSummaryResults: RLMResults<MXRealmBeaconInfoSummary>) -> [MXBeaconInfoSummary] {
        
        var summaries: [MXBeaconInfoSummary] = []
        
        for realmSummary in realmBeaconInfoSummaryResults {
            
            if let realmBeaconInfoSummary = realmSummary as? MXRealmBeaconInfoSummary, let summary = self.mapper.beaconInfoSummary(from: realmBeaconInfoSummary) {
                summaries.append(summary)
            }
        }
        
        return summaries
    }
}

// MARK: - MXBeaconInfoSummaryStoreProtocol
extension MXBeaconInfoSummaryRealmStore: MXBeaconInfoSummaryStoreProtocol {
    
    public func addOrUpdateBeaconInfoSummary(_ beaconInfoSummary: MXBeaconInfoSummary, inRoomWithId roomId: String) {
          
        guard let realm = self.realm else {
            return
        }
        
        do {
            try realm.mx_transaction(name: "[MXBeaconInfoSummaryRealmStore] addOrUpdateBeaconInfoSummary") {
                let realmBeaconInfoSummary =  self.mapper.realmBeaconInfoSummary(from: beaconInfoSummary)
                realm.addOrUpdate(realmBeaconInfoSummary)
            }
        } catch {
            MXLog.error("[MXBeaconInfoSummaryRealmStore] addOrUpdateBeaconInfoSummary failed", context: error)
        }
    }
    
    public func getBeaconInfoSummary(withIdentifier identifier: String, inRoomWithId roomId: String) -> MXBeaconInfoSummary? {
        
        guard let realm = self.realm else {
            return nil
        }
        
        let identifierPredicate = BeaconInfoSummaryPredicate.identifier(identifier)
        let roomPredicate = BeaconInfoSummaryPredicate.room(roomId)
                
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [identifierPredicate, roomPredicate])
        
        guard let realmBeaconInfoSummary = self.realmBeaconInfoSummaryResults(in: realm, with: predicate).firstObject() else {
            return nil
        }
        
        return self.mapper.beaconInfoSummary(from: realmBeaconInfoSummary)
    }
    
    public func getBeaconInfoSummary(withUserId userId: String, description: String?, timeout: UInt64, timestamp: UInt64, inRoomWithId roomId: String) -> MXBeaconInfoSummary? {
        
        guard let realm = self.realm else {
            return nil
        }
        
        let roomPredicate = BeaconInfoSummaryPredicate.room(roomId)
        
        let userPredicate = BeaconInfoSummaryPredicate.user(userId)
        
        let timeoutPredicate = NSPredicate(format: "%K = %ld",
                                           #keyPath(MXRealmBeaconInfoSummary.beaconInfo.timeout), Int(timeout))
        
        let timestampPredicate = NSPredicate(format: "%K = %ld", #keyPath(MXRealmBeaconInfoSummary.beaconInfo.timestamp), Int(timestamp))
                
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [roomPredicate, userPredicate, timeoutPredicate, timestampPredicate])

        let summaries = self.realmBeaconInfoSummaryResults(in: realm, with: predicate)
        
                
        guard let realmBeaconInfoSummary = summaries.firstObject() else {
            return nil
        }
        
        return self.mapper.beaconInfoSummary(from: realmBeaconInfoSummary)
    }
    
    public func getBeaconInfoSummaries(for userId: String, inRoomWithId roomId: String) -> [MXBeaconInfoSummary] {

        guard let realm = self.realm else {
            return []
        }
        
        let roomPredicate = BeaconInfoSummaryPredicate.room(roomId)
        let userPredicate = BeaconInfoSummaryPredicate.user(userId)
        
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [roomPredicate, userPredicate])

        let realmSummaries = self.realmBeaconInfoSummaryResults(in: realm, with: predicate)
        
        return self.beaconInfoSummaries(from: realmSummaries)
    }
    
    public func getAllBeaconInfoSummaries(forUserId userId: String) -> [MXBeaconInfoSummary] {
        
        guard let realm = self.realm else {
            return []
        }
        
        let userPredicate = BeaconInfoSummaryPredicate.user(userId)
        
        let realmSummaries = self.realmBeaconInfoSummaryResults(in: realm, with: userPredicate)
        
        return self.beaconInfoSummaries(from: realmSummaries)
    }
    
    public func getAllBeaconInfoSummaries(inRoomWithId roomId: String) -> [MXBeaconInfoSummary] {
        
        guard let realm = self.realm else {
            return []
        }
        
        let realmSummaries = self.realmBeaconInfoSummaryResults(in: realm, with: roomId)
        
        return self.beaconInfoSummaries(from: realmSummaries)
    }
    
    public func deleteBeaconInfoSummary(with identifier: String, inRoomWithId roomId: String) {
        guard let realm = self.realm else {
            return
        }
        
        do {
            try realm.mx_transaction(name: "[MXBeaconInfoSummaryRealmStore] deleteBeaconInfoSummary(with identifier:, inRoomWithId:)") {
                
                let identifierPredicate = BeaconInfoSummaryPredicate.identifier(identifier)
                let roomPredicate = BeaconInfoSummaryPredicate.room(roomId)
                
                let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [identifierPredicate, roomPredicate])
                
                let realmBeaconInfoSummaries = self.realmBeaconInfoSummaryResults(in: realm, with: predicate)
                
                realm.deleteObjects(realmBeaconInfoSummaries)
            }
        } catch {
            MXLog.error("[MXBeaconInfoSummaryRealmStore] deleteAllBeaconInfoSummaries failed", context: error)
        }
    }
    
    public func deleteAllBeaconInfoSummaries(inRoomWithId roomId: String) {
        
        guard let realm = self.realm else {
            return
        }
        
        do {
            try realm.mx_transaction(name: "[MXBeaconInfoSummaryRealmStore] deleteAllBeaconInfoSummaries inRoomWithId") {
                let realmBeaconInfoSummaries = self.realmBeaconInfoSummaryResults(in: realm, with: roomId)
                realm.deleteObjects(realmBeaconInfoSummaries)
            }
        } catch {
            MXLog.error("[MXBeaconInfoSummaryRealmStore] deleteAllBeaconInfoSummaries failed", context: error)
        }
    }
    
    public func deleteAllBeaconInfoSummaries() {
        
        guard let realm = self.realm else {
            return
        }
        
        do {
            try realm.mx_transaction(name: "[MXBeaconInfoSummaryRealmStore] deleteAllBeaconInfoSummaries") {
                realm.deleteAllObjects()
            }
        } catch {
            MXLog.error("[MXBeaconInfoSummaryRealmStore] Failed to delete all objects", context: error)
        }
    }
}
