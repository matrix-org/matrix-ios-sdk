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

/// Errors can be raised by `MXBackgroundSyncService`.
public enum MXBackgroundSyncServiceError: Error {
    case unknown
    case unknownAlgorithm
    case decryptionFailure
}

/// This class can be used to sync in background, keeping the user offline. It does not initiate MXSession or MXCrypto instances.
/// Sync results are written to a MXSyncResponseFileStore.
@objcMembers public class MXBackgroundSyncService: NSObject {
    
    private enum Queues {
        static let dispatchQueue: DispatchQueue = .main
    }
    
    private enum Constants {
        static let syncRequestServerTimout: UInt = 0
        static let syncRequestClientTimout: UInt = 20 * 1000
        static let syncRequestPresence: String = "offline"
    }
    
    private let processingQueue: DispatchQueue
    public let credentials: MXCredentials
    private let syncResponseStoreManager: MXSyncResponseStoreManager
    private let crypto: MXBackgroundCrypto
    private var store: MXStore
    private let restClient: MXRestClient
    private var pushRulesManager: MXBackgroundPushRulesManager
    
    // Mechanism to process one call of event() at a time
    private let asyncTaskQueue: MXAsyncTaskQueue
    
    /// Cached events. Keys are even identifiers.
    private var cachedEvents: [String: MXEvent] = [:]
    
    /// Cached profiles. UserId -> (displayName, avatarUrl)
    private var cachedProfiles: [String: (String?, String?)] = [:]
    
    /// See MXSyncResponseStoreManager.syncResponseCacheSizeLimit
    public var syncResponseCacheSizeLimit: Int {
        get {
            syncResponseStoreManager.syncResponseCacheSizeLimit
        } set {
            syncResponseStoreManager.syncResponseCacheSizeLimit = newValue
        }
    }
    
    /// Initializer
    /// - Parameter credentials: account credentials
    public init(
        withCredentials credentials: MXCredentials,
        persistTokenDataHandler: MXRestClientPersistTokenDataHandler? = nil,
        unauthenticatedHandler: MXRestClientUnauthenticatedHandler? = nil
    ) {
        processingQueue = DispatchQueue(label: "MXBackgroundSyncServiceQueue-" + MXTools.generateSecret())
        self.credentials = credentials
        
        asyncTaskQueue = MXAsyncTaskQueue(dispatchQueue: processingQueue,
                                          label: "MXBackgroundSyncServiceQueueEventSerialQueue-" + MXTools.generateSecret())
        
        let syncResponseStore = MXSyncResponseFileStore(withCredentials: credentials)
        syncResponseStoreManager = MXSyncResponseStoreManager(syncResponseStore: syncResponseStore)
        
        let restClient = MXRestClient(
            credentials: credentials,
            unrecognizedCertificateHandler: nil,
            persistentTokenDataHandler: persistTokenDataHandler,
            unauthenticatedHandler: unauthenticatedHandler
        )
        restClient.completionQueue = processingQueue
        self.restClient = restClient
        
        store = MXBackgroundStore(withCredentials: credentials)
        
        MXLog.debug("[MXBackgroundSyncService] init: constructing crypto")
        crypto = MXBackgroundCryptoV2(credentials: credentials, restClient: restClient)
        
        pushRulesManager = MXBackgroundPushRulesManager(withCredentials: credentials)
        MXLog.debug("[MXBackgroundSyncService] init complete")
        super.init()
        syncPushRuleManagerWithAccountData()
    }
    
    /// Fetch event with given event and room identifiers. It performs a sync if the event not found in session store.
    /// - Parameters:
    ///   - eventId: The event identifier for the desired event
    ///   - roomId: The room identifier for the desired event
    ///   - allowSync:Whether to check local stores on every request so that we use up-to-data data from the MXSession store
    ///   - completion: Completion block to be called. Always called in main thread.
    public func event(withEventId eventId: String,
                      inRoom roomId: String,
                      allowSync: Bool = true,
                      completion: @escaping (MXResponse<MXEvent>) -> Void) {
        // Process one request at a time
        let stopwatch = MXStopwatch()
        asyncTaskQueue.async { (taskCompleted) in
            MXLog.debug("[MXBackgroundSyncService] event: Start processing \(eventId) after waiting for \(stopwatch.readable())")
            
            self._event(withEventId: eventId, inRoom: roomId, allowSync: allowSync) { response in
                completion(response)
                taskCompleted()
            }
        }
    }
    
