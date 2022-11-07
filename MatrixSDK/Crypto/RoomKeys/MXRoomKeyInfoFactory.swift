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

@objcMembers
public class MXRoomKeyInfoFactory: NSObject {
    private let myUserId: String
    private let store: MXCryptoStore
    private let log = MXNamedLog(name: "MXRoomKeyFactory")
    
    public init(myUserId: String, store: MXCryptoStore) {
        self.myUserId = myUserId
        self.store = store
    }
    
    public func roomKey(for event: MXEvent) -> MXRoomKeyResult? {
        if event.eventType == .roomKey {
            return roomKeyEventInfo(for: event)
        } else if event.eventType == .roomForwardedKey {
            return forwardedRoomKeyEventInfo(for: event)
        } else {
            log.error("Unknown event type", context: event.eventType)
            return nil
        }
    }
    
    private func roomKeyEventInfo(for event: MXEvent) -> MXRoomKeyResult? {
        guard
            let content = MXRoomKeyEventContent(fromJSON: event.content),
            let info = MXRoomKeyInfo(roomKey: content, event: event)
        else {
            log.error("Invalid room key")
            return nil
        }
        
        return .init(type: .safe, info: info)
    }
    
    private func forwardedRoomKeyEventInfo(for event: MXEvent) -> MXRoomKeyResult? {
        guard let eventSenderKey = event.senderKey else {
            log.error("Unknown event sender")
            return nil
        }
        
        guard let content = MXForwardedRoomKeyEventContent(fromJSON: event.content) else {
            log.error("Invalid forwarded key")
            return nil
        }
        
        content.forwardingCurve25519KeyChain += [eventSenderKey]

        return .init(
            type: keyType(for: content, senderKey: eventSenderKey),
            info: .init(forwardedRoomKey: content)
        )
    }
    
    private func keyType(for content: MXForwardedRoomKeyEventContent, senderKey: String) -> MXRoomKeyType {
        if !hasPendingRequest(for: content) {
            log.debug("Key was not requested")
            return .unrequested
        } else if isMyVerifiedDevice(identityKey: senderKey) {
            return .safe
        } else {
            log.debug("Key forward is not from my verified device")
            return .unsafe
        }
    }
    
    private func isMyVerifiedDevice(identityKey: String) -> Bool {
        guard let device = store.device(withIdentityKey: identityKey) else {
            return false
        }
        return device.userId == myUserId && device.trustLevel.isVerified
    }
    
    private func hasPendingRequest(for content: MXForwardedRoomKeyEventContent) -> Bool {
        let request = store.outgoingRoomKeyRequest(withRequestBody: [
            "room_id": content.roomId,
            "algorithm": content.algorithm,
            "sender_key": content.senderKey,
            "session_id": content.sessionId
        ])
        return request != nil
    }
}
