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

// MARK: - MXSpaceNotificationCounter notification constants
extension MXSpaceNotificationCounter {
    /// Posted once notification count for all spaces has been updated
    public static let didUpdateNotificationCount = Notification.Name("MXSpaceNotificationCounterDidUpdateNotificationCount")
}

/// MXSpaceNotificationCounter compute the number of unread messages for each space
@objcMembers
public class MXSpaceNotificationCounter: NSObject {
    
    // MARK: - Properties
    
    private unowned let session: MXSession
    
    private let processingQueue: DispatchQueue
    private let sdkProcessingQueue: DispatchQueue
    private let completionQueue: DispatchQueue

    public private(set) var homeNotificationState = MXSpaceNotificationState()
    private var notificationStatePerSpaceId: [String:MXSpaceNotificationState] = [:]

    // MARK: - Setup
    
    public init(session: MXSession) {
        self.session = session
        
        self.processingQueue = DispatchQueue(label: "org.matrix.sdk.MXSpaceNotificationCounter.processingQueue", attributes: .concurrent)
        self.completionQueue = DispatchQueue.main
        self.sdkProcessingQueue = DispatchQueue.main
        
        super.init()
    }

    // MARK: - Public
    
    /// close the service and free all data
    public func close() {
        self.homeNotificationState = MXSpaceNotificationState()
        self.notificationStatePerSpaceId = [:]
    }
    
    private class RoomInfo {
        let roomId: String
        let roomTags: [String: MXRoomTag]?
        let highlightCount: UInt
        let notificationCount: UInt
        let isDirect: Bool
        let membership: MXMembership
        
        init(with room: MXRoom) {
            self.roomId = room.roomId
            self.roomTags = room.accountData.tags
            
            let summary = room.summary
            self.highlightCount = summary?.highlightCount ?? 0
            self.notificationCount = summary?.notificationCount ?? 0
            self.isDirect = summary?.isDirect ?? false
            self.membership = summary?.membership ?? .unknown
        }
    }
    
