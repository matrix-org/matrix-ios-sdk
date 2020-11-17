// 
// Copyright 2020 The Matrix.org Foundation C.I.C
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

/// `MXRoomMembershipStateDataSource` store and notify room membership change state
@objcMembers
public class MXRoomMembershipStateDataSource: NSObject {
    
    // MARK: - Notifications
    
    /// Posted when a membership state of a room is changed. The `Notification` contains the room id.
    public static let didChangeRoomMembershipStateNotification = Notification.Name(rawValue: "MXRoomMembershipStateDataSource.didChangeRoomMembershipState")
    
    /// The key in notification userInfo dictionary representating the roomId.
    public static let notificationUserInfoRoomIdKey = "roomId"
    
    // MARK: - Properties
    
    private var membershipStates: [String: MXMembershipChangeState] = [:]
    
    // MARK: - Public
    
    /// Update room membership change state based on MXMembership value
    /// Use this method from sync
    /// - Parameters:
    ///   - roomId: The room id
    ///   - membership: The MXMembership to base on
    public func updateState(for roomId: String, from membership: MXMembership) {
        self.updateState(for: roomId, with: self.membershipChangeState(for: membership))
    }
        
    /// Update the room membership change state with a new value
    /// - Parameters:
    ///   - roomId: The room id
    ///   - changeMembershipState: The new MXMembershipChangeState
    public func updateState(for roomId: String, with changeMembershipState: MXMembershipChangeState) {
        self.membershipStates[roomId] = changeMembershipState
        let userInfo = [MXRoomMembershipStateDataSource.notificationUserInfoRoomIdKey: roomId]
        NotificationCenter.default.post(name: MXRoomMembershipStateDataSource.didChangeRoomMembershipStateNotification, object: self, userInfo: userInfo)
    }
    
    /// Get the membership change state for the room
    /// - Parameter roomId: The room id
    /// - Returns: A MXMembershipChangeState
    public func getState(for roomId: String) -> MXMembershipChangeState {
        self.membershipStates[roomId] ?? .unknown
    }
    
    // MARK: - Private
    
    private func membershipChangeState(for membership: MXMembership) -> MXMembershipChangeState {
        
        let inviteState: MXMembershipChangeState
        
        switch membership {
        case .invite:
            inviteState = .pending
        case .join:
            inviteState = .joined
        case .leave:
            inviteState = .left
        default:
            inviteState = .unknown
        }
        
        return inviteState
    }
}
