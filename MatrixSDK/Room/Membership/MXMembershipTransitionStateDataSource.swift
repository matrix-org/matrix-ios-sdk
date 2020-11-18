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

/// `MXMembershipTransitionStateDataSource` store and notify room membership transition state
@objcMembers
public class MXMembershipTransitionStateDataSource: NSObject {
    
    // MARK: - Notifications
    
    /// Posted when a membership state of a room is changed. The `Notification` contains the room id.
    public static let didChangeRoomMembershipStateNotification = Notification.Name(rawValue: "MXMembershipTransitionStateDataSource.didChangeRoomMembershipState")
    
    /// The key in notification userInfo dictionary representating the roomId.
    public static let notificationUserInfoRoomIdKey = "roomId"
    
    // MARK: - Properties
    
    private var membershipTransitionStates: [String: MXMembershipTransitionState] = [:]
    
    // MARK: - Public
    
    /// Update room membership transition state based on MXMembership value
    /// Use this method from sync
    /// - Parameters:
    ///   - roomId: The room id
    ///   - membership: The MXMembership to base on
    public func updateState(for roomId: String, from membership: MXMembership) {
        self.updateState(for: roomId, with: self.membershipTransitionState(for: membership))
    }
        
    /// Update the room membership transition state with a new value
    /// - Parameters:
    ///   - roomId: The room id
    ///   - membershipTransitionState: The new MXMembershipChangeState
    public func updateState(for roomId: String, with membershipTransitionState: MXMembershipTransitionState) {
        self.membershipTransitionStates[roomId] = membershipTransitionState
        let userInfo = [MXMembershipTransitionStateDataSource.notificationUserInfoRoomIdKey: roomId]
        NotificationCenter.default.post(name: MXMembershipTransitionStateDataSource.didChangeRoomMembershipStateNotification, object: self, userInfo: userInfo)
    }
    
    /// Get the membership transition state for the room
    /// - Parameter roomId: The room id
    /// - Returns: A MXMembershipTransitionState
    public func getState(for roomId: String) -> MXMembershipTransitionState {
        self.membershipTransitionStates[roomId] ?? .unknown
    }
    
    // MARK: - Private
    
    private func membershipTransitionState(for membership: MXMembership) -> MXMembershipTransitionState {
        
        let transitionState: MXMembershipTransitionState
        
        switch membership {
        case .invite:
            transitionState = .pending
        case .join:
            transitionState = .joined
        case .leave:
            transitionState = .left
        default:
            transitionState = .unknown
        }
        
        return transitionState
    }
}
