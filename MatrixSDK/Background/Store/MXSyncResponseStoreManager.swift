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
    
    /// Maximum data size for each sync response cached in MXSyncResponseStore.
    /// Under this value, sync reponses are merged. This limit allows to work on several smaller sync responses to limit RAM usage.
    /// Default is 512kB.
    var syncResponseCacheSizeLimit: Int = 512 * 1024
    
    /// The actual store
    let syncResponseStore: MXSyncResponseStore
    
    public init(syncResponseStore: MXSyncResponseStore) {
        self.syncResponseStore = syncResponseStore
    }
    
    /// The sync token that is the origin of the stored sync response.
    /// - Returns: the original sync token.
    public func syncToken() -> String? {
        self.firstSyncResponse()?.syncToken
    }
    
    /// The sync token to use for the next /sync requests
    /// - Returns: the next sync token
    public func nextSyncToken() -> String? {
        self.lastSyncResponse()?.syncResponse.nextBatch
    }
    
    public func firstSyncResponse() ->  MXCachedSyncResponse? {
        guard let id = syncResponseStore.syncResponseIds.first else {
            return nil
        }
        guard let syncResponse = try? syncResponseStore.syncResponse(withId: id) else {
            MXLog.debug("[MXSyncResponseStoreManager] firstSyncResponse: invalid id")
            return nil
        }
        return syncResponse
    }
    
    public func lastSyncResponse() -> MXCachedSyncResponse? {
        guard let id = syncResponseStore.syncResponseIds.last else {
            return nil
        }
        guard let syncResponse = try? syncResponseStore.syncResponse(withId: id) else {
            MXLog.debug("[MXSyncResponseStoreManager] lastSyncResponse: invalid id")
            return nil
        }
        return syncResponse
    }
    
    public func markDataOutdated() {
        let syncResponseIds = syncResponseStore.syncResponseIds
        if syncResponseIds.count == 0 {
            return
        }
        
        MXLog.debug("[MXSyncResponseStoreManager] markDataOutdated \(syncResponseIds.count) cached sync responses. The sync token was \(String(describing: syncToken()))")
        syncResponseStore.markOutdated(syncResponseIds: syncResponseIds)
    }
    

    /// Cache a sync response.
    /// - Parameters:
    ///   - newSyncResponse: the sync response to store
    ///   - syncToken: the sync token that generated this sync response.
    public func updateStore(with newSyncResponse: MXSyncResponse, syncToken: String) {
        if let id = syncResponseStore.syncResponseIds.last {
            
            // Check if we can merge the new sync response to the last one
            // Store it as a new chunk if the previous chunk is too big
            let cachedSyncResponseSize = syncResponseStore.syncResponseSize(withId: id)
            if  cachedSyncResponseSize < syncResponseCacheSizeLimit,
                let cachedSyncResponse = try? syncResponseStore.syncResponse(withId: id) {
                
                MXLog.debug("[MXSyncResponseStoreManager] updateStore: Merge new sync response to the previous one")
                
                //  handle new limited timelines
                newSyncResponse.rooms?.join?.filter({ $1.timeline.limited == true }).forEach { (roomId, _) in
                    if let joinedRoomSync = cachedSyncResponse.syncResponse.rooms?.join?[roomId] {
                        //  remove old events
                        joinedRoomSync.timeline.events = []
                        //  mark old timeline as limited too
                        joinedRoomSync.timeline.limited = true
                    }
                }
                newSyncResponse.rooms?.leave?.filter({ $1.timeline.limited == true }).forEach { (roomId, _) in
                    if let leftRoomSync = cachedSyncResponse.syncResponse.rooms?.leave?[roomId] {
                        //  remove old events
                        leftRoomSync.timeline.events = []
                        //  mark old timeline as limited too
                        leftRoomSync.timeline.limited = true
                    }
                }
                
                //  handle old limited timelines
                cachedSyncResponse.syncResponse.rooms?.join?.filter({ $1.timeline.limited == true }).forEach { (roomId, _) in
                    if let joinedRoomSync = newSyncResponse.rooms?.join?[roomId] {
                        //  mark new timeline as limited too, to avoid losing value of limited
                        joinedRoomSync.timeline.limited = true
                    }
                }
                cachedSyncResponse.syncResponse.rooms?.leave?.filter({ $1.timeline.limited == true }).forEach { (roomId, _) in
                    if let leftRoomSync = newSyncResponse.rooms?.leave?[roomId] {
                        //  mark new timeline as limited too, to avoid losing value of limited
                        leftRoomSync.timeline.limited = true
                    }
                }
                
                // Merge the new sync response to the old one
                var dictionary = NSDictionary(dictionary: cachedSyncResponse.syncResponse.jsonDictionary())
                dictionary = dictionary + NSDictionary(dictionary: newSyncResponse.jsonDictionary())
                
                // And update it to the store.
                // Note we we care only about the cached sync token. syncToken is now useless
                let updatedCachedSyncResponse = MXCachedSyncResponse(syncToken: cachedSyncResponse.syncToken,
                                                                     syncResponse: MXSyncResponse(fromJSON: dictionary as? [AnyHashable : Any]))
                syncResponseStore.updateSyncResponse(withId: id, syncResponse: updatedCachedSyncResponse)
                
                
            } else {
                // Use a new chunk
                MXLog.debug("[MXSyncResponseStoreManager] updateStore: Create a new chunk to store the new sync response. Previous chunk size: \(cachedSyncResponseSize)")
                let cachedSyncResponse = MXCachedSyncResponse(syncToken: syncToken,
                                                              syncResponse: newSyncResponse)
                _ = syncResponseStore.addSyncResponse(syncResponse: cachedSyncResponse)
            }
        } else {
            //  no current sync response, directly save the new one
            MXLog.debug("[MXSyncResponseStoreManager] updateStore: Start storing sync response")
            let cachedSyncResponse = MXCachedSyncResponse(syncToken: syncToken,
                                                         syncResponse: newSyncResponse)
            _ = syncResponseStore.addSyncResponse(syncResponse: cachedSyncResponse)
        }
        
        // Manage user account data
        if let newAccountData = newSyncResponse.accountData,
           let newAccountDataEvents = newAccountData["events"] as? [[String: Any]], newAccountDataEvents.count > 0 {
            let cachedAccountData = syncResponseStore.accountData ?? [:]
            guard let accountData = MXAccountData(accountData: cachedAccountData) else {
                return
            }
            
            newAccountDataEvents.forEach {
                accountData.update(withEvent: $0)
            }
            
            syncResponseStore.accountData = accountData.accountData
        }
    }

    /// Fetch event in the store
    /// - Parameters:
    ///   - eventId: Event identifier to be fetched.
    ///   - roomId: Room identifier to be fetched.
    public func event(withEventId eventId: String, inRoom roomId: String) -> MXEvent? {
        for id in  syncResponseStore.syncResponseIds.reversed() {
            let event = autoreleasepool { () -> MXEvent? in
                guard let response = try? syncResponseStore.syncResponse(withId: id) else {
                    return nil
                }
                
                return self.event(withEventId: eventId, inRoom: roomId, inSyncResponse: response)
            }
            
            if let event = event {
                return event
            }
        }
        
        MXLog.debug("[MXSyncResponseStoreManager] event: Not found event \(eventId) in room \(roomId)")
        return nil
    }
    
    private func event(withEventId eventId: String, inRoom roomId: String, inSyncResponse response: MXCachedSyncResponse) -> MXEvent? {
        var allEvents: [MXEvent] = []
        if let joinedRoomSync = response.syncResponse.rooms?.join?[roomId] {
            allEvents.appendIfNotNil(contentsOf: joinedRoomSync.state.events)
            allEvents.appendIfNotNil(contentsOf: joinedRoomSync.timeline.events)
            allEvents.appendIfNotNil(contentsOf: joinedRoomSync.accountData.events)
        }
        if let invitedRoomSync = response.syncResponse.rooms?.invite?[roomId] {
            allEvents.appendIfNotNil(contentsOf: invitedRoomSync.inviteState.events)
        }
        if let leftRoomSync = response.syncResponse.rooms?.leave?[roomId] {
            allEvents.appendIfNotNil(contentsOf: leftRoomSync.state.events)
            allEvents.appendIfNotNil(contentsOf: leftRoomSync.timeline.events)
            allEvents.appendIfNotNil(contentsOf: leftRoomSync.accountData.events)
        }
        
        let result = allEvents.first(where: { eventId == $0.eventId })
        result?.roomId = roomId
        
        MXLog.debug("[MXSyncResponseStoreManager] eventWithEventId: \(eventId) \(result == nil ? "not " : "" )found")
        
        return result
    }

    /// Fetch room summary for an invited room. Just uses the data in syncResponse to guess the room display name
    /// - Parameter roomId: Room identifier to be fetched
    /// - Parameter summary: A room summary (if exists) which user had before a sync response
    public func roomSummary(forRoomId roomId: String, using summary: MXRoomSummary?) -> MXRoomSummary? {
        guard let summary = summary ?? MXRoomSummary(roomId: roomId, andMatrixSession: nil) else {
            return nil
        }
        
        for id in syncResponseStore.syncResponseIds.reversed() {
            let summary = autoreleasepool { () -> MXRoomSummary? in
                guard let response = try? syncResponseStore.syncResponse(withId: id) else {
                    return nil
                }
                
                return roomSummary(forRoomId: roomId, using: summary, inSyncResponse: response)
            }
            
            if let summary = summary {
                return summary
            }
        }
        
        MXLog.debug("[MXSyncResponseStoreManager] roomSummary: Not found for room \(roomId)")
        
        return nil
    }
    
    private func roomSummary(forRoomId roomId: String, using summary: MXRoomSummary, inSyncResponse response: MXCachedSyncResponse) -> MXRoomSummary? {
        var eventsToProcess: [MXEvent] = []
        
        if let invitedRoomSync = response.syncResponse.rooms?.invite?[roomId] {
            eventsToProcess.append(contentsOf: invitedRoomSync.inviteState.events)
        }
        
        if let joinedRoomSync = response.syncResponse.rooms?.join?[roomId] {
            eventsToProcess.append(contentsOf: joinedRoomSync.state.events)
            eventsToProcess.append(contentsOf: joinedRoomSync.timeline.events)
        }
        
        if let leftRoomSync = response.syncResponse.rooms?.leave?[roomId] {
            eventsToProcess.append(contentsOf: leftRoomSync.state.events)
            eventsToProcess.append(contentsOf: leftRoomSync.timeline.events)
        }
        
        for event in eventsToProcess {
            switch event.eventType {
                case .roomAliases:
                    if summary.displayname == nil {
                        summary.displayname = (event.content["aliases"] as? [String])?.first
                    }
                case .roomCanonicalAlias:
                    if summary.displayname == nil {
                        summary.displayname = event.content["alias"] as? String
                        if summary.displayname == nil {
                            summary.displayname = (event.content["alt_aliases"] as? [String])?.first
                        }
                    }
                case .roomName:
                    summary.displayname = event.content["name"] as? String
                default:
                    break
            }
        }
        return summary
    }
}


//  MARK: - Private

private extension Array {
    
    mutating func appendIfNotNil(contentsOf array: Array?) {
        if let array = array {
            append(contentsOf: array)
        }
    }
    
}
