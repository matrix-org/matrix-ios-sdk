// 
// Copyright 2020 The Matrix.org Foundation C.I.C
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

@objcMembers
/// Sync response storage in a file implementation.
///
/// File structure is the following:
/// + NSCachesDirectory or shared group id folder
///     + SyncResponse
///         + Matrix user id (one folder per account)
///             + SyncResponses
///                 L syncResponse-xxx
///                 L syncResponse-yyy
///                 L ...
///             L metadata
///
public class MXSyncResponseFileStore: NSObject {
    
    private enum Constants {
        static let folderName = "SyncResponse"
        static let metadataFileName = "metadata"
        static let syncResponsesFolderName = "SyncResponses"
        static let syncResponseFileNameTemplate = "syncResponse-%@"
        static let fileEncoding: String.Encoding = .utf8
        static let v0FileName = "syncResponse"                          // Unique file used before storing multiple sync reponse
    }
    
    private let fileOperationQueue: DispatchQueue
    private var metadataFilePath: URL
    private var syncResponsesFolderPath: URL
    
    public init(withCredentials credentials: MXCredentials) {
        guard let userId = credentials.userId else {
            fatalError("Credentials must provide a user identifier")
        }
        var cachePath: URL!
        
        if let container = FileManager.default.applicationGroupContainerURL() {
            cachePath = container
        } else {
            cachePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        }
        
        metadataFilePath = cachePath
            .appendingPathComponent(Constants.folderName)
            .appendingPathComponent(userId)
            .appendingPathComponent(Constants.metadataFileName)
        
        let syncResponsesFolderPath = cachePath
            .appendingPathComponent(Constants.folderName)
            .appendingPathComponent(userId)
            .appendingPathComponent(Constants.syncResponsesFolderName)
        self.syncResponsesFolderPath = syncResponsesFolderPath
        
        fileOperationQueue = DispatchQueue(label: "MXSyncResponseFileStore-" + MXTools.generateSecret())

        fileOperationQueue.async {
            try? FileManager.default.createDirectoryExcludedFromBackup(at: syncResponsesFolderPath)
            
            // Clean the single cache file used for "v0"
            // TODO: Remove it at some point
            let v0filePath = cachePath
                .appendingPathComponent(Constants.folderName)
                .appendingPathComponent(userId)
                .appendingPathComponent(Constants.v0FileName)
            try? FileManager.default.removeItem(at: v0filePath)
        }
    }
    
    private func syncResponsePath(withId id: String) -> URL {
        let fileName = String(format: Constants.syncResponseFileNameTemplate, id)
        return syncResponsesFolderPath.appendingPathComponent(fileName)
    }
    
    private func readSyncResponse(path: URL) -> MXCachedSyncResponse? {
        autoreleasepool {
            let stopwatch = MXStopwatch()
            
            var fileContents: String?
            
            fileOperationQueue.sync {
                fileContents = try? String(contentsOf: path,
                                           encoding: Constants.fileEncoding)
                MXLog.debug("[MXSyncResponseFileStore] readData: File read of \(fileContents?.count ?? 0) bytes lasted \(stopwatch.readable()). Free memory: \(MXMemory.formattedMemoryAvailable())")
                
            }
            
            stopwatch.reset()
            guard let jsonString = fileContents else {
                return nil
            }
            guard let json = MXTools.deserialiseJSONString(jsonString) as? [AnyHashable: Any] else {
                return nil
            }
            
            let syncResponse = MXCachedSyncResponse(fromJSON: json)
            
            MXLog.debug("[MXSyncResponseFileStore] readData: Consersion to model lasted \(stopwatch.readable()). Free memory: \(MXMemory.formattedMemoryAvailable())")
            return syncResponse
        }
    }
    
    private func saveSyncResponse(path: URL, syncResponse: MXCachedSyncResponse?) {
        let stopwatch = MXStopwatch()
        
        fileOperationQueue.async {
            guard let syncResponse = syncResponse else {
                try? FileManager.default.removeItem(at: path)
                MXLog.debug("[MXSyncResponseFileStore] saveData: File remove lasted \(stopwatch.readable())")
                return
            }
            
            try? syncResponse.jsonString()?.write(to: path,
                                                  atomically: true,
                                                  encoding: Constants.fileEncoding)
            MXLog.debug("[MXSyncResponseFileStore] saveData: File write lasted \(stopwatch.readable()). Free memory: \(MXMemory.formattedMemoryAvailable())")
        }
    }
    
