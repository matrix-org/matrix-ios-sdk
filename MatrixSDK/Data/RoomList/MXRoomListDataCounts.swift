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
    
    /// Number of handled rooms having unsent message(s)
    var numberOfUnsentRooms: Int { get }
    
    /// Number of handled rooms being notified
    var numberOfNotifiedRooms: Int { get }
    
    /// Number of handled rooms being highlighted
    var numberOfHighlightedRooms: Int { get }
    
    /// Sum of notification counts for handled rooms
    var numberOfNotifications: UInt { get }
    
    /// Sum of highlight counts for handled rooms
    var numberOfHighlights: UInt { get }
    
    /// Number of invited rooms for handled rooms
    var numberOfInvitedRooms: Int { get }
    
    /// Total values. nil if pagination is not enabled.
    var total: MXRoomListDataCounts? { get }
    
}
