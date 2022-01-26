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

// MARK: - Internal

/// InitialStateEvent represents an intial state event
struct InitialStateEvent {
    let type: String
    let stateKey: String = ""
    let content: [String: Any]
    
    var jsonDictionary: [String: Any] {
        return [
            "type": type,
            "stateKey": stateKey,
            "content": content
        ]
    }
}

// MARK: - Public

/// MXRoomInitialStateEventBuilder enables to build initial state events
@objcMembers
public class MXRoomInitialStateEventBuilder: NSObject {
    
    /// Build avatar state event
    /// - Parameter avatarURL: The mxc url of the avatar
    /// - Returns: State event dictionary
    public func buildAvatarEvent(withAvatarURL avatarURL: String) -> [String: Any] {
        let event = InitialStateEvent(type: MXEventType.roomAvatar.identifier,
                                      content: ["url": avatarURL])
        return event.jsonDictionary
    }
    
    /// Build history visibility state event
    /// - Parameter roomHistoryVisibility: The room history visibility
    /// - Returns: State event dictionary
    public func buildHistoryVisibilityEvent(withVisibility roomHistoryVisibility: MXRoomHistoryVisibility) -> [String: Any] {
        let event = InitialStateEvent(type: MXEventType.roomHistoryVisibility.identifier,
                                      content: ["history_visibility" : roomHistoryVisibility.identifier])
        return event.jsonDictionary
    }
    
    /// Build guest access state event
    /// - Parameter roomGuestAccess: The room guest access
    /// - Returns: State event dictionary
    public func buildGuestAccessEvent(withAccess roomGuestAccess: MXRoomGuestAccess) -> [String: Any] {
        let event = InitialStateEvent(type: MXEventType.roomGuestAccess.identifier,
                                      content: ["guest_access": roomGuestAccess.identifier])
        return event.jsonDictionary
    }
    
    /// Build algorithm access state event
    /// - Parameter algorithm: The encryption algorithm
    /// - Returns: State event dictionary
    public func buildAlgorithmEvent(withAlgorithm algorithm: String) -> [String: Any] {
        let event = InitialStateEvent(type: MXEventType.roomEncryption.identifier,
                                      content: ["algorithm": algorithm])
        return event.jsonDictionary
    }
    
    /// Build join rule state event
    /// - Parameter joinRule: The type of join rule
    /// - Parameter allowedParentsList: list of allowed parent IDs (used for `restricted` join rule)
    /// - Returns: State event dictionary
    public func buildJoinRuleEvent(withJoinRule joinRule: MXRoomJoinRule, allowedParentsList: [String]? = nil) -> [String: Any] {
        var content: [String: Any] = ["join_rule": joinRule.identifier]
        if let allowedParentsList = allowedParentsList {
            content["allow"] = allowedParentsList.map({ roomId in
                ["type" : kMXEventTypeStringRoomMembership, "room_id": roomId]
            })
        }
        let event = InitialStateEvent(type: MXEventType.roomJoinRules.identifier, content: content)
        return event.jsonDictionary
    }
}
