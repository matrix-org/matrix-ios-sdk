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

/// `MXSpaceFileStore` is used to store the spaces related data into a file
class MXSpaceFileStore: MXSpaceStore {
    
    // MARK: - Constants
    
    private enum Constants {
        static let fileStoreFolder = "MXSpaceStore"
        static let fileStoreGraphFile = "graph"
        static let backupFileExtension = "backup"
    }
    
    // MARK: - Properties

    private let userId: String
    private let deviceId: String
    private var storeUrl: URL?

    // MARK - Setup
    
    init(userId: String, deviceId: String) {
        self.userId = userId
        self.deviceId = deviceId
        self.setUpStoragePaths()
    }
    
    /// Stores the given graph
    /// - Parameters:
    ///   - spaceGraphData: space graph to be stored
    /// - Returns: `true` if the data has been stored properly.`false` otherwise
    func store(spaceGraphData: MXSpaceGraphData) -> Bool {
        guard let storeUrl = self.storeUrl else {
            MXLog.error("[MXSpaceFileStore] store: storeSpaceGraphData failed: storeUrl not defined")
            return false
        }
        
        let fileUrl = storeUrl.appendingPathComponent(Constants.fileStoreGraphFile)
        let backupUrl = fileUrl.appendingPathExtension(Constants.backupFileExtension)
        
        if FileManager.default.fileExists(atPath: fileUrl.path) {
            do {
                if FileManager.default.fileExists(atPath: backupUrl.path) {
                    try FileManager.default.removeItem(at: backupUrl)
                }
                try FileManager.default.moveItem(at: fileUrl, to: backupUrl)
            } catch {
                MXLog.error("[MXSpaceFileStore] store: storeSpaceGraphData failed to move graph to backup", context: error)
            }
        }
        
        return NSKeyedArchiver.archiveRootObject(spaceGraphData, toFile: fileUrl.path)
    }
    
    /// Loads graph data from store
    /// - Returns:an instance of `MXSpaceGraphData` if the data has been restored succesfully. `nil` otherwise
    func loadSpaceGraphData() -> MXSpaceGraphData? {
        guard let storeUrl = self.storeUrl else {
            MXLog.error("[MXSpaceStore] loadSpaceGraphData: failed: storeUrl not defined")
            return nil
        }
        
        let fileUrl = storeUrl.appendingPathComponent(Constants.fileStoreGraphFile)
        
        guard let graph = NSKeyedUnarchiver.unarchiveObject(withFile: fileUrl.path) as? MXSpaceGraphData else {
            MXLog.warning("[MXSpaceStore] loadSpaceGraphData: found no archived graph")
            return nil
        }
        
        return graph
    }

    // MARK - Private
    
    private func setUpStoragePaths() {
        var _cacheUrl: URL?
        
        if let container = FileManager.default.applicationGroupContainerURL() {
            _cacheUrl = container
        } else {
            let cacheDirList = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)
            _cacheUrl = URL(fileURLWithPath: cacheDirList[0])
        }
        
        guard let cacheUrl = _cacheUrl else {
            MXLog.error("[MXSpaceStore] setUpStoragePaths was unable to define cache URL")
            return
        }
        
        let storeUrl = cacheUrl.appendingPathComponent(Constants.fileStoreFolder).appendingPathComponent(self.userId).appendingPathComponent(self.deviceId)
        
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: storeUrl.path, isDirectory: &isDirectory) {
            do {
                try FileManager.default.createDirectoryExcludedFromBackup(at: storeUrl)
                self.storeUrl = storeUrl
            } catch {
                MXLog.error("[MXSpaceStore] setUpStoragePaths was unable to create space storage folder", context: error)
            }
        } else {
            self.storeUrl = storeUrl
        }
    }

}
