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

extension MXEvent {
    static func fixture(id: Int) -> MXEvent {
        return MXEvent(fromJSON: [
            "event_id": "\(id)"
        ])!
    }
    
    static func fixture(id: Int, threadId: String) -> MXEvent {
        return MXEvent(fromJSON: [
            "event_id": "\(id)",
            "content": [
                kMXEventRelationRelatesToKey: [
                    kMXEventContentRelatesToKeyEventId: threadId,
                    kMXEventContentRelatesToKeyRelationType: MXEventRelationTypeThread
                ]
            ]
        ])!
    }
    
    static func fixture(
        type: String,
        sender: String = "",
        content: [String: Any] = [:]
    ) -> MXEvent {
        let result = MXEventDecryptionResult()
        result.clearEvent = [
            "type": type,
            "content": content
        ]
        
        let event = MXEvent(fromJSON: [:])!
        event.sender = sender
        event.setClearData(result)
        return event
    }
    
    static func roomKeyFixture(
        algorithm: String = "megolm",
        roomId: String = "!123:matrix.org",
        sessionId: String = "session1",
        sessionKey: String = "<key>",
        senderKey: String = "<sender_key>",
        claimedKey: String = "<claimed_key>",
        sharedHistory: Bool? = nil
    ) -> MXEvent {
        var content: [String: Any] = [
            "type": kMXEventTypeStringRoomKey,
            "room_id": roomId,
            "session_id": sessionId,
            "session_key": sessionKey,
            "algorithm": algorithm
        ]
        
        if let sharedHistory = sharedHistory {
            content["org.matrix.msc3061.shared_history"] = sharedHistory
        }
        
        let result = MXEventDecryptionResult()
        result.senderCurve25519Key = senderKey
        result.claimedEd25519Key = claimedKey
        result.clearEvent = [
            "type": kMXEventTypeStringRoomKey,
            "content": content
        ]
        
        let event = MXEvent(fromJSON: [:])!
        event.setClearData(result)
        return event
    }
    
    static func forwardedRoomKeyFixture(
        algorithm: String = "megolm",
        roomId: String = "!123:matrix.org",
        sessionId: String = "session1",
        sessionKey: String = "<key>",
        senderKey: String = "<sender_key>",
        initialSenderKey: String = "<initial_sender_key>",
        claimedKey: String = "<claimed_key>",
        sharedHistory: Bool = false
    ) -> MXEvent {
        let content: [String: Any] = [
            "type": kMXEventTypeStringRoomKey,
            "room_id": roomId,
            "session_id": sessionId,
            "session_key": sessionKey,
            "algorithm": algorithm,
            "sender_key": initialSenderKey,
            "sender_claimed_ed25519_key": claimedKey,
            kMXSharedHistoryKeyName: sharedHistory
        ]
        
        let result = MXEventDecryptionResult()
        result.senderCurve25519Key = senderKey
        result.claimedEd25519Key = claimedKey
        result.clearEvent = [
            "type": kMXEventTypeStringRoomForwardedKey,
            "content": content
        ]
        
        let event = MXEvent(fromJSON: [:])!
        event.setClearData(result)
        return event
    }
    
    static func encryptedFixture(
        id: String = "1",
        sender: String = "Alice",
        sessionId: String = "123",
        senderKey: String = "456",
        ciphertext: String = "ABC"
    ) -> MXEvent {
        return MXEvent(fromJSON: [
            "type": "m.room.encrypted",
            "event_id": id,
            "sender": sender,
            "content": [
                "algorithm": kMXCryptoMegolmAlgorithm,
                "session_id": sessionId,
                "sender_key": senderKey,
                "ciphertext": ciphertext
            ]
        ])!
    }
}
