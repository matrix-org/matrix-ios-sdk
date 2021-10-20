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

internal let StringArrayDelimiter: String = ";"

@objc(MXRoomSummaryModel)
public class MXRoomSummaryModel: NSManagedObject {
    
    internal static func typedFetchRequest() -> NSFetchRequest<MXRoomSummaryModel> {
        return NSFetchRequest<MXRoomSummaryModel>(entityName: entityName)
    }

    @NSManaged public var s_identifier: String
    @NSManaged public var s_typeString: String?
    @NSManaged public var s_typeInt: Int16
    @NSManaged public var s_avatar: String?
    @NSManaged public var s_displayName: String?
    @NSManaged public var s_topic: String?
    @NSManaged public var s_creatorUserId: String
    @NSManaged public var s_aliases: String?
    @NSManaged public var s_joinRule: String?
    @NSManaged public var s_membershipInt: Int16
    @NSManaged public var s_membershipTransitionStateInt: Int16
    @NSManaged public var s_isConferenceUserRoom: Bool
    @NSManaged public var s_others: Data?
    @NSManaged public var s_isEncrypted: Bool
    @NSManaged public var s_localUnreadEventCount: Int16
    @NSManaged public var s_notificationCount: Int16
    @NSManaged public var s_highlightCount: Int16
    @NSManaged public var s_directUserId: String?
    @NSManaged public var s_hiddenFromUser: Bool
    @NSManaged public var s_storedHash: Int64
    @NSManaged public var s_favoriteTagOrder: String?
    @NSManaged public var s_dataTypesInt: Int64
    @NSManaged public var s_sentStatusInt: Int16
    @NSManaged public var s_parentSpaceIds: String?
    @NSManaged public var s_membersCount: MXRoomMembersCountModel?
    @NSManaged public var s_trust: MXUsersTrustLevelSummaryModel?
    @NSManaged public var s_lastMessage: MXRoomLastMessageModel?
    
    @discardableResult
    internal static func insert(roomSummary summary: MXRoomSummaryProtocol,
                                into moc: NSManagedObjectContext) -> MXRoomSummaryModel {
        let model = MXRoomSummaryModel(context: moc)
        
        model.update(withRoomSummary: summary, in: moc)
        
        return model
    }
    
    internal func update(withRoomSummary summary: MXRoomSummaryProtocol,
                         in moc: NSManagedObjectContext) {
        s_identifier = summary.roomId
        s_typeString = summary.roomTypeString
        s_typeInt = Int16(summary.roomType.rawValue)
        s_avatar = summary.avatar
        s_displayName = summary.displayname
        s_topic = summary.topic
        s_creatorUserId = summary.creatorUserId
        s_aliases = summary.aliases.joined(separator: StringArrayDelimiter)
        s_joinRule = summary.joinRule
        s_membershipInt = Int16(summary.membership.rawValue)
        s_membershipTransitionStateInt = Int16(summary.membershipTransitionState.rawValue)
        s_isConferenceUserRoom = summary.isConferenceUserRoom
        if let others = summary.others {
            s_others = NSKeyedArchiver.archivedData(withRootObject: others)
        } else {
            s_others = nil
        }
        s_isEncrypted = summary.isEncrypted
        s_localUnreadEventCount = Int16(summary.localUnreadEventCount)
        s_notificationCount = Int16(summary.notificationCount)
        s_highlightCount = Int16(summary.highlightCount)
        s_directUserId = summary.directUserId
        s_hiddenFromUser = summary.hiddenFromUser
        s_storedHash = Int64(summary.storedHash)
        s_favoriteTagOrder = summary.favoriteTagOrder
        s_dataTypesInt = Int64(summary.dataTypes.rawValue)
        s_sentStatusInt = Int16(summary.sentStatus.rawValue)
        s_parentSpaceIds = summary.parentSpaceIds.joined(separator: StringArrayDelimiter)
        
        if let old = s_membersCount {
            moc.delete(old)
        }
        let membersCountModel = MXRoomMembersCountModel.insert(roomMembersCount: summary.membersCount,
                                                               into: moc)
        do {
            try moc.obtainPermanentIDs(for: [membersCountModel])
        } catch {
            MXLog.error("[MXRoomSummaryModel] update: couldn't obtain permanent id for membersCount: \(error)")
        }
        s_membersCount = membersCountModel
        
        if let old = s_trust {
            moc.delete(old)
        }
        if let trust = summary.trust {
            let trustModel = MXUsersTrustLevelSummaryModel.insert(roomUsersTrustLevelSummary: trust,
                                                                  into: moc)
            do {
                try moc.obtainPermanentIDs(for: [trustModel])
            } catch {
                MXLog.error("[MXRoomSummaryModel] update: couldn't obtain permanent id for trust: \(error)")
            }
            s_trust = trustModel
        } else {
            s_trust = nil
        }
        
        if let old = s_lastMessage {
            moc.delete(old)
        }
        if let lastMessage = summary.lastMessage {
            let lastMessageModel = MXRoomLastMessageModel.insert(roomLastMessage: lastMessage,
                                                                 into: moc)
            do {
                try moc.obtainPermanentIDs(for: [lastMessageModel])
            } catch {
                MXLog.error("[MXRoomSummaryModel] update: couldn't obtain permanent id for lastMessage: \(error)")
            }
            s_lastMessage = lastMessageModel
        } else {
            s_lastMessage = nil
        }
    }
    
}

