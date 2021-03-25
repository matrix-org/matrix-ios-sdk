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

/// Sync response storage in a file implementation.
@objcMembers
public class MXSyncResponseStoreManager: NSObject {
    let syncResponseStore: MXSyncResponseStore
    
    public init(syncResponseStore: MXSyncResponseStore) {
        self.syncResponseStore = syncResponseStore
    }
    
    /// Cache a sync response.
    /// - Parameters:
    ///   - newSyncResponse: the sync response to store
    ///   - syncToken: the sync token that generated this sync response.
    func updateStore(with newSyncResponse: MXSyncResponse, syncToken: String) {
        if let cachedSyncResponse = syncResponseStore.syncResponse {
            //  current sync response exists, merge it with the new response
            
            //  handle new limited timelines
            newSyncResponse.rooms.join.filter({ $1.timeline?.limited == true }).forEach { (roomId, _) in
                if let joinedRoomSync = cachedSyncResponse.syncResponse.rooms.join[roomId] {
                    //  remove old events
                    joinedRoomSync.timeline?.events = []
                    //  mark old timeline as limited too
                    joinedRoomSync.timeline?.limited = true
                }
            }
            newSyncResponse.rooms.leave.filter({ $1.timeline?.limited == true }).forEach { (roomId, _) in
                if let leftRoomSync = cachedSyncResponse.syncResponse.rooms.leave[roomId] {
                    //  remove old events
                    leftRoomSync.timeline?.events = []
                    //  mark old timeline as limited too
                    leftRoomSync.timeline?.limited = true
                }
            }
            
            //  handle old limited timelines
            cachedSyncResponse.syncResponse.rooms.join.filter({ $1.timeline?.limited == true }).forEach { (roomId, _) in
                if let joinedRoomSync = newSyncResponse.rooms.join[roomId] {
                    //  mark new timeline as limited too, to avoid losing value of limited
                    joinedRoomSync.timeline?.limited = true
                }
            }
            cachedSyncResponse.syncResponse.rooms.leave.filter({ $1.timeline?.limited == true }).forEach { (roomId, _) in
                if let leftRoomSync = newSyncResponse.rooms.leave[roomId] {
                    //  mark new timeline as limited too, to avoid losing value of limited
                    leftRoomSync.timeline?.limited = true
                }
            }
            
            // Merge the new sync response to the old one
            var dictionary = NSDictionary(dictionary: cachedSyncResponse.jsonDictionary())
            dictionary = dictionary + NSDictionary(dictionary: newSyncResponse.jsonDictionary())
            
            // And update it to the store.
            // Note we we care only about the cached sync token. syncToken is now useless
            syncResponseStore.syncResponse = MXCachedSyncResponse(syncToken: cachedSyncResponse.syncToken,
                                                                  syncResponse: MXSyncResponse(fromJSON: dictionary as? [AnyHashable : Any]))
        } else {
            //  no current sync response, directly save the new one
            syncResponseStore.syncResponse = MXCachedSyncResponse(syncToken: syncToken,
                                                                  syncResponse: newSyncResponse)
        }
        
        // Manage user account data
        if let accountData = newSyncResponse.accountData {
            syncResponseStore.accountData = accountData
        }
    }
}
