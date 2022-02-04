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


public enum MXSyncResponseStoreError: Error {
    case unknownId
}


/// Protocol defining the storage for a sync response.
@objc public protocol MXSyncResponseStore: NSObjectProtocol {
    
    /// CRUD interface for cached sync responses
    @discardableResult func addSyncResponse(syncResponse: MXCachedSyncResponse) -> String
    func syncResponse(withId id: String) throws -> MXCachedSyncResponse
    func syncResponseSize(withId id: String) -> Int
    func updateSyncResponse(withId id: String, syncResponse: MXCachedSyncResponse)
    func deleteSyncResponse(withId id: String)
    func deleteSyncResponses(withIds ids: [String])
    
    /// All ids of valid stored sync responses.
    /// Sync responses are stored in chunks to save RAM when processing it
    /// The array order is chronological
    var syncResponseIds: [String] { get }
    
    /// Mark as outdated some stored sync responses
    func markOutdated(syncResponseIds: [String])
    /// All outdated sync responses
    var outdatedSyncResponseIds: [String] { get }
    
    /// User account data
    var accountData: [String : Any]? { get set }
    
    /// Delete all data in the store
    func deleteData()
}

extension MXSyncResponseStore {
    var allSyncResponseIds : [String] {
        outdatedSyncResponseIds + syncResponseIds
    }
}
