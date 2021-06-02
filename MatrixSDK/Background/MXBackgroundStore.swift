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

//  error domain
let MXBackgroundStoreErrorDomain: String = "MXBackgroundStoreErrorDomain"

//  error codes
enum MXBackgroundStoreErrorCode: Int {
    case userIDMissing = 1001   // User ID is missing in credentials
}

/// Minimalist MXStore implementation. It uses some real values from an MXFileStore instance.
class MXBackgroundStore: NSObject, MXStore {

    //  real store
    private var fileStore: MXFileStore
    
    // Room stores cache
    private var roomsStore: [String: MXFileRoomStore] = [:]
    
    init(withCredentials credentials: MXCredentials) {
        fileStore = MXFileStore(credentials: credentials)
        //  load real eventStreamToken
        fileStore.loadMetaData()
    }
    
    //  Return real eventStreamToken, to be able to launch a meaningful background sync
    var eventStreamToken: String? {
        get {
            return fileStore.eventStreamToken
        } set {
            //  no-op
        }
    }
    
    //  Return real userAccountData, to be able to use push rules
    var userAccountData: [AnyHashable : Any]? {
        get {
            return fileStore.userAccountData
        } set {
            //  no-op
        }
    }
    
    var isPermanent: Bool {
        return false
    }
    
    //  Some mandatory methods to implement to be permanent
    func storeState(forRoom roomId: String, stateEvents: [MXEvent]) {
        //  no-op
    }
    
    //  Fetch real room state
    func state(ofRoom roomId: String, success: @escaping ([MXEvent]) -> Void, failure: ((Error) -> Void)? = nil) {
        fileStore.state(ofRoom: roomId, success: success, failure: failure)
    }
    
    //  Fetch real soom summary
    func summary(ofRoom roomId: String) -> MXRoomSummary? {
        return fileStore.summary(ofRoom: roomId)
    }
    
    //  Fetch real room account data
    func accountData(ofRoom roomId: String) -> MXRoomAccountData? {
        return fileStore.accountData(ofRoom: roomId)
    }
    
    var syncFilterId: String? {
        get {
            return fileStore.syncFilterId
        } set {
            //  no-op
        }
    }
    
    func event(withEventId eventId: String, inRoom roomId: String) -> MXEvent? {
        guard let roomStore = roomStore(forRoom: roomId) else {
            return nil
        }
        
        let event = roomStore.event(withEventId: eventId)
        
        MXLog.debug("[MXBackgroundStore] eventWithEventId: \(eventId) \(event == nil ? "not " : "" )found")
        return event
    }
    
    
    //  MARK: - Private
    private func roomStore(forRoom roomId: String) -> MXFileRoomStore? {
        // Use the cached instance if available
        if let roomStore = roomsStore[roomId] {
            return roomStore
        }
        
        guard let roomStore = fileStore.roomStore(forRoom: roomId) else {
            MXLog.debug("[MXBackgroundStore] roomStore: Unknown room id: \(roomId)")
            return nil
        }
        
        roomsStore[roomId] = roomStore
        return roomStore
    }
    
    
    //  MARK: - Stubs
    
    /// Following operations should be not required
    
    func open(with credentials: MXCredentials, onComplete: (() -> Void)?, failure: ((Error?) -> Void)? = nil) {
    }
    
    func storeEvent(forRoom roomId: String, event: MXEvent, direction: __MXTimelineDirection) {
    }
    
    func replace(_ event: MXEvent, inRoom roomId: String) {
    }
    
    func eventExists(withEventId eventId: String, inRoom roomId: String) -> Bool {
        return false
    }
    
    func deleteAllMessages(inRoom roomId: String) {
    }
    
    func deleteRoom(_ roomId: String) {
    }
    
    func deleteAllData() {
    }
    
    func storePaginationToken(ofRoom roomId: String, andToken token: String) {
    }
    
    func paginationToken(ofRoom roomId: String) -> String? {
        return nil
    }
    
    func storeHasReachedHomeServerPaginationEnd(forRoom roomId: String, andValue value: Bool) {
    }
    
    func hasReachedHomeServerPaginationEnd(forRoom roomId: String) -> Bool {
        return true
    }
    
    func storeHasLoadedAllRoomMembers(forRoom roomId: String, andValue value: Bool) {
    }
    
    func hasLoadedAllRoomMembers(forRoom roomId: String) -> Bool {
        return false
    }
    
    func messagesEnumerator(forRoom roomId: String) -> MXEventsEnumerator {
        return MXEventsEnumeratorOnArray(messages: [])
    }
    
    func messagesEnumerator(forRoom roomId: String, withTypeIn types: [Any]?) -> MXEventsEnumerator {
        return MXEventsEnumeratorOnArray(messages: [])
    }
    
    func relations(forEvent eventId: String, inRoom roomId: String, relationType: String) -> [MXEvent] {
        return []
    }
    
    func store(_ user: MXUser) {
    }
    
    func users() -> [MXUser]? {
        return nil
    }
    
    func user(withUserId userId: String) -> MXUser? {
        return nil
    }
    
    func store(_ group: MXGroup) {
    }
    
    func groups() -> [MXGroup]? {
        return nil
    }
    
    func group(withGroupId groupId: String) -> MXGroup? {
        return nil
    }
    
    func deleteGroup(_ groupId: String) {
    }
    
    func storePartialTextMessage(forRoom roomId: String, partialTextMessage: String) {
    }
    
    func partialTextMessage(ofRoom roomId: String) -> String? {
        return nil
    }
    
    func getEventReceipts(_ roomId: String, eventId: String, sorted sort: Bool) -> [MXReceiptData]? {
        return nil
    }
    
    func storeReceipt(_ receipt: MXReceiptData, inRoom roomId: String) -> Bool {
        return false
    }
    
    func getReceiptInRoom(_ roomId: String, forUserId userId: String) -> MXReceiptData? {
        return nil
    }
    
    func localUnreadEventCount(_ roomId: String, withTypeIn types: [Any]?) -> UInt {
        return 0
    }
    
    var homeserverWellknown: MXWellKnown?
    
    func storeHomeserverWellknown(_ homeserverWellknown: MXWellKnown) {
    }
    
}
