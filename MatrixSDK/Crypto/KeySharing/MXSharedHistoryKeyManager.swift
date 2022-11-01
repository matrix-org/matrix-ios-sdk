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

/// Manager responsible for sharing keys of messages in a room with an invited user
///
/// The intent of sharing keys with different users on invite is to allow them to see any immediate
/// context of the conversation that may have led to the invite. The amount of keys to be shared
/// is configurable, based on the number of messages that should be readable.
///
/// Note that after the initial key share by the inviting user, there is no mechanism by which the invited
/// user can request additional keys. There is also no retry mechanism if any of the initial key sharing fails.
@objc
public class MXSharedHistoryKeyManager: NSObject {
    struct SessionInfo: Hashable {
        let sessionId: String
        let senderKey: String
    }
    
    private let roomId: String
    private let crypto: MXCrypto
    private let service: MXSharedHistoryKeyService
    
    @objc public init(roomId: String, crypto: MXCrypto, service: MXSharedHistoryKeyService) {
        self.roomId = roomId
        self.crypto = crypto
        self.service = service
    }
    
    @objc public func shareMessageKeys(withUserId userId: String, messageEnumerator: MXEventsEnumerator, limit: Int) {
        // Convert the last few messages into session information
        let sessions = extractMessages(from: messageEnumerator, limit: limit)
            .compactMap(sessionInfo)
        
        // We need to force download all keys for a given user, as we may not have any of them locally yet
        crypto.downloadKeys([userId], forceDownload: true) { [weak self] userDevices, _ in
            guard
                let devices = userDevices?.objects(forUser: userId),
                !devices.isEmpty else
            {
                MXLog.debug("[MXSharedHistoryRoomKeyRequestManager] No known devices for user %@, cannot share keys", userId)
                return
            }
            
            self?.shareSessions(Set(sessions), userId: userId, devices: devices)
        } failure: {
            MXLog.debug("[MXSharedHistoryRoomKeyRequestManager] Failed downloading user keys - \(String(describing: $0.localizedDescription))")
        }
    }
    
    private func shareSessions(_ sessions: Set<SessionInfo>, userId: String, devices: [MXDeviceInfo]) {
        for session in sessions {
            
            let request = MXSharedHistoryKeyRequest(
                userId: userId,
                devices: devices,
                roomId: roomId,
                sessionId: session.sessionId,
                senderKey: session.senderKey
            )
            
            service.shareKeys(for: request) {
                // Success does not trigger any further action / user notification, so we only log the outcome
                MXLog.debug("[MXSharedHistoryRoomKeyRequestManager] Shared key successfully")
            } failure: {
                MXLog.debug("[MXSharedHistoryRoomKeyRequestManager] Failed sharing key - \(String(describing: $0?.localizedDescription))")
            }
        }
    }
    
    private func extractMessages(from enumerator: MXEventsEnumerator, limit: Int) -> [MXEvent] {
        var messages = [MXEvent]()
        while let event = enumerator.nextEvent, messages.count < limit {
            if event.wireEventType == .roomEncrypted {
                messages.append(event)
            }
        }
        return messages
    }
    
    private func sessionInfo(for message: MXEvent) -> SessionInfo? {
        let content = message.wireContent
        guard
            let sessionId = content?["session_id"] as? String,
            let senderKey = content?["sender_key"] as? String
        else {
            MXLog.debug("[MXSharedHistoryRoomKeyRequestManager] Cannot create key request")
            return nil
        }

        guard service.hasSharedHistory(forRoomId: roomId, sessionId: sessionId, senderKey: senderKey) else {
            MXLog.debug("[MXSharedHistoryRoomKeyRequestManager] Skipping keys for message without shared history or mismatched room identifier")
            return nil
        }
        
        return .init(
            sessionId: sessionId,
            senderKey: senderKey
        )
    }
}
