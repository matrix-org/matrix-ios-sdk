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
    
    // A store service to record if the file store deletes its data
    var storeService: MXStoreService?

    // Real store
    private var fileStore: MXFileStore
    
    // Room stores cache
    private var roomsStore: [String: MXFileRoomStore] = [:]
    
    init(withCredentials credentials: MXCredentials) {
        fileStore = MXFileStore(credentials: credentials)
        storeService = MXStoreService(store: fileStore, credentials: credentials)
        //  load real eventStreamToken without enabling clear data
        fileStore.loadMetaData(false)
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
    
    func storeEvent(forRoom roomId: String, event: MXEvent, direction: MXTimelineDirection) {
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
        return MXEventsEnumeratorOnArray(eventIds: [], dataSource: nil)
    }
    
    func messagesEnumerator(forRoom roomId: String, withTypeIn types: [Any]?) -> MXEventsEnumerator {
        return MXEventsEnumeratorOnArray(eventIds: [], dataSource: nil)
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

    func storePartialAttributedTextMessage(forRoom roomId: String, partialAttributedTextMessage: NSAttributedString) {
    }

    func partialAttributedTextMessage(ofRoom roomId: String) -> NSAttributedString? {
        return nil
    }
    
    func getEventReceipts(_ roomId: String, eventId: String, threadId: String, sorted sort: Bool, completion: @escaping ([MXReceiptData]) -> Void) {
        DispatchQueue.main.async {
            completion([])
        }
    }
    
    func storeReceipt(_ receipt: MXReceiptData, inRoom roomId: String) -> Bool {
        return false
    }
    
    func getReceiptInRoom(_ roomId: String, threadId: String, forUserId userId: String) -> MXReceiptData? {
        return nil
    }
    
    func getReceiptsInRoom(_ roomId: String, forUserId userId: String) -> [String: MXReceiptData] {
        return [:]
    }
    
    func loadReceipts(forRoom roomId: String, completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            completion?()
        }
    }
    
    func localUnreadEventCount(_ roomId: String, threadId: String?, withTypeIn types: [Any]?) -> UInt {
        return 0
    }
    
    func localUnreadEventCountPerThread(_ roomId: String, withTypeIn types: [Any]?) -> [String : NSNumber]! {
        return [:]
    }

    func newIncomingEvents(inRoom roomId: String, threadId: String?, withTypeIn types: [String]?) -> [MXEvent] {
        return []
    }
    
    var homeserverWellknown: MXWellKnown?
    
    func storeHomeserverWellknown(_ homeserverWellknown: MXWellKnown) {
    }

    var homeserverCapabilities: MXCapabilities?
    func storeHomeserverCapabilities(_ homeserverCapabilities: MXCapabilities) {
    }

    var supportedMatrixVersions: MXMatrixVersions?
    func storeSupportedMatrixVersions(_ supportedMatrixVersions: MXMatrixVersions) {
    }
    
    func loadRoomMessages(forRoom roomId: String, completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            completion?()
        }
    }
    
    func storeOutgoingMessage(forRoom roomId: String, outgoingMessage: MXEvent) {
        
    }
    
    func removeAllOutgoingMessages(fromRoom roomId: String) {
        
    }
    
    func removeOutgoingMessage(fromRoom roomId: String, outgoingMessage outgoingMessageEventId: String) {
        
    }
    
    func outgoingMessages(inRoom roomId: String) -> [MXEvent]? {
        return []
    }
    
    var roomSummaryStore: MXRoomSummaryStore {
        return self
    }

    var roomIds: [String] {
        return []
    }
    
    func setUnreadForRoom(_ roomId: String) {
        //  no-op
    }
    
    func resetUnread(forRoom roomId: String) {
        //  no-op
    }
    
    func isRoomMarked(asUnread roomId: String) -> Bool {
        return false
    }
    
    func removeAllMessagesSent(before limitTs: UInt64, inRoom roomId: String) -> Bool {
        // Not sure if this needs to be implemented
        false
    }
}

//  MARK: - MXRoomSummaryStore

extension MXBackgroundStore: MXRoomSummaryStore {
    
    var rooms: [String] {
        return []
    }
    
    var countOfRooms: UInt {
        return 0
    }
    
    func storeSummary(_ summary: MXRoomSummaryProtocol) {
        
    }
    
    //  Fetch real soom summary
    func summary(ofRoom roomId: String) -> MXRoomSummaryProtocol? {
        return fileStore.roomSummaryStore.summary(ofRoom: roomId)
    }
    
    func removeSummary(ofRoom roomId: String) {
        
    }
    
    func removeAllSummaries() {
        
    }
    
    func fetchAllSummaries(_ completion: @escaping ([MXRoomSummaryProtocol]) -> Void) {
        DispatchQueue.main.async {
            completion([])
        }
    }
}