    /// Fetch room state for given roomId.
    /// - Parameters:
    ///   - roomId: The room identifier for the desired room.
    ///   - completion: Completion block to be called. Always called in main thread.
    public func roomState(forRoomId roomId: String,
                          completion: @escaping (MXResponse<MXRoomState>) -> Void) {
        MXRoomState.load(from: store,
                         withRoomId: roomId,
                         matrixSession: nil) { (roomState) in
                            guard let roomState = roomState else {
                                Queues.dispatchQueue.async {
                                    completion(.failure(MXBackgroundSyncServiceError.unknown))
                                }
                                return
                            }
                            Queues.dispatchQueue.async {
                                completion(.success(roomState))
                            }
        }
    }
    
    /// Get the profile of a room member.
    ///
    /// This method must be called when the member is not visible in the room state. It happens in case of
    /// lazy loading of room members, not all members are known yet.
    ///
    /// - Parameters:
    ///   - userId: The user id.
    ///   - roomId: The room id.
    ///   - completion: Completion block to be called. Always called in main thread.
    public func profile(ofMember userId: String, inRoom roomId: String, completion: @escaping (MXResponse<(String?, String?)>) -> Void) {
        
        // There is no CS API to get a single member in a room. /members will be expensive in a room with thousands of users.
        // So, use the simplest possible HS API to get the data, the profile API.
        // It will not take into account customised name into the room but that will be better than a Matrix id.
        
        // Check cache first
        if let (displayName, avatarUrl) = cachedProfiles[userId] {
            Queues.dispatchQueue.async {
                completion(.success((displayName, avatarUrl)))
            }
            return
        }
        
        // Else make a request
        restClient.profile(forUser: userId) { (response) in
            Queues.dispatchQueue.async {
                if let (displayName, avatarUrl) = response.value {
                    self.cachedProfiles[userId] = (displayName, avatarUrl)
                }
                completion(response)
            }
        }
    }
    
    /// Check whether the given room is mentions only.
    /// - Parameter roomId: The room identifier to be checked
    /// - Returns: If the room is mentions only.
    public func isRoomMentionsOnly(_ roomId: String) -> Bool {
        return pushRulesManager.isRoomMentionsOnly(roomId)
    }
    
    /// Fetch the summary for the given room identifier.
    /// - Parameter roomId: The room identifier to fetch.
    /// - Returns: Summary of room.
    public func roomSummary(forRoomId roomId: String) -> MXRoomSummaryProtocol? {
        let summary = store.roomSummaryStore.summary(ofRoom: roomId)
        return syncResponseStoreManager.roomSummary(forRoomId: roomId, using: summary)
    }
    
    /// Fetch push rule matching an event.
    /// - Parameters:
    ///   - event: The event to be matched.
    ///   - roomState: Room state.
    /// - Returns: Push rule matching the event.
    public func pushRule(matching event: MXEvent, roomState: MXRoomState) -> MXPushRule? {
        guard let currentUserId = credentials.userId else { return nil }
        return pushRulesManager.pushRule(matching: event,
                                         roomState: roomState,
                                         currentUserDisplayName:  roomState.members.member(withUserId: currentUserId)?.displayname)
    }
    
