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

@objc
/// Most popular counts used by recents
public protocol MXRoomListDataCounts {
    
    /// Number of rooms handled by this instance
    var numberOfRooms: Int { get }
    
    /// Total number of rooms. Can be different from `numberOfRooms` if pagination enabled
    var totalRoomsCount: Int { get }
    
    /// Number of rooms having unsent message(s)
    var numberOfUnsentRooms: Int { get }
    
    /// Number of rooms being notified
    var numberOfNotifiedRooms: Int { get }
    
    /// Number of room being highlighted
    var numberOfHighlightedRooms: Int { get }
    
    /// Total notification count for handled rooms
    var totalNotificationCount: UInt { get }
    
    /// Total highlight count for handled rooms
    var totalHighlightCount: UInt { get }
    
    /// Number of invited rooms
    var numberOfInvitedRooms: Int { get }
    
}
