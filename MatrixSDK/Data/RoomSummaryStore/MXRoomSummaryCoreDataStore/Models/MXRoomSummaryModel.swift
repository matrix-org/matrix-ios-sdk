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
    
    private enum Constants {
        static let entityName: String = "MXRoomSummaryModel"
    }
    
    internal static func typedFetchRequest() -> NSFetchRequest<MXRoomSummaryModel> {
        return NSFetchRequest<MXRoomSummaryModel>(entityName: Constants.entityName)
    }

    @NSManaged public var identifier: String
    @NSManaged public var typeString: String?
    @NSManaged public var typeInt: Int16
    @NSManaged public var avatar: String?
    @NSManaged public var displayName: String?
    @NSManaged public var topic: String?
    @NSManaged public var creatorUserId: String?
    @NSManaged public var aliases: [String]?
    @NSManaged public var membershipInt: Int16
    @NSManaged public var membershipTransitionStateInt: Int16
    @NSManaged public var isConferenceUserRoom: Bool
    @NSManaged public var others: Data?
    @NSManaged public var isEncrypted: Bool
    @NSManaged public var notificationCount: Int16
    @NSManaged public var highlightCount: Int16
    @NSManaged public var directUserId: String?
    @NSManaged public var lastMessage: Data?
    @NSManaged public var hiddenFromUser: Bool
    @NSManaged public var membersCount: MXRoomMembersCountModel?
    @NSManaged public var trust: MXUsersTrustLevelSummaryModel?
    
    internal static func from(roomSummary summary: MXRoomSummary,
                              in managedObjectContext: NSManagedObjectContext) -> MXRoomSummaryModel {
        guard let model = NSEntityDescription.insertNewObject(forEntityName: Constants.entityName,
                                                              into: managedObjectContext) as? MXRoomSummaryModel else {
            fatalError("[MXRoomSummaryModel] from: could not initialize new model")
        }
        
        model.update(withRoomSummary: summary, in: managedObjectContext)
        
        return model
    }
    
    internal func update(withRoomSummary summary: MXRoomSummary,
                         in managedObjectContext: NSManagedObjectContext) {
        identifier = summary.roomId
        typeString = summary.roomTypeString
        typeInt = Int16(summary.roomType.rawValue)
        avatar = summary.avatar
        displayName = summary.displayname
        topic = summary.topic
        creatorUserId = summary.creatorUserId
        aliases = summary.aliases
        membershipInt = Int16(summary.membership.rawValue)
        membershipTransitionStateInt = Int16(summary.membershipTransitionState.rawValue)
        isConferenceUserRoom = summary.isConferenceUserRoom
        if let others = summary.others {
            self.others = NSKeyedArchiver.archivedData(withRootObject: others)
        } else {
            self.others = nil
        }
        isEncrypted = summary.isEncrypted
        notificationCount = Int16(summary.notificationCount)
        highlightCount = Int16(summary.highlightCount)
        directUserId = summary.directUserId
        if let message = summary.lastMessage {
            lastMessage = NSKeyedArchiver.archivedData(withRootObject: message)
        } else {
            lastMessage = nil
        }
        hiddenFromUser = summary.hiddenFromUser
        
        if let membersCount = summary.membersCount {
            self.membersCount = MXRoomMembersCountModel.from(roomMembersCount: membersCount,
                                                        in: managedObjectContext)
        } else {
            membersCount = nil
        }
        if let trust = summary.trust {
            self.trust = MXUsersTrustLevelSummaryModel.from(roomUsersTrustLevelSummary: trust,
                                                            in: managedObjectContext)
        } else {
            trust = nil
        }
        
    }
    
}