    /// Fetch room account data for given roomId.
    /// - Parameters:
    ///   - roomId: The room identifier for the desired room.
    ///   - completion: Completion block to be called. Always called in main thread.
    public func roomAccountData(forRoomId roomId: String,
                                completion: @escaping (MXResponse<MXRoomAccountData>) -> Void) {
        processingQueue.async {
            guard let accountData = self.store.accountData?(ofRoom: roomId) else {
                Queues.dispatchQueue.async {
                    completion(.failure(MXBackgroundSyncServiceError.unknown))
                }
                return
            }
            
            Queues.dispatchQueue.async {
                completion(.success(accountData))
            }
        }
    }
    
    public func readMarkerEvent(forRoomId roomId: String, completion: @escaping (MXResponse<MXEvent>) -> Void) {
        roomAccountData(forRoomId: roomId) { [weak self] response in
            guard let self = self else { return }
            
            switch response {
            case .failure(let error):
                completion(.failure(error))
                return
            case .success(let roomAccountData):
                self._event(withEventId: roomAccountData.readMarkerEventId, inRoom: roomId, allowSync: false, completion: completion)
            }
        }
    }
    
    //  MARK: - Private
    
    private func _event(withEventId eventId: String,
                        inRoom roomId: String,
                        allowSync: Bool,
                        completion: @escaping (MXResponse<MXEvent>) -> Void) {
        MXLog.debug("[MXBackgroundSyncService] fetchEvent: \(eventId). allowSync: \(allowSync)")
        
        // Check local stores on every request so that we use up-to-data data from the MXSession store
        if allowSync {
            updateBackgroundServiceStoresIfNeeded()
        }
        
        /// Inline function to handle decryption failure
        func handleDecryptionFailure(withError error: Error?) {
            if allowSync {
                MXLog.debug("[MXBackgroundSyncService] fetchEvent: Launch a background sync.")
                self.launchBackgroundSync(forEventId: eventId, roomId: roomId, completion: completion)
            } else {
                MXLog.debug("[MXBackgroundSyncService] fetchEvent: Do not sync anymore.")
                Queues.dispatchQueue.async {
                    completion(.failure(error ?? MXBackgroundSyncServiceError.decryptionFailure))
                }
            }
        }

        /// Inline function to handle encryption for event, either from cache or from the backend
        /// - Parameter event: The event to be handled
        func handleEncryption(forEvent event: MXEvent) {
            if !event.isEncrypted {
                //  not encrypted, go on processing
                MXLog.debug("[MXBackgroundSyncService] fetchEvent: Event not encrypted.")
                Queues.dispatchQueue.async {
                    completion(.success(event))
                }
                return
            }
            
            //  encrypted
            if event.clear != nil {
                //  already decrypted
                MXLog.debug("[MXBackgroundSyncService] fetchEvent: Event already decrypted.")
                Queues.dispatchQueue.async {
                    completion(.success(event))
                }
                return
            }
            
            //  should decrypt it first
            if crypto.canDecryptEvent(event) {
                //  we have keys to decrypt the event
                MXLog.debug("[MXBackgroundSyncService] fetchEvent: Event needs to be decrpyted, and we have the keys to decrypt it.")
                
                do {
                    try crypto.decryptEvent(event)
                    Queues.dispatchQueue.async {
                        completion(.success(event))
                    }
                } catch let error {
                    MXLog.debug("[MXBackgroundSyncService] fetchEvent: Decryption failed even crypto claimed it has the keys.")
                    handleDecryptionFailure(withError: error)
                }
            } else {
                //  we don't have keys to decrypt the event
                MXLog.debug("[MXBackgroundSyncService] fetchEvent: Event needs to be decrypted, but we don't have the keys to decrypt it.")
                handleDecryptionFailure(withError: nil)
            }
        }
        
        //  check if we've fetched the event before
        if let cachedEvent = self.cachedEvents[eventId] {
            //  use cached event
            handleEncryption(forEvent: cachedEvent)
        } else {
            //  do not call the /event api and just check if the event exists in the store
            let event = syncResponseStoreManager.event(withEventId: eventId, inRoom: roomId)
                // Disable read access to MXSession store because it consumes too much RAM
                // and RAM is limited when running an app extension
                // TODO: Find a way to reuse MXSession store data
                //?? store.event(withEventId: eventId, inRoom: roomId)
            
            if let event = event {
                MXLog.debug("[MXBackgroundSyncService] fetchEvent: We have the event in stores.")
                //  cache this event
                self.cachedEvents[eventId] = event
                
                //  handle encryption for this event
                handleEncryption(forEvent: event)
            } else if allowSync {
                MXLog.debug("[MXBackgroundSyncService] fetchEvent: We don't have the event in stores. Launch a background sync to fetch it.")
                self.launchBackgroundSync(forEventId: eventId, roomId: roomId, completion: completion)
            } else {
                // Final fallback, try with /event API
                MXLog.debug("[MXBackgroundSyncService] fetchEvent: We still don't have the event in stores. Try with /event API")
                
                restClient.event(withEventId: eventId, inRoom: roomId) { [weak self] (response) in
                    
                    guard let self = self else {
                        MXLog.debug("[NotificationService] fetchEvent: /event API returned too late successfully.")
                        return
                    }
                    
                    switch response {
                        case .success(let event):
                            MXLog.debug("[MXBackgroundSyncService] fetchEvent: We got the event from /event API")
                            
                            //  cache this event
                            self.cachedEvents[eventId] = event
                            
                            //  handle encryption for this event
                            handleEncryption(forEvent: event)
                            
                        case .failure(let error):
                            MXLog.debug("[MXBackgroundSyncService] fetchEvent: Failed to fetch event \(eventId)")
                            Queues.dispatchQueue.async {
                                completion(.failure(error))
                            }
                    }
                }
            }
        }
    }
    
