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

/// MXSpaceNotificationState stores the categorized number of unread messages
@objcMembers
public class MXSpaceNotificationState: NSObject {
    /// Number of unread messages in favourite rooms
    public var favouriteMissedDiscussionsCount: UInt = 0
    /// Number of unread highlight messages in favourite rooms
    public var favouriteMissedDiscussionsHighlightedCount: UInt = 0
    /// Number of unread messages in DM rooms
    public var directMissedDiscussionsCount: UInt = 0
    /// Number of unread highlight messages in DM rooms
    public var directMissedDiscussionsHighlightedCount: UInt = 0
    /// Number of unread messages in rooms other than DMs
    public var groupMissedDiscussionsCount: UInt = 0
    /// Number of unread highlight message sin rooms other than DMs
    public var groupMissedDiscussionsHighlightedCount: UInt = 0
    /// Number of all unread messages
    public var allCount: UInt {
        return favouriteMissedDiscussionsCount + directMissedDiscussionsCount + groupMissedDiscussionsCount
    }
    /// Number of all unread highlight messages
    public var allHighlightCount: UInt {
        return favouriteMissedDiscussionsHighlightedCount + directMissedDiscussionsHighlightedCount + groupMissedDiscussionsHighlightedCount
    }
    
    static func +(left: MXSpaceNotificationState, right: MXSpaceNotificationState) -> MXSpaceNotificationState {
        let sum = MXSpaceNotificationState()
        sum.favouriteMissedDiscussionsCount = left.favouriteMissedDiscussionsCount + right.favouriteMissedDiscussionsCount
        sum.favouriteMissedDiscussionsHighlightedCount = left.favouriteMissedDiscussionsHighlightedCount + right.favouriteMissedDiscussionsHighlightedCount
        sum.directMissedDiscussionsCount = left.directMissedDiscussionsCount + right.directMissedDiscussionsCount
        sum.directMissedDiscussionsHighlightedCount = left.directMissedDiscussionsHighlightedCount + right.directMissedDiscussionsHighlightedCount
        sum.groupMissedDiscussionsCount = left.groupMissedDiscussionsCount + right.groupMissedDiscussionsCount
        sum.groupMissedDiscussionsHighlightedCount = left.groupMissedDiscussionsHighlightedCount + right.groupMissedDiscussionsHighlightedCount
        return sum
    }
    
    static public func +=( left: inout MXSpaceNotificationState, right: MXSpaceNotificationState) {
        left = left + right
    }
}
