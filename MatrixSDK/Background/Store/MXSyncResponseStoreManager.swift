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
    
    /// Fetch event in the store
    /// - Parameters:
    ///   - eventId: Event identifier to be fetched.
    ///   - roomId: Room identifier to be fetched.
    public func event(withEventId eventId: String, inRoom roomId: String) -> MXEvent? {
        guard let response = syncResponseStore.syncResponse else {
            return nil
        }
        
        var allEvents: [MXEvent] = []
        if let joinedRoomSync = response.syncResponse.rooms.join[roomId] {
            allEvents.appendIfNotNil(contentsOf: joinedRoomSync.state?.events)
            allEvents.appendIfNotNil(contentsOf: joinedRoomSync.timeline?.events)
            allEvents.appendIfNotNil(contentsOf: joinedRoomSync.accountData?.events)
        }
        if let invitedRoomSync = response.syncResponse.rooms.invite[roomId] {
            allEvents.appendIfNotNil(contentsOf: invitedRoomSync.inviteState?.events)
        }
        if let leftRoomSync = response.syncResponse.rooms.leave[roomId] {
            allEvents.appendIfNotNil(contentsOf: leftRoomSync.state?.events)
            allEvents.appendIfNotNil(contentsOf: leftRoomSync.timeline?.events)
            allEvents.appendIfNotNil(contentsOf: leftRoomSync.accountData?.events)
        }
        
        let result = allEvents.first(where: { eventId == $0.eventId })
        result?.roomId = roomId
        
        NSLog("[MXSyncResponseStoreManager] eventWithEventId: \(eventId) \(result == nil ? "not " : "" )found")
        
        return result
    }
    
    /// Fetch room summary for an invited room. Just uses the data in syncResponse to guess the room display name
    /// - Parameter roomId: Room identifier to be fetched
    /// - Parameter summary: A room summary (if exists) which user had before a sync response
    public func roomSummary(forRoomId roomId: String, using summary: MXRoomSummary?) -> MXRoomSummary? {
        guard let response = syncResponseStore.syncResponse else {
            return summary
        }
        guard let summary = summary ?? MXRoomSummary(roomId: roomId, andMatrixSession: nil) else {
            return nil
        }
        
        var eventsToProcess: [MXEvent] = []
        
        if let invitedRoomSync = response.syncResponse.rooms.invite[roomId],
           let stateEvents = invitedRoomSync.inviteState?.events {
            eventsToProcess.append(contentsOf: stateEvents)
        }
        
        if let joinedRoomSync = response.syncResponse.rooms.join[roomId] {
            if let stateEvents = joinedRoomSync.state?.events {
                eventsToProcess.append(contentsOf: stateEvents)
            }
            if let timelineEvents = joinedRoomSync.timeline?.events {
                eventsToProcess.append(contentsOf: timelineEvents)
            }
        }
        
        if let leftRoomSync = response.syncResponse.rooms.leave[roomId] {
            if let stateEvents = leftRoomSync.state?.events {
                eventsToProcess.append(contentsOf: stateEvents)
            }
            if let timelineEvents = leftRoomSync.timeline?.events {
                eventsToProcess.append(contentsOf: timelineEvents)
            }
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
