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

/// MXSpaceNotificationCounter compute the number of unread messages for each space
@objcMembers
public class MXSpaceNotificationCounter: NSObject {
    
    // MARK: - Properties
    
    public private(set) var homeNotificationState = MXSpaceNotificationState()
    private var notificationStatePerSpaceId: [String:MXSpaceNotificationState] = [:]
    
    // MARK: - Public
    
    /// Compute the notification count for every spaces
    /// - Parameters:
    ///   - spaces: list of spaces of the current sessiom
    ///   - rooms: list of rooms of the current session
    ///   - flattenedParentIds: the flattened aprent ID for all rooms
    public func computeNotificationCount(for spaces:[MXSpace], with rooms:[MXRoom], flattenedParentIds: [String: Set<String>]) {
        let startDate = Date()
        MXLog.debug("[Spaces] computeNotificationCount started")

        var homeNotificationState = MXSpaceNotificationState()
        var notificationStatePerSpaceId: [String:MXSpaceNotificationState] = [:]
        
        for room in rooms {
            guard room.summary.roomType != .space else {
                continue
            }
            
            let notificationState = self.notificationState(forRoomWithId: room)
            
            homeNotificationState += notificationState
            for space in spaces {
                if flattenedParentIds[room.roomId]?.contains(space.spaceId) ?? false {
                    let storedState = notificationStatePerSpaceId[space.spaceId] ?? MXSpaceNotificationState()
                    notificationStatePerSpaceId[space.spaceId] = storedState + notificationState
                }
            }
        }
        
        self.homeNotificationState = homeNotificationState
        self.notificationStatePerSpaceId = notificationStatePerSpaceId
        
        MXLog.debug("[Spaces] computeNotificationCount ended after \(Date().timeIntervalSince(startDate))s")
    }
    
    /// Notification state for a given space
    /// - Parameters:
    ///   - spaceId: ID of the space
    /// - Returns: a `MXSpaceNotificationState` instance with the number of notifications for the given space
    public func notificationState(forSpaceWithId spaceId: String) -> MXSpaceNotificationState? {
        return notificationStatePerSpaceId[spaceId]
    }
    
    /// Notification state for a all spaces except for a given space
    /// - Parameters:
    ///   - spaceId: ID of the space to be excluded
    /// - Returns: a `MXSpaceNotificationState` instance with the number of notifications for all spaces
    public func notificationState(forAllSpacesExcept spaceId: String?) -> MXSpaceNotificationState {
        var notificationState = MXSpaceNotificationState()
        notificationStatePerSpaceId.forEach { (key: String, state: MXSpaceNotificationState) in
            if key != spaceId {
                notificationState += state
            }
        }
        return notificationState
    }
    
    // MARK: - Private
    
    private func notificationState(forRoomWithId room: MXRoom) -> MXSpaceNotificationState {
        let notificationState = MXSpaceNotificationState()
        guard let summary = room.summary else {
            return notificationState
        }
        
        let notificationCount = self.isRoomMentionsOnly(summary) ? summary.highlightCount : summary.notificationCount
        
        if notificationCount > 0 {
            let tags = room.accountData.tags
            if tags != nil, tags?[kMXRoomTagFavourite] != nil {
                notificationState.favouriteMissedDiscussionsCount += summary.notificationCount
                notificationState.favouriteMissedDiscussionsHighlightedCount += summary.highlightCount
            }
            
            if summary.isDirect {
                notificationState.directMissedDiscussionsCount += summary.notificationCount
                notificationState.directMissedDiscussionsHighlightedCount += summary.highlightCount
            } else if tags?.isEmpty ?? true || tags?[kMXRoomTagFavourite] != nil {
                notificationState.groupMissedDiscussionsCount += summary.notificationCount
                notificationState.groupMissedDiscussionsHighlightedCount += summary.highlightCount
            }
        } else if summary.membership == .invite {
            if room.isDirect {
                notificationState.directMissedDiscussionsHighlightedCount += 1
            } else {
                notificationState.groupMissedDiscussionsHighlightedCount += 1
            }
        }
        
        return notificationState
    }
    
    private func isRoomMentionsOnly(_ summary: MXRoomSummary) -> Bool {
        guard let rules = summary.mxSession?.notificationCenter?.rules?.global?.room as? [MXPushRule] else {
            return false
        }
        
        for rule in rules {
            guard rule.ruleId == summary.roomId, let ruleActions = rule.actions as? [MXPushRuleAction] else {
                continue
            }
            
            for ruleAction in ruleActions where ruleAction.actionType == MXPushRuleActionTypeDontNotify {
                return rule.enabled
            }
            break
        }
        
        return false
    }
}
