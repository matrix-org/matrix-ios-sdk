// 
// Copyright 2022 The Matrix.org Foundation C.I.C
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

class MXLegacyBackgroundCrypto: MXBackgroundCrypto {
    private let credentials: MXCredentials
    private let cryptoStore: MXBackgroundCryptoStore
    private let olmDevice: MXOlmDevice
    
    init(credentials: MXCredentials, resetBackgroundCryptoStore: Bool) {
        self.credentials = credentials
        cryptoStore = MXBackgroundCryptoStore(credentials: credentials, resetBackgroundCryptoStore: resetBackgroundCryptoStore)
        olmDevice = MXOlmDevice(store: cryptoStore)
    }
    
    func handleSyncResponse(_ syncResponse: MXSyncResponse) {
        for event in syncResponse.toDevice?.events ?? [] {
            handleToDeviceEvent(event)
        }
    }
    
    func canDecryptEvent(_ event: MXEvent) -> Bool {
        if !event.isEncrypted {
            return true
        }
        
        guard let senderKey = event.content["sender_key"] as? String,
            let sessionId = event.content["session_id"] as? String else {
            return false
        }
        
        return cryptoStore.inboundGroupSession(withId: sessionId, andSenderKey: senderKey) != nil
    }
    
    func decryptEvent(_ event: MXEvent) throws {
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
            
            let olmResult = try olmDevice.decryptGroupMessage(ciphertext, isEditEvent: event.isEdit(), roomId: event.roomId, inTimeline: nil, sessionId: sessionId, senderKey: senderKey)
            
            let decryptionResult = MXEventDecryptionResult()
            decryptionResult.clearEvent = olmResult.payload
            decryptionResult.senderCurve25519Key = olmResult.senderKey
            decryptionResult.claimedEd25519Key = olmResult.keysClaimed["ed25519"] as? String
            decryptionResult.forwardingCurve25519KeyChain = olmResult.forwardingCurve25519KeyChain
            decryptionResult.isUntrusted = olmResult.isUntrusted
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
    
    func reset() {
        cryptoStore.reset()
    }
    
    // MARK: - Private
    
    private func handleToDeviceEvent(_ event: MXEvent) {
        //   only handle supported events
        guard MXTools.isSupportedToDeviceEvent(event) else {
            MXLog.debug("[MXLegacyBackgroundCrypto] handleToDeviceEvent: ignore unsupported event")
            return
        }
        
        if event.isEncrypted {
            do {
                try decryptEvent(event)
            } catch let error {
                MXLog.debug("[MXLegacyBackgroundCrypto] handleToDeviceEvent: Could not decrypt to-device event: \(error)")
                return
            }
        }
        
        guard let userId = credentials.userId else {
            MXLog.error("[MXLegacyBackgroundCrypto] handleToDeviceEvent: Cannot get userId")
            return
        }
        
        let factory = MXRoomKeyInfoFactory(myUserId: userId, store: cryptoStore)
        guard let key = factory.roomKey(for: event) else {
            MXLog.error("[MXLegacyBackgroundCrypto] handleToDeviceEvent: Cannot create megolm key from event")
            return
        }
        
        switch key.type {
        case .safe:
            olmDevice.addInboundGroupSession(
                key.info.sessionId,
                sessionKey: key.info.sessionKey,
                roomId: key.info.roomId,
                senderKey: key.info.senderKey,
                forwardingCurve25519KeyChain: key.info.forwardingKeyChain,
                keysClaimed: key.info.keysClaimed,
                exportFormat: key.info.exportFormat,
                sharedHistory: key.info.sharedHistory,
                untrusted: key.type != .safe
            )
        case .unsafe:
            MXLog.warning("[MXLegacyBackgroundCrypto] handleToDeviceEvent: Ignoring unsafe keys")
        case .unrequested:
            MXLog.warning("[MXLegacyBackgroundCrypto] handleToDeviceEvent: Ignoring unrequested keys")
        }
    }
    
    private func decryptMessageWithOlm(message: [AnyHashable: Any], theirDeviceIdentityKey: String) -> String? {
        let sessionIds = olmDevice.sessionIds(forDevice: theirDeviceIdentityKey)
        let messageBody = message[kMXMessageBodyKey] as? String
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
}