    /// Compute the notification count for every spaces
    public func computeNotificationCount() {
        let startDate = Date()
        MXLog.debug("[MXSpaceNotificationCounter] computeNotificationCount: started")
        
        self.sdkProcessingQueue.async {
            let roomsIds: [String] = self.session.rooms.compactMap { room in
                room.roomId
            }
            
            let spaceIds: [String] = self.session.spaceService.spaceSummaries.compactMap { summary in
                summary.roomId
            }
            
            self.computeNotificationCount(for: spaceIds, with: roomsIds, at: 0, output: ComputeDataResult(), ancestorsPerRoomId: self.session.spaceService.ancestorsPerRoomId) { result in
                
                self.homeNotificationState = result.homeNotificationState
                self.notificationStatePerSpaceId = result.notificationStatePerSpaceId
                
                MXLog.debug("[MXSpaceNotificationCounter] computeNotificationCount: ended after \(Date().timeIntervalSince(startDate))s")
                
                self.completionQueue.async {
                    NotificationCenter.default.post(name: MXSpaceNotificationCounter.didUpdateNotificationCount, object: self)
                }
            }
        }
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
    
    private class ComputeDataResult {
        var homeNotificationState: MXSpaceNotificationState = MXSpaceNotificationState()
        var notificationStatePerSpaceId: [String:MXSpaceNotificationState] = [:]
    }
    
    private func computeNotificationCount(for spaceIds:[String], with roomIds:[String], at index: Int, output: ComputeDataResult, ancestorsPerRoomId: [String: Set<String>], completion: @escaping (_ result: ComputeDataResult) -> Void) {
        guard index < roomIds.count else {
            self.completionQueue.async {
                completion(output)
            }
            return
        }
        
        self.processingQueue.async {
            
            let roomId = roomIds[index]

            self.sdkProcessingQueue.async {
                var _roomInfo: RoomInfo?
                var isMentionOnly: Bool = false

                if let room = self.session.room(withRoomId: roomId), let summary = room.summary, summary.roomType != .space {
                    let roomInto = RoomInfo(with: room)
                    _roomInfo = roomInto
                    isMentionOnly = self.isRoomMentionsOnly(roomInto)
                }
                
                self.computeNotificationCount(for: spaceIds, with: roomIds, at: index, output: output, ancestorsPerRoomId: ancestorsPerRoomId, roomInfo: _roomInfo, isMentionOnly: isMentionOnly, completion: completion)
            }
        }
    }
    
    private func computeNotificationCount(for spaceIds:[String], with roomIds:[String], at index: Int, output: ComputeDataResult, ancestorsPerRoomId: [String: Set<String>], roomInfo _roomInfo: RoomInfo?, isMentionOnly: Bool, completion: @escaping (_ result: ComputeDataResult) -> Void) {
        
        self.processingQueue.async {
            guard let roomInfo = _roomInfo else {
                self.computeNotificationCount(for: spaceIds, with: roomIds, at: index + 1, output: output, ancestorsPerRoomId: ancestorsPerRoomId, completion: completion)
                return
            }
            
            let notificationState = self.notificationState(for: roomInfo, isMentionOnly: isMentionOnly)

            output.homeNotificationState += notificationState
            for spaceId in spaceIds {
                if ancestorsPerRoomId[roomInfo.roomId]?.contains(spaceId) ?? false {
                    let storedState = output.notificationStatePerSpaceId[spaceId] ?? MXSpaceNotificationState()
                    output.notificationStatePerSpaceId[spaceId] = storedState + notificationState
                }
            }

            self.computeNotificationCount(for: spaceIds, with: roomIds, at: index + 1, output: output, ancestorsPerRoomId: ancestorsPerRoomId, completion: completion)
        }
    }

    private func notificationState(for roomInfo: RoomInfo, isMentionOnly: Bool) -> MXSpaceNotificationState {
        let notificationState = MXSpaceNotificationState()
        
        let notificationCount = isMentionOnly ? roomInfo.highlightCount : roomInfo.notificationCount
        
        if notificationCount > 0 {
            let tags = roomInfo.roomTags
            if tags != nil, tags?[kMXRoomTagFavourite] != nil {
                notificationState.favouriteMissedDiscussionsCount += roomInfo.notificationCount
                notificationState.favouriteMissedDiscussionsHighlightedCount += roomInfo.highlightCount
            }
            
            if roomInfo.isDirect {
                notificationState.directMissedDiscussionsCount += roomInfo.notificationCount
                notificationState.directMissedDiscussionsHighlightedCount += roomInfo.highlightCount
            } else if tags?.isEmpty ?? true || tags?[kMXRoomTagFavourite] != nil {
                notificationState.groupMissedDiscussionsCount += roomInfo.notificationCount
                notificationState.groupMissedDiscussionsHighlightedCount += roomInfo.highlightCount
            }
        } else if roomInfo.membership == .invite {
            if roomInfo.isDirect {
                notificationState.directMissedDiscussionsCount += 1
                notificationState.directMissedDiscussionsHighlightedCount += 1
            } else {
                notificationState.groupMissedDiscussionsCount += 1
                notificationState.groupMissedDiscussionsHighlightedCount += 1
            }
        }
        
        return notificationState
    }
    
    private func isRoomMentionsOnly(_ roomInfo: RoomInfo) -> Bool {
        guard let rules = self.session.notificationCenter?.rules?.global?.room as? [MXPushRule] else {
            return false
        }
        
        for rule in rules {
            guard rule.ruleId == roomInfo.roomId, let ruleActions = rule.actions as? [MXPushRuleAction] else {
                continue
            }
            
            // Support for MSC3987: The dont_notify push rule action is deprecated.
            if rule.actions.isEmpty {
                return rule.enabled
            }

            // Compatibility support.
            for ruleAction in ruleActions where ruleAction.actionType == MXPushRuleActionTypeDontNotify {
                return rule.enabled
            }
            break
        }
        
        return false
    }
}
