/*
 Copyright 2017 Avery Pierce
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

import Foundation


public enum MXRoomHistoryVisibility: Equatable, Hashable {
    public typealias Identifier = String

    case worldReadable, shared, invited, joined
    
    public var identifier: Identifier {
        switch self {
        case .worldReadable: return kMXRoomHistoryVisibilityWorldReadable
        case .shared: return kMXRoomHistoryVisibilityShared
        case .invited: return kMXRoomHistoryVisibilityInvited
        case .joined: return kMXRoomHistoryVisibilityJoined
        }
    }

    private static let lookupTable: [Identifier: Self] = [
        kMXRoomHistoryVisibilityWorldReadable: .worldReadable,
        kMXRoomHistoryVisibilityShared: .shared,
        kMXRoomHistoryVisibilityInvited: .invited,
        kMXRoomHistoryVisibilityJoined: .joined,
    ]

    public init?(identifier: Identifier?) {
        guard let identifier = identifier else {
            return nil
        }
        guard let value = Self.lookupTable[identifier] else {
            return nil
        }
        self = value
    }
}



/**
 Room join rule.
 
 The default homeserver value is invite.
 */
public enum MXRoomJoinRule: Equatable, Hashable {
    public typealias Identifier = String

    /// Anyone can join the room without any prior action
    case `public`
    
    /// A user who wishes to join the room must first receive an invite to the room from someone already inside of the room.
    case invite
    
    /// Reserved keyword which is not implemented by homeservers.
    case `private`, knock
    
    public var identifier: Identifier {
        switch self {
        case .public: return kMXRoomJoinRulePublic
        case .invite: return kMXRoomJoinRuleInvite
        case .private: return kMXRoomJoinRulePrivate
        case .knock: return kMXRoomJoinRuleKnock
        }
    }

    private static let lookupTable: [Identifier: Self] = [
        kMXRoomJoinRulePublic: .public,
        kMXRoomJoinRuleInvite: .invite,
        kMXRoomJoinRulePrivate: .private,
        kMXRoomJoinRuleKnock: .knock,
    ]

    public init?(identifier: Identifier?) {
        guard let identifier = identifier else {
            return nil
        }
        guard let value = Self.lookupTable[identifier] else {
            return nil
        }
        self = value
    }
}



/// Room guest access. The default homeserver value is forbidden.
public enum MXRoomGuestAccess: Equatable, Hashable {
    public typealias Identifier = String

    /// Guests can join the room
    case canJoin
    
    /// Guest access is forbidden
    case forbidden
    
    /// String identifier
    public var identifier: String {
        switch self {
        case .canJoin: return kMXRoomGuestAccessCanJoin
        case .forbidden: return kMXRoomGuestAccessForbidden
        }
    }

    private static let lookupTable: [Identifier: Self] = [
        kMXRoomGuestAccessCanJoin: .canJoin,
        kMXRoomGuestAccessForbidden: .forbidden,
    ]

    public init?(identifier: Identifier?) {
        guard let identifier = identifier else {
            return nil
        }
        guard let value = Self.lookupTable[identifier] else {
            return nil
        }
        self = value
    }
}



/**
 Room visibility in the current homeserver directory.
 The default homeserver value is private.
 */
public enum MXRoomDirectoryVisibility: Equatable, Hashable {
    public typealias Identifier = String

    /// The room is not listed in the homeserver directory
    case `private`
    
    /// The room is listed in the homeserver directory
    case `public`
    
    public var identifier: String {
        switch self {
        case .private: return kMXRoomDirectoryVisibilityPrivate
        case .public: return kMXRoomDirectoryVisibilityPublic
        }
    }
    
    private static let lookupTable: [Identifier: Self] = [
        kMXRoomDirectoryVisibilityPrivate: .private,
        kMXRoomDirectoryVisibilityPublic: .public,
    ]

    public init?(identifier: Identifier?) {
        guard let identifier = identifier else {
            return nil
        }
        guard let value = Self.lookupTable[identifier] else {
            return nil
        }
        self = value
    }
}




/// Room presets.
/// Define a set of state events applied during a new room creation.
public enum MXRoomPreset: Equatable, Hashable {
    public typealias Identifier = String

    /// join_rules is set to invite. history_visibility is set to shared.
    case privateChat
    
    /// join_rules is set to invite. history_visibility is set to shared. All invitees are given the same power level as the room creator.
    case trustedPrivateChat
    
    /// join_rules is set to public. history_visibility is set to shared.
    case publicChat
    
    
    public var identifier: Identifier {
        switch self {
        case .privateChat: return kMXRoomPresetPrivateChat
        case .trustedPrivateChat: return kMXRoomPresetTrustedPrivateChat
        case .publicChat: return kMXRoomPresetPublicChat
        }
    }

    private static let lookupTable: [Identifier: Self] = [
        kMXRoomPresetPrivateChat: .privateChat,
        kMXRoomPresetTrustedPrivateChat: .trustedPrivateChat,
        kMXRoomPresetPublicChat: .publicChat,
    ]

    public init?(identifier: Identifier?) {
        guard let identifier = identifier else {
            return nil
        }
        guard let value = Self.lookupTable[identifier] else {
            return nil
        }
        self = value
    }
}



/**
 The direction of an event in the timeline.
 */
public enum MXTimelineDirection: Equatable, Hashable {
    public typealias Identifier = __MXTimelineDirection

    /// Forwards when the event is added to the end of the timeline.
    /// These events come from the /sync stream or from forwards pagination.
    case forwards
    
    /// Backwards when the event is added to the start of the timeline.
    /// These events come from a back pagination.
    case backwards
    
    public var identifier: __MXTimelineDirection {
        switch self {
        case .forwards: return __MXTimelineDirectionForwards
        case .backwards: return __MXTimelineDirectionBackwards
        }
    }

    private static let lookupTable: [Identifier: Self] = [
        __MXTimelineDirectionForwards: .forwards,
        __MXTimelineDirectionBackwards: .backwards,
    ]

    public init?(identifier: Identifier?) {
        guard let identifier = identifier else {
            return nil
        }
        guard let value = Self.lookupTable[identifier] else {
            return nil
        }
        self = value
    }
    
    public init(identifer _identifier: __MXTimelineDirection) {
        self = (_identifier == __MXTimelineDirectionForwards ? .forwards : .backwards)
    }
}

extension __MXTimelineDirection: Hashable {}