//  MARK: - MXRoomSummaryProtocol

extension MXRoomSummaryModel: MXRoomSummaryProtocol {
    public var roomId: String {
        return s_identifier
    }
    
    public var roomTypeString: String? {
        return s_typeString
    }
    
    public var roomType: MXRoomType {
        return MXRoomType(rawValue: Int(s_typeInt)) ?? .room
    }
    
    public var avatar: String? {
        return s_avatar
    }
    
    public var displayname: String? {
        return s_displayName
    }
    
    public var topic: String? {
        return s_topic
    }
    
    public var creatorUserId: String {
        return s_creatorUserId
    }
    
    public var aliases: [String] {
        return s_aliases?.components(separatedBy: StringArrayDelimiter) ?? []
    }
    
    public var joinRule: String? {
        return s_joinRule
    }
    
    public var membership: MXMembership {
        return MXMembership(rawValue: UInt(s_membershipInt)) ?? .unknown
    }
    
    public var membershipTransitionState: MXMembershipTransitionState {
        return MXMembershipTransitionState(rawValue: Int(s_membershipTransitionStateInt)) ?? .unknown
    }
    
    public var membersCount: MXRoomMembersCount {
        if let s_membersCount = s_membersCount {
            return MXRoomMembersCount(coreDataModel: s_membersCount)
        }
        return MXRoomMembersCount()
    }
    
    public var isConferenceUserRoom: Bool {
        return s_isConferenceUserRoom
    }
    
    public var hiddenFromUser: Bool {
        return s_hiddenFromUser
    }
    
    public var storedHash: UInt {
        return UInt(s_storedHash)
    }
    
    public var lastMessage: MXRoomLastMessage? {
        if let s_lastMessage = s_lastMessage {
            return MXRoomLastMessage(coreDataModel: s_lastMessage)
        }
        return nil
    }
    
    public var isEncrypted: Bool {
        return s_isEncrypted
    }
    
    public var localUnreadEventCount: UInt {
        return UInt(s_localUnreadEventCount)
    }
    
    public var notificationCount: UInt {
        return UInt(s_notificationCount)
    }
    
    public var highlightCount: UInt {
        return UInt(s_highlightCount)
    }
    
    public var isDirect: Bool {
        return s_directUserId != nil
    }
    
    public var directUserId: String? {
        return s_directUserId
    }
    
    public var others: [String : NSCoding]? {
        if let s_others = s_others {
            return NSKeyedUnarchiver.unarchiveObject(with: s_others) as? [String: NSCoding]
        }
        return nil
    }
    
    public var favoriteTagOrder: String? {
        return s_favoriteTagOrder
    }
    
    public var dataTypes: MXRoomSummaryDataTypes {
        return MXRoomSummaryDataTypes(rawValue: Int(s_dataTypesInt))
    }
    
    public func isTyped(_ types: MXRoomSummaryDataTypes) -> Bool {
        return dataTypes.contains(types)
    }
    
    public var sentStatus: MXRoomSummarySentStatus {
        return MXRoomSummarySentStatus(rawValue: UInt(s_sentStatusInt)) ?? .ok
    }
    
    public var spaceChildInfo: MXSpaceChildInfo? {
        return nil
    }
    
    public var parentSpaceIds: Set<String> {
        if let array = s_parentSpaceIds?.components(separatedBy: StringArrayDelimiter) {
            return Set<String>(array)
        }
        return []
    }
    
    public var trust: MXUsersTrustLevelSummary? {
        if let s_trust = s_trust {
            return MXUsersTrustLevelSummary(coreDataModel: s_trust)
        }
        return nil
    }
    
}
