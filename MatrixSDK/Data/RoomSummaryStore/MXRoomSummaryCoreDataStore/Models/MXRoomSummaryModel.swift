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
import CoreData

@objc(MXRoomSummaryModel)
public class MXRoomSummaryModel: NSManagedObject {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<MXRoomSummaryModel> {
        return NSFetchRequest<MXRoomSummaryModel>(entityName: "MXRoomSummaryModel")
    }

    @NSManaged public var identifier: String
    @NSManaged public var typeString: String?
    @NSManaged public var typeInt: Int16
    @NSManaged public var avatar: String?
    @NSManaged public var displayName: String?
    @NSManaged public var topic: String?
    @NSManaged public var creatorUserId: String?
    @NSManaged public var aliases: [String]
    @NSManaged public var membershipInt: Int16
    @NSManaged public var membershipTransitionStateInt: Int16
    @NSManaged public var isConferenceUserRoom: Bool
    @NSManaged public var others: Data?
    @NSManaged public var isEncrypted: Bool
    @NSManaged public var notificationCount: Int16
    @NSManaged public var highlightCount: Int16
    @NSManaged public var directUserId: String?
    @NSManaged public var lastMessageEventId: String?
    @NSManaged public var lastMessageDate: Date?
    @NSManaged public var isLastMessageEncrypted: Bool
    @NSManaged public var hiddenFromUser: Bool
    @NSManaged public var lastMessageData: Data?
    @NSManaged public var membersCount: MXRoomMembersCountModel?
    @NSManaged public var trust: MXUsersTrustLevelSummaryModel?
    
    internal static func from(roomSummary summary: MXRoomSummary) -> MXRoomSummaryModel {
        let model = MXRoomSummaryModel()
        
        model.identifier = summary.roomId
        model.typeString = summary.roomTypeString
        model.typeInt = Int16(summary.roomType.rawValue)
        model.avatar = summary.avatar
        model.displayName = summary.displayname
        model.topic = summary.topic
        model.creatorUserId = summary.creatorUserId
        model.aliases = summary.aliases
        model.membershipInt = Int16(summary.membership.rawValue)
        model.membershipTransitionStateInt = Int16(summary.membershipTransitionState.rawValue)
        model.isConferenceUserRoom = summary.isConferenceUserRoom
        if let others = summary.others {
            model.others = NSKeyedArchiver.archivedData(withRootObject: others)
        }
        model.isEncrypted = summary.isEncrypted
        model.notificationCount = Int16(summary.notificationCount)
        model.highlightCount = Int16(summary.highlightCount)
        model.directUserId = summary.directUserId
        model.lastMessageEventId = summary.lastMessageEventId
        model.lastMessageDate = Date(timeIntervalSince1970: TimeInterval(summary.lastMessageOriginServerTs))
        model.isLastMessageEncrypted = summary.isLastMessageEncrypted
        model.hiddenFromUser = summary.hiddenFromUser
        
        var lastMessageData: [String: Any] = [:]
        lastMessageData["lastMessageString"] = summary.lastMessageString
        lastMessageData["lastMessageAttributedString"] = summary.lastMessageAttributedString
        lastMessageData["lastMessageOthers"] = summary.lastMessageOthers
        
        if model.isLastMessageEncrypted {
            let data = NSKeyedArchiver.archivedData(withRootObject: lastMessageData)
            // TODO: encrypt data
            model.lastMessageData = data
        } else {
            model.lastMessageData = NSKeyedArchiver.archivedData(withRootObject: lastMessageData)
        }
        
        model.membersCount = MXRoomMembersCountModel.from(roomMembersCount: summary.membersCount)
        model.trust = MXUsersTrustLevelSummaryModel.from(roomUsersTrustLevelSummary: summary.trust)
        
        return model
    }
    
}
