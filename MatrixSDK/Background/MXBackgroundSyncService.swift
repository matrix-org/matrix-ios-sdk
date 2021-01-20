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
    private let credentials: MXCredentials
    private let syncResponseStore: MXSyncResponseStore
    private var store: MXStore
    private let cryptoStore: MXBackgroundCryptoStore
    private let olmDevice: MXOlmDevice
    private let restClient: MXRestClient
    private var pushRulesManager: MXBackgroundPushRulesManager
    
    /// Cached events. Keys are even identifiers.
    private var cachedEvents: [String: MXEvent] = [:]
    
    /// Initializer
    /// - Parameter credentials: account credentials
    public init(withCredentials credentials: MXCredentials) {
        processingQueue = DispatchQueue(label: "MXBackgroundSyncServiceQueue-" + MXTools.generateSecret())
        self.credentials = credentials
        syncResponseStore = MXSyncResponseFileStore()
        syncResponseStore.open(withCredentials: credentials)
        restClient = MXRestClient(credentials: credentials, unrecognizedCertificateHandler: nil)
        restClient.completionQueue = processingQueue
        store = MXBackgroundStore(withCredentials: credentials)
        // We can flush any crypto data if our sync response store is empty
        let resetBackgroundCryptoStore = syncResponseStore.syncResponse == nil
        cryptoStore = MXBackgroundCryptoStore(credentials: credentials, resetBackgroundCryptoStore: resetBackgroundCryptoStore)
        olmDevice = MXOlmDevice(store: cryptoStore)
        pushRulesManager = MXBackgroundPushRulesManager(withCredentials: credentials)
        if let accountData = syncResponseStore.syncResponse?.accountData {
            pushRulesManager.handleAccountData(accountData)
        } else if let accountData = store.userAccountData ?? nil {
            pushRulesManager.handleAccountData(accountData)
        }
        super.init()
    }
    
    /// Fetch event with given event and room identifiers. It performs a sync if the event not found in session store.
    /// - Parameters:
    ///   - eventId: The event identifier for the desired event
    ///   - roomId: The room identifier for the desired event
    ///   - completion: Completion block to be called. Always called in main thread.
    public func event(withEventId eventId: String,
                      inRoom roomId: String,
                      completion: @escaping (MXResponse<MXEvent>) -> Void) {
        processingQueue.async {
            self._event(withEventId: eventId, inRoom: roomId, completion: completion)
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
    
    /// Check whether the given room is mentions only.
    /// - Parameter roomId: The room identifier to be checked
    /// - Returns: If the room is mentions only.
    public func isRoomMentionsOnly(_ roomId: String) -> Bool {
        return pushRulesManager.isRoomMentionsOnly(roomId)
    }
    
    /// Fetch the summary for the given room identifier.
    /// - Parameter roomId: The room identifier to fetch.
    /// - Returns: Summary of room.
    public func roomSummary(forRoomId roomId: String) -> MXRoomSummary? {
        return syncResponseStore.roomSummary(forRoomId: roomId, using: store.summary?(ofRoom: roomId))
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
    
    //  MARK: - Private
    
    private func _event(withEventId eventId: String,
                        inRoom roomId: String,
                        allowSync: Bool = true,
                        completion: @escaping (MXResponse<MXEvent>) -> Void) {
        NSLog("[MXBackgroundSyncService] fetchEvent: \(eventId). allowSync: \(allowSync)")
        
        // Check local stores on every request so that we use up-to-data data from the MXSession store
        if allowSync {
            updateBackgroundServiceStoresIfNeeded()
        }
        
        /// Inline function to handle decryption failure
        func handleDecryptionFailure(withError error: Error?) {
            if allowSync {
                NSLog("[MXBackgroundSyncService] fetchEvent: Launch a background sync.")
                self.launchBackgroundSync(forEventId: eventId, roomId: roomId, completion: completion)
            } else {
                NSLog("[MXBackgroundSyncService] fetchEvent: Do not sync anymore.")
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
                NSLog("[MXBackgroundSyncService] fetchEvent: Event not encrypted.")
                Queues.dispatchQueue.async {
                    completion(.success(event))
                }
                return
            }
            
            //  encrypted
            if event.clear != nil {
                //  already decrypted
                NSLog("[MXBackgroundSyncService] fetchEvent: Event already decrypted.")
                Queues.dispatchQueue.async {
                    completion(.success(event))
                }
                return
            }
            
            //  should decrypt it first
            if canDecryptEvent(event) {
                //  we have keys to decrypt the event
                NSLog("[MXBackgroundSyncService] fetchEvent: Event needs to be decrpyted, and we have the keys to decrypt it.")
                
                do {
                    try decryptEvent(event)
                    Queues.dispatchQueue.async {
                        completion(.success(event))
                    }
                } catch let error {
                    NSLog("[MXBackgroundSyncService] fetchEvent: Decryption failed even crypto claimed it has the keys.")
                    handleDecryptionFailure(withError: error)
                }
            } else {
                //  we don't have keys to decrypt the event
                NSLog("[MXBackgroundSyncService] fetchEvent: Event needs to be decrpyted, but we don't have the keys to decrypt it.")
                handleDecryptionFailure(withError: nil)
            }
        }
        
        //  check if we've fetched the event before
        if let cachedEvent = self.cachedEvents[eventId] {
            //  use cached event
            handleEncryption(forEvent: cachedEvent)
        } else {
            //  do not call the /event api and just check if the event exists in the store
            let event = syncResponseStore.event(withEventId: eventId, inRoom: roomId)
                // Disable read access to MXSession store because it consumes too much RAM
                // and RAM is limited when running an app extension
                // TODO: Find a way to reuse MXSession store data
                //?? store.event(withEventId: eventId, inRoom: roomId)
            
            if let event = event {
                NSLog("[MXBackgroundSyncService] fetchEvent: We have the event in stores.")
                //  cache this event
                self.cachedEvents[eventId] = event
                
                //  handle encryption for this event
                handleEncryption(forEvent: event)
            } else if allowSync {
                NSLog("[MXBackgroundSyncService] fetchEvent: We don't have the event in stores. Launch a background sync to fetch it.")
                self.launchBackgroundSync(forEventId: eventId, roomId: roomId, completion: completion)
            } else {
                // Final fallback, try with /event API
                NSLog("[MXBackgroundSyncService] fetchEvent: We still don't have the event in stores. Try with /event API")
                
                restClient.event(withEventId: eventId, inRoom: roomId) { [weak self] (response) in
                    
                    guard let self = self else {
                        NSLog("[NotificationService] fetchEvent: /event API returned too late successfully.")
                        return
                    }
                    
                    switch response {
                        case .success(let event):
                            NSLog("[MXBackgroundSyncService] fetchEvent: We got the event from /event API")
                            
                            //  cache this event
                            self.cachedEvents[eventId] = event
                            
                            //  handle encryption for this event
                            handleEncryption(forEvent: event)
                            
                        case .failure(let error):
                            NSLog("[MXBackgroundSyncService] fetchEvent: Failed to fetch event \(eventId)")
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
            
        guard let eventStreamToken = syncResponseStore.syncResponse?.nextBatch ?? store.eventStreamToken else {
            NSLog("[MXBackgroundSyncService] launchBackgroundSync: Do not sync because event streaming not started yet.")
            Queues.dispatchQueue.async {
                completion(.failure(MXBackgroundSyncServiceError.unknown))
            }
            return
        }
        
        //  save the token for the start of the sync response
        if (syncResponseStore.prevBatch == nil)
        {
            syncResponseStore.prevBatch = eventStreamToken
        }
        
        NSLog("[MXBackgroundSyncService] launchBackgroundSync: start from token \(eventStreamToken)")
        
        restClient.sync(fromToken: eventStreamToken,
                        serverTimeout: Constants.syncRequestServerTimout,
                        clientTimeout: Constants.syncRequestClientTimout,
                        setPresence: Constants.syncRequestPresence,
                        filterId: store.syncFilterId ?? nil) { [weak self] (response) in
            switch response {
            case .success(let syncResponse):
                guard let self = self else {
                    NSLog("[MXBackgroundSyncService] launchBackgroundSync: MXRestClient.syncFromToken returned too late successfully")
                    Queues.dispatchQueue.async {
                        completion(.failure(MXBackgroundSyncServiceError.unknown))
                    }
                    return
                }

                self.handleSyncResponse(syncResponse)
                
                if let event = self.syncResponseStore.event(withEventId: eventId, inRoom: roomId),
                    !self.canDecryptEvent(event),
                    (syncResponse.toDevice?.events ?? []).count > 0 {
                    //  we got the event but not the keys to decrypt it. continue to sync
                    self.launchBackgroundSync(forEventId: eventId, roomId: roomId, completion: completion)
                } else {
                    //  do not allow to sync anymore
                    self._event(withEventId: eventId, inRoom: roomId, allowSync: false, completion: completion)
                }
            case .failure(let error):
                guard let _ = self else {
                    NSLog("[MXBackgroundSyncService] launchBackgroundSync: MXRestClient.syncFromToken returned too late with error: \(String(describing: error))")
                    Queues.dispatchQueue.async {
                        completion(.failure(error))
                    }
                    return
                }
                NSLog("[MXBackgroundSyncService] launchBackgroundSync: MXRestClient.syncFromToken returned with error: \(String(describing: error))")
                Queues.dispatchQueue.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func canDecryptEvent(_ event: MXEvent) -> Bool {
        if !event.isEncrypted {
            return true
        }
        
        guard let senderKey = event.content["sender_key"] as? String,
            let sessionId = event.content["session_id"] as? String else {
            return false
        }
        
        return cryptoStore.inboundGroupSession(withId: sessionId, andSenderKey: senderKey) != nil
    }
    
    private func decryptEvent(_ event: MXEvent) throws {
        if !event.isEncrypted {
            return
        }
        
        guard let senderKey = event.content["sender_key"] as? String,
            let algorithm = event.content["algorithm"] as? String else {
                throw MXBackgroundSyncServiceError.unknown
        }
        
        guard let decryptorClass = MXCryptoAlgorithms.shared()?.decryptorClass(forAlgorithm: algorithm) else {
            throw MXBackgroundSyncServiceError.unknownAlgorithm
        }
        
        if decryptorClass == MXMegolmDecryption.self {
            guard let ciphertext = event.content["ciphertext"] as? String,
                let sessionId = event.content["session_id"] as? String else {
                    throw MXBackgroundSyncServiceError.unknown
            }
            
            let olmResult = try olmDevice.decryptGroupMessage(ciphertext, roomId: event.roomId, inTimeline: nil, sessionId: sessionId, senderKey: senderKey)
            
            let decryptionResult = MXEventDecryptionResult()
            decryptionResult.clearEvent = olmResult.payload
            decryptionResult.senderCurve25519Key = olmResult.senderKey
            decryptionResult.claimedEd25519Key = olmResult.keysClaimed["ed25519"] as? String
            decryptionResult.forwardingCurve25519KeyChain = olmResult.forwardingCurve25519KeyChain
            event.setClearData(decryptionResult)
        } else if decryptorClass == MXOlmDecryption.self {
            guard let ciphertextDict = event.content["ciphertext"] as? [AnyHashable: Any],
                let deviceCurve25519Key = olmDevice.deviceCurve25519Key,
                let message = ciphertextDict[deviceCurve25519Key] as? [AnyHashable: Any],
                let payloadString = decryptMessageWithOlm(message: message, theirDeviceIdentityKey: senderKey) else {
                    throw MXBackgroundSyncServiceError.decryptionFailure
            }
            guard let payloadData = payloadString.data(using: .utf8),
                let payload = try? JSONSerialization.jsonObject(with: payloadData,
                                                                  options: .init(rawValue: 0)) as? [AnyHashable: Any],
                let recipient = payload["recipient"] as? String,
                recipient == credentials.userId,
                let recipientKeys = payload["recipient_keys"] as? [AnyHashable: Any],
                let ed25519 = recipientKeys["ed25519"] as? String,
                ed25519 == olmDevice.deviceEd25519Key,
                let sender = payload["sender"] as? String,
                sender == event.sender else {
                    throw MXBackgroundSyncServiceError.decryptionFailure
            }
            if let roomId = event.roomId {
                guard payload["room_id"] as? String == roomId else {
                    throw MXBackgroundSyncServiceError.decryptionFailure
                }
            }
            
            let claimedKeys = payload["keys"] as? [AnyHashable: Any]
            let decryptionResult = MXEventDecryptionResult()
            decryptionResult.clearEvent = payload
            decryptionResult.senderCurve25519Key = senderKey
            decryptionResult.claimedEd25519Key = claimedKeys?["ed25519"] as? String
            event.setClearData(decryptionResult)
        } else {
            throw MXBackgroundSyncServiceError.unknownAlgorithm
        }
    }
    
    private func decryptMessageWithOlm(message: [AnyHashable: Any], theirDeviceIdentityKey: String) -> String? {
        let sessionIds = olmDevice.sessionIds(forDevice: theirDeviceIdentityKey)
        let messageBody = message["body"] as? String
        let messageType = message["type"] as? UInt ?? 0
        
        for sessionId in sessionIds ?? [] {
            if let payload = olmDevice.decryptMessage(messageBody,
                                                      withType: messageType,
                                                      sessionId: sessionId,
                                                      theirDeviceIdentityKey: theirDeviceIdentityKey) {
                return payload
            } else {
                let foundSession = olmDevice.matchesSession(theirDeviceIdentityKey,
                                                            sessionId: sessionId,
                                                            messageType: messageType,
                                                            ciphertext: messageBody)
                if foundSession {
                    return nil
                }
            }
        }
        
        if messageType != 0 {
            return nil
        }
        
        var payload: NSString?
        guard let _ = olmDevice.createInboundSession(theirDeviceIdentityKey,
                                                     messageType: messageType,
                                                     cipherText: messageBody,
                                                     payload: &payload) else {
                                                        return nil
        }
        return payload as String?
    }
    
    private func handleSyncResponse(_ syncResponse: MXSyncResponse) {
        NSLog("[MXBackgroundSyncService] handleSyncResponse: Received %tu joined rooms, %tu invited rooms, %tu left rooms, %tu toDevice events.",
              syncResponse.rooms.join.count,
              syncResponse.rooms.invite.count,
              syncResponse.rooms.leave.count,
              syncResponse.toDevice.events?.count ?? 0)
        
        self.pushRulesManager.handleAccountData(syncResponse.accountData)
        self.updateStore(with: syncResponse)
        
        for event in syncResponse.toDevice?.events ?? [] {
            handleToDeviceEvent(event)
        }
        
        NSLog("[MXBackgroundSyncService] handleSyncResponse: Next sync token: \(syncResponse.nextBatch ?? "nil")")
    }
    
    private func updateStore(with newResponse: MXSyncResponse) {
        if let oldResponse = syncResponseStore.syncResponse {
            //  current sync response exists, merge it with the new response
            
            //  handle new limited timelines
            newResponse.rooms.join.filter({ $1.timeline?.limited == true }).forEach { (roomId, _) in
                if let joinedRoomSync = oldResponse.rooms.join[roomId] {
                    //  remove old events
                    joinedRoomSync.timeline?.events = []
                    //  mark old timeline as limited too
                    joinedRoomSync.timeline?.limited = true
                }
            }
            newResponse.rooms.leave.filter({ $1.timeline?.limited == true }).forEach { (roomId, _) in
                if let leftRoomSync = oldResponse.rooms.leave[roomId] {
                    //  remove old events
                    leftRoomSync.timeline?.events = []
                    //  mark old timeline as limited too
                    leftRoomSync.timeline?.limited = true
                }
            }
            
            //  handle old limited timelines
            oldResponse.rooms.join.filter({ $1.timeline?.limited == true }).forEach { (roomId, _) in
                if let joinedRoomSync = newResponse.rooms.join[roomId] {
                    //  mark new timeline as limited too, to avoid losing value of limited
                    joinedRoomSync.timeline?.limited = true
                }
            }
            oldResponse.rooms.leave.filter({ $1.timeline?.limited == true }).forEach { (roomId, _) in
                if let leftRoomSync = newResponse.rooms.leave[roomId] {
                    //  mark new timeline as limited too, to avoid losing value of limited
                    leftRoomSync.timeline?.limited = true
                }
            }
            var dictionary = NSDictionary(dictionary: oldResponse.jsonDictionary())
            dictionary = dictionary + NSDictionary(dictionary: newResponse.jsonDictionary())
            syncResponseStore.syncResponse = MXSyncResponse(fromJSON: dictionary as? [AnyHashable : Any])
        } else {
            //  no current sync response, directly save the new one
            syncResponseStore.syncResponse = newResponse
        }
    }
    
    private func handleToDeviceEvent(_ event: MXEvent) {
        if event.isEncrypted {
            do {
                try decryptEvent(event)
            } catch let error {
                NSLog("[MXBackgroundSyncService] handleToDeviceEvent: Could not decrypt to-device event: \(error)")
                return
            }
        }
        
        guard let content = event.content else {
            NSLog("[MXBackgroundSyncService] handleToDeviceEvent: ERROR: incomplete event content: \(String(describing: event.jsonDictionary()))")
            return
        }
        
        guard let roomId = content["room_id"] as? String,
            let sessionId = content["session_id"] as? String,
            let sessionKey = content["session_key"] as? String,
            var senderKey = event.senderKey else {
            NSLog("[MXBackgroundSyncService] handleToDeviceEvent: ERROR: incomplete event: \(String(describing: event.jsonDictionary()))")
            return
        }
        
        var forwardingKeyChain: [String] = []
        var exportFormat: Bool = false
        var keysClaimed: [String: String] = [:]
        
        switch event.eventType {
        case .roomKey:
            keysClaimed = event.keysClaimed as! [String: String]
        case .roomForwardedKey:
            exportFormat = true
            
            if let array = content["forwarding_curve25519_key_chain"] as? [String] {
                forwardingKeyChain = array
            }
            forwardingKeyChain.append(senderKey)
            
            if let senderKeyInContent = content["sender_key"] as? String {
                senderKey = senderKeyInContent
            } else {
                return
            }
            
            guard let ed25519Key = event.content["sender_claimed_ed25519_key"] as? String else {
                return
            }
            
            keysClaimed = [
                "ed25519": ed25519Key
            ]
        default:
            NSLog("[MXBackgroundSyncService] handleToDeviceEvent: ERROR: Not supported type: \(event.eventType)")
            return
        }
        
        olmDevice.addInboundGroupSession(sessionId,
                                         sessionKey: sessionKey,
                                         roomId: roomId,
                                         senderKey: senderKey,
                                         forwardingCurve25519KeyChain: forwardingKeyChain,
                                         keysClaimed: keysClaimed,
                                         exportFormat: exportFormat)
    }
    
    private func updateBackgroundServiceStoresIfNeeded() {
        // Check self.store data is in-sync with MXSession store data
        // by checking that the event stream token we have in memory is the same that in the last version of MXSession store
        let eventStreamToken = store.eventStreamToken
 
        let upToDateStore = MXBackgroundStore(withCredentials: credentials)
        let upToDateEventStreamToken = upToDateStore.eventStreamToken

        if (eventStreamToken != upToDateEventStreamToken) {
            // MXSession continued to work in parallel with the background sync service
            // MXSession has updated its stream token. We need to use t
            NSLog("[MXBackgroundSyncService] updateBackgroundServiceStoresIfNeeded: Update MXBackgroundStore. Its event stream token (\(String(describing: eventStreamToken))) does not match current MXStore.eventStreamToken (\(String(describing: upToDateEventStreamToken)))")
            store = upToDateStore
            
            // syncResponseStore has obsolete data. Reset it
            NSLog("[MXBackgroundSyncService] updateBackgroundServiceStoresIfNeeded: Reset MXSyncResponseStore. Its prevBatch was token \(String(describing: syncResponseStore.prevBatch))")
            syncResponseStore.deleteData()
            
            NSLog("[MXBackgroundSyncService] updateBackgroundServiceStoresIfNeeded: Reset MXBackgroundCryptoStore")
            cryptoStore.reset()
        }
    }
    
}
