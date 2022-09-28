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

/// Domain object representing a room key and its parameters
@objcMembers
public class MXRoomKeyInfo: NSObject {
    public let algorithm: String
    public let sessionId: String
    public let sessionKey: String
    public let roomId: String
    public let senderKey: String
    public let forwardingKeyChain: [String]?
    public let keysClaimed: [String: String]
    public let exportFormat: Bool
    public let sharedHistory: Bool
    
    public init(
        algorithm: String,
        sessionId: String,
        sessionKey: String,
        roomId: String,
        senderKey: String,
        forwardingKeyChain: [String]?,
        keysClaimed: [String: String],
        exportFormat: Bool,
        sharedHistory: Bool
    ) {
        self.algorithm = algorithm
        self.sessionId = sessionId
        self.sessionKey = sessionKey
        self.roomId = roomId
        self.senderKey = senderKey
        self.forwardingKeyChain = forwardingKeyChain
        self.keysClaimed = keysClaimed
        self.exportFormat = exportFormat
        self.sharedHistory = sharedHistory
        super.init()
    }
}

extension MXRoomKeyInfo {
    convenience init?(roomKey: MXRoomKeyEventContent, event: MXEvent) {
        guard let senderKey = event.senderKey, let keysClaimed = event.keysClaimed as? [String: String] else {
            return nil
        }
        
        self.init(
            algorithm: roomKey.algorithm,
            sessionId: roomKey.sessionId,
            sessionKey: roomKey.sessionKey,
            roomId: roomKey.roomId,
            senderKey: senderKey,
            forwardingKeyChain: nil,
            keysClaimed: keysClaimed,
            exportFormat: false,
            sharedHistory: roomKey.sharedHistory
        )
    }
}

extension MXRoomKeyInfo {
    convenience init(forwardedRoomKey: MXForwardedRoomKeyEventContent) {
        self.init(
            algorithm: forwardedRoomKey.algorithm,
            sessionId: forwardedRoomKey.sessionId,
            sessionKey: forwardedRoomKey.sessionKey,
            roomId: forwardedRoomKey.roomId,
            senderKey: forwardedRoomKey.senderKey,
            forwardingKeyChain: forwardedRoomKey.forwardingCurve25519KeyChain,
            keysClaimed: ["ed25519": forwardedRoomKey.senderClaimedEd25519Key],
            exportFormat: true,
            sharedHistory: forwardedRoomKey.sharedHistory
        )
    }
}