    private func launchBackgroundSync(forEventId eventId: String,
                                      roomId: String,
                                      completion: @escaping (MXResponse<MXEvent>) -> Void) {
            
        guard let eventStreamToken = syncResponseStoreManager.nextSyncToken() ?? store.eventStreamToken else {
            MXLog.debug("[MXBackgroundSyncService] launchBackgroundSync: Do not sync because event streaming not started yet.")
            Queues.dispatchQueue.async {
                completion(.failure(MXBackgroundSyncServiceError.unknown))
            }
            return
        }
        
        MXLog.debug("[MXBackgroundSyncService] launchBackgroundSync: start from token \(eventStreamToken)")
        
        restClient.sync(fromToken: eventStreamToken,
                        serverTimeout: Constants.syncRequestServerTimout,
                        clientTimeout: Constants.syncRequestClientTimout,
                        setPresence: Constants.syncRequestPresence,
                        filterId: store.syncFilterId ?? nil) { [weak self] (response) in
            switch response {
            case .success(let syncResponse):
                guard let self = self else {
                    MXLog.debug("[MXBackgroundSyncService] launchBackgroundSync: MXRestClient.syncFromToken returned too late successfully")
                    Queues.dispatchQueue.async {
                        completion(.failure(MXBackgroundSyncServiceError.unknown))
                    }
                    return
                }

                Task {
                    await self.handleSyncResponse(syncResponse, syncToken: eventStreamToken)
                    
                    if let event = self.syncResponseStoreManager.event(withEventId: eventId, inRoom: roomId),
                       !self.crypto.canDecryptEvent(event),
                       (syncResponse.toDevice?.events ?? []).count > 0 {
                        //  we got the event but not the keys to decrypt it. continue to sync
                        self.launchBackgroundSync(forEventId: eventId, roomId: roomId, completion: completion)
                    } else {
                        //  do not allow to sync anymore
                        self._event(withEventId: eventId, inRoom: roomId, allowSync: false, completion: completion)
                    }
                }
            case .failure(let error):
                guard let _ = self else {
                    MXLog.debug("[MXBackgroundSyncService] launchBackgroundSync: MXRestClient.syncFromToken returned too late with error: \(String(describing: error))")
                    Queues.dispatchQueue.async {
                        completion(.failure(error))
                    }
                    return
                }
                MXLog.debug("[MXBackgroundSyncService] launchBackgroundSync: MXRestClient.syncFromToken returned with error: \(String(describing: error))")
                Queues.dispatchQueue.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func handleSyncResponse(_ syncResponse: MXSyncResponse, syncToken: String) async {
        MXLog.debug("""
            [MXBackgroundSyncService] handleSyncResponse: \
            Received \(syncResponse.rooms?.join?.count ?? 0) joined rooms, \
            \(syncResponse.rooms?.invite?.count ?? 0) invited rooms, \
            \(syncResponse.rooms?.leave?.count ?? 0) left rooms, \
            \(syncResponse.toDevice?.events.count ?? 0) toDevice events.
            """)
        
        if let accountData = syncResponse.accountData {
            pushRulesManager.handleAccountData(accountData)
        }
        syncResponseStoreManager.updateStore(with: syncResponse, syncToken: syncToken)
        
        await crypto.handleSyncResponse(syncResponse)
        
        if MXSDKOptions.sharedInstance().autoAcceptRoomInvites,
           let invitedRooms = syncResponse.rooms?.invite {
            invitedRooms.forEach { roomId, roomSync in
                MXLog.debug("[MXBackgroundSyncService] handleSyncResponse: Auto-accepting room invite for \(roomId)")
                restClient.joinRoom(roomId) { response in
                    switch response {
                    case .success:
                        MXLog.debug("[MXBackgroundSyncService] handleSyncResponse: Joined room: \(roomId)")
                    case .failure(let error):
                        MXLog.error("[MXBackgroundSyncService] handleSyncResponse: Failed to join room", context: [
                            "error": error,
                            "room_id": roomId
                        ])
                    }
                }
            }
        }
        
        MXLog.debug("[MXBackgroundSyncService] handleSyncResponse: Next sync token: \(syncResponse.nextBatch)")
    }
    
    private func updateBackgroundServiceStoresIfNeeded() {
        var outdatedStore = false
        
        // Check self.store data is in-sync with MXSession store data
        // by checking that the event stream token we have in memory is the same that in the last version of MXSession store
        let eventStreamToken = store.eventStreamToken
 
        let upToDateStore = MXBackgroundStore(withCredentials: credentials)
        let upToDateEventStreamToken = upToDateStore.eventStreamToken
        if eventStreamToken != upToDateEventStreamToken {
            // MXSession continued to work in parallel with the background sync service
            // MXSession has updated its stream token. We need to use it
            MXLog.debug("[MXBackgroundSyncService] updateBackgroundServiceStoresIfNeeded: Update MXBackgroundStore. Wrong sync token: \(String(describing: eventStreamToken)) instead of \(String(describing: upToDateEventStreamToken))")
            store = upToDateStore
            outdatedStore = true
        }
        
        if let cachedSyncResponseSyncToken = syncResponseStoreManager.syncToken() {
            if upToDateEventStreamToken != cachedSyncResponseSyncToken {
                // syncResponseStore has obsolete data. Reset it
                MXLog.debug("[MXBackgroundSyncService] updateBackgroundServiceStoresIfNeeded: Update MXSyncResponseStoreManager. Wrong sync token: \(String(describing: cachedSyncResponseSyncToken)) instead of \(String(describing: upToDateEventStreamToken))")
                outdatedStore = true
            }
            
            if outdatedStore {
                MXLog.debug("[MXBackgroundSyncService] updateBackgroundServiceStoresIfNeeded: Mark MXSyncResponseStoreManager data as outdated. Its sync token was \(String(describing: cachedSyncResponseSyncToken))")
                syncResponseStoreManager.markDataOutdated()
            }
        }
        
        syncPushRuleManagerWithAccountData()
    }
    
    private func syncPushRuleManagerWithAccountData() {
        if let accountData = syncResponseStoreManager.syncResponseStore.accountData {
            pushRulesManager.handleAccountData(accountData)
        } else if let accountData = store.userAccountData ?? nil {
            pushRulesManager.handleAccountData(accountData)
        }
    }
}