    private func readMetaData() -> MXSyncResponseStoreMetaDataModel {
        var fileData: Data?
        fileOperationQueue.sync {
            fileData = try? Data(contentsOf: metadataFilePath)
        }
        
        guard let data = fileData else {
            MXLog.debug("[MXSyncResponseFileStore] readMetaData: File does not exist")
            return MXSyncResponseStoreMetaDataModel()
        }
        
        do {
            let metadata = try PropertyListDecoder().decode(MXSyncResponseStoreMetaDataModel.self, from: data)
            return metadata
        } catch let error {
            MXLog.debug("[MXSyncResponseFileStore] readMetaData: Failed to decode. Error: \(error)")
            return MXSyncResponseStoreMetaDataModel()
        }
    }
    
    private func saveMetaData(_ metadata: MXSyncResponseStoreMetaDataModel?) {
        fileOperationQueue.async {
            guard let metadata = metadata else {
                try? FileManager.default.removeItem(at: self.metadataFilePath)
                MXLog.debug("[MXSyncResponseFileStore] saveMetaData: Remove file")
                return
            }
            
            do {
                let data = try PropertyListEncoder().encode(metadata)
                try data.write(to: self.metadataFilePath)
            } catch let error {
                MXLog.debug("[MXSyncResponseFileStore] saveMetaData: Failed to store. Error: \(error)")
            }
        }
    }
    
    private func addSyncResponseId(id: String) {
        var metadata = readMetaData()
        metadata.syncResponseIds.append(id)
        saveMetaData(metadata)
    }
    
    private func deleteSyncResponseId(id: String) {
        deleteSyncResponseIds(ids: [id])
    }

    private func deleteSyncResponseIds(ids: [String]) {
        var metadata = readMetaData()
        metadata.syncResponseIds.removeAll(where: { ids.contains($0) })
        metadata.outdatedSyncResponseIds.removeAll(where: { ids.contains($0) })
        saveMetaData(metadata)
    }
}

//  MARK: - MXSyncResponseStore

extension MXSyncResponseFileStore: MXSyncResponseStore {
    
    public func addSyncResponse(syncResponse: MXCachedSyncResponse) -> String {
        let id = UUID().uuidString
        saveSyncResponse(path: syncResponsePath(withId: id), syncResponse: syncResponse)
        addSyncResponseId(id: id)
        return id
    }
    
    public func syncResponse(withId id: String) throws -> MXCachedSyncResponse {
        guard let syncResponse = readSyncResponse(path: syncResponsePath(withId: id)) else {
            throw MXSyncResponseStoreError.unknownId
        }
        return syncResponse
    }
    
    public func syncResponseSize(withId id: String) -> Int {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: syncResponsePath(withId: id).path),
              let size = attributes[FileAttributeKey.size] as? Int else {
            return 0
        }
        return size
    }
    
    public func updateSyncResponse(withId id: String, syncResponse: MXCachedSyncResponse) {
        saveSyncResponse(path: syncResponsePath(withId: id), syncResponse: syncResponse)
    }
    
    public func deleteSyncResponse(withId id: String) {
        saveSyncResponse(path: syncResponsePath(withId: id), syncResponse: nil)
        deleteSyncResponseId(id: id)
    }

    public func deleteSyncResponses(withIds ids: [String]) {
        for id in ids {
            saveSyncResponse(path: syncResponsePath(withId: id), syncResponse: nil)
        }
        deleteSyncResponseIds(ids: ids)
    }
    
    public var syncResponseIds: [String] {
        readMetaData().syncResponseIds
    }
    
    public var outdatedSyncResponseIds: [String] {
        readMetaData().outdatedSyncResponseIds
    }
    
    public func markOutdated(syncResponseIds: [String]) {
        var metadata = readMetaData()
        syncResponseIds.forEach { syncResponseId in
            if let index = metadata.syncResponseIds.firstIndex(of: syncResponseId) {
                metadata.syncResponseIds.remove(at: index)
                metadata.outdatedSyncResponseIds.append(syncResponseId)
            }
        }
        saveMetaData(metadata)
    }
    
    
    public var accountData: [String : Any]? {
        get {
            return readMetaData().accountData
        }
        set {
            var metadata = readMetaData()
            metadata.accountData = newValue
            saveMetaData(metadata)
        }
    }
    
    
    public func deleteData() {
        let syncResponseIds = self.allSyncResponseIds
        syncResponseIds.forEach { id in
            deleteSyncResponse(withId: id)
        }
        saveMetaData(nil)
    }
}
