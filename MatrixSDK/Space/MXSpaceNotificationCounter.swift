//
//  MXSpaceNotificationCounter.swift
//  MatrixSDK
//
//  Created by Gil Eluard on 19/09/2021.
//

import Foundation

@objcMembers
public class MXSpaceNotificationState: NSObject {
    public var favouriteMissedDiscussionsCount: UInt = 0
    public var favouriteMissedDiscussionsHighlightedCount: UInt = 0
    public var directMissedDiscussionsCount: UInt = 0
    public var directMissedDiscussionsHighlightedCount: UInt = 0
    public var groupMissedDiscussionsCount: UInt = 0
    public var groupMissedDiscussionsHighlightedCount: UInt = 0
    public var allCount: UInt {
        return favouriteMissedDiscussionsCount + directMissedDiscussionsCount + groupMissedDiscussionsCount
    }
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

@objcMembers
public class MXSpaceNotificationCounter: NSObject {
    
    // MARK: - Properties
    
    public var homeNotificationState = MXSpaceNotificationState()
    private var notificationStatePerSpaceId: [String:MXSpaceNotificationState] = [:]
    
    // MARK: - Public
    
    /// Compute the notification count for every spaces
    /// - Parameters:
    ///   - spaces: list of spaces of the current sessiom
    ///   - rooms: list of rooms of the current session
    ///   - flattenedParentIds: the flattened aprent ID for all rooms
    public func computeNotificationCount(for spaces:[MXSpace], with rooms:[MXRoom], flattenedParentIds: [String: Set<String>]) {
        let startDate = Date()
        MXLog.debug("[Spaces] computeNotificationCount started")

        var homeNotificationState = MXSpaceNotificationState()
        var notificationStatePerSpaceId: [String:MXSpaceNotificationState] = [:]
        
        for room in rooms {
            guard room.summary.roomType != .space else {
                continue
            }
            
            let notificationState = self.notificationState(forRoomWithId: room)
            
            homeNotificationState += notificationState
            for space in spaces {
                if flattenedParentIds[room.roomId]?.contains(space.spaceId) ?? false {
                    let storedState = notificationStatePerSpaceId[space.spaceId] ?? MXSpaceNotificationState()
                    notificationStatePerSpaceId[space.spaceId] = storedState + notificationState
                }
            }
        }
        
        self.homeNotificationState = homeNotificationState
        self.notificationStatePerSpaceId = notificationStatePerSpaceId
        
        MXLog.debug("[Spaces] computeNotificationCount ended after \(Date().timeIntervalSince(startDate))s")
    }
    
    /// Notification state for a given space
    /// - Parameters:
    ///   - spaceId: ID of the space
    /// - Returns: a `MXSpaceNotificationState` instance with the number of notifications for the given space
    public func notificationState(forSpaceWithId spaceId: String) -> MXSpaceNotificationState {
        return notificationStatePerSpaceId[spaceId] ?? MXSpaceNotificationState()
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
    
    private func notificationState(forRoomWithId room: MXRoom) -> MXSpaceNotificationState {
        let notificationState = MXSpaceNotificationState()
        guard let summary = room.summary else {
            return notificationState
        }
        
        let notificationCount = summary.notificationCount
        
        if notificationCount > 0 {
            let tags = room.accountData.tags
            if tags != nil, tags?[kMXRoomTagFavourite] != nil {
                notificationState.favouriteMissedDiscussionsCount += summary.notificationCount
                notificationState.favouriteMissedDiscussionsHighlightedCount += summary.highlightCount
            }
            
            if summary.isDirect {
                notificationState.directMissedDiscussionsCount += summary.notificationCount
                notificationState.directMissedDiscussionsHighlightedCount += summary.highlightCount
            } else if tags?.isEmpty ?? true || tags?[kMXRoomTagFavourite] != nil {
                notificationState.groupMissedDiscussionsCount += summary.notificationCount
                notificationState.groupMissedDiscussionsHighlightedCount += summary.highlightCount
            }
        } else if summary.membership == .invite {
            if room.isDirect {
                notificationState.directMissedDiscussionsHighlightedCount += 1
            } else {
                notificationState.groupMissedDiscussionsHighlightedCount += 1
            }
        }
        
        return notificationState
    }

}
