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

internal class MockRoomSummary: NSObject, MXRoomSummaryProtocol {
    var roomId: String
    
    var roomTypeString: String?
    
    var roomType: MXRoomType = .room
    
    var avatar: String?
    
    var displayName: String?
    
    var topic: String?
    
    var creatorUserId: String = "@room_creator:some_domain.com"
    
    var aliases: [String] = []
    
    var historyVisibility: String? = nil
    
    var joinRule: String? = kMXRoomJoinRuleInvite
    
    var membership: MXMembership = .join
    
    var membershipTransitionState: MXMembershipTransitionState = .joined
    
    var membersCount: MXRoomMembersCount = MXRoomMembersCount(members: 2, joined: 2, invited: 0)
    
    var isConferenceUserRoom: Bool = false
    
    var hiddenFromUser: Bool = false
    
    var storedHash: UInt = 0
    
    var lastMessage: MXRoomLastMessage?
    
    var isEncrypted: Bool = false
    
    var trust: MXUsersTrustLevelSummary?
    
    var localUnreadEventCount: UInt = 0
    
    var notificationCount: UInt = 0
    
    var highlightCount: UInt = 0
    
    var hasAnyUnread: Bool {
        return localUnreadEventCount > 0
    }
    
    var hasAnyNotification: Bool {
        return notificationCount > 0
    }
    
    var hasAnyHighlight: Bool {
        return highlightCount > 0
    }
    
    var isDirect: Bool {
        return isTyped(.direct)
    }
    
    var directUserId: String?
    
    var others: [String: NSCoding]?
    
    var favoriteTagOrder: String?
    
    var dataTypes: MXRoomSummaryDataTypes = []
    
    func isTyped(_ types: MXRoomSummaryDataTypes) -> Bool {
        return (dataTypes.rawValue & types.rawValue) != 0
    }
    
    var sentStatus: MXRoomSummarySentStatus = .ok
    
    var spaceChildInfo: MXSpaceChildInfo?
    
    var parentSpaceIds: Set<String> = []
    
    var userIdsSharingLiveBeacon: Set<String> = []
    
    init(withRoomId roomId: String) {
        self.roomId = roomId
        super.init()
    }
    
    static func generate() -> MockRoomSummary {
        return generate(withTypes: [])
    }
    
    static func generateDirect() -> MockRoomSummary {
        return generate(withTypes: .direct)
    }
    
    static func generate(withTypes types: MXRoomSummaryDataTypes) -> MockRoomSummary {
        guard let random = MXTools.generateSecret() else {
            fatalError("Room id cannot be created")
        }
        let result = MockRoomSummary(withRoomId: "!\(random):some_domain.com")
        result.dataTypes = types
        if types.contains(.invited) {
            result.membership = .invite
            result.membershipTransitionState = .invited
        }
        return result
    }
    
    override var description: String {
        return "<MockRoomSummary: \(roomId) \(String(describing: displayName))>"
    }
}
