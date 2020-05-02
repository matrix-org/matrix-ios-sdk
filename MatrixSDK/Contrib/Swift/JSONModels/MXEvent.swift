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


/**
 Types of Matrix events
 
 Matrix events types are exchanged as strings with the home server. The types
 specified by the Matrix standard are listed here as NSUInteger enum in order
 to ease the type handling.
 
 Custom events types, out of the specification, may exist. In this case,
 `MXEventTypeString` must be checked.
 */
public enum MXEventType: Equatable, Hashable {
    public typealias Identifier = String

    case roomName
    case roomTopic
    case roomAvatar
    case roomMember
    case roomCreate
    case roomJoinRules
    case roomPowerLevels
    case roomAliases
    case roomCanonicalAlias
    case roomEncrypted
    case roomEncryption
    case roomGuestAccess
    case roomHistoryVisibility
    case roomKey
    case roomForwardedKey
    case roomKeyRequest
    case roomMessage
    case roomMessageFeedback
    case roomRedaction
    case roomThirdPartyInvite
    case roomTag
    case presence
    case typing
    case callInvite
    case callCandidates
    case callAnswer
    case callHangup
    case reaction
    case receipt
    case roomTombStone
    case keyVerificationStart
    case keyVerificationAccept
    case keyVerificationKey
    case keyVerificationMac
    case keyVerificationCancel
    case keyVerificationDone

    case custom(Identifier)

    public var identifier: Identifier {
        switch self {
        case .roomName: return kMXEventTypeStringRoomName
        case .roomTopic: return kMXEventTypeStringRoomTopic
        case .roomAvatar: return kMXEventTypeStringRoomAvatar
        case .roomMember: return kMXEventTypeStringRoomMember
        case .roomCreate: return kMXEventTypeStringRoomCreate
        case .roomJoinRules: return kMXEventTypeStringRoomJoinRules
        case .roomPowerLevels: return kMXEventTypeStringRoomPowerLevels
        case .roomAliases: return kMXEventTypeStringRoomAliases
        case .roomCanonicalAlias: return kMXEventTypeStringRoomCanonicalAlias
        case .roomEncrypted: return kMXEventTypeStringRoomEncrypted
        case .roomEncryption: return kMXEventTypeStringRoomEncryption
        case .roomGuestAccess: return kMXEventTypeStringRoomGuestAccess
        case .roomHistoryVisibility: return kMXEventTypeStringRoomHistoryVisibility
        case .roomKey: return kMXEventTypeStringRoomKey
        case .roomForwardedKey: return kMXEventTypeStringRoomForwardedKey
        case .roomKeyRequest: return kMXEventTypeStringRoomKeyRequest
        case .roomMessage: return kMXEventTypeStringRoomMessage
        case .roomMessageFeedback: return kMXEventTypeStringRoomMessageFeedback
        case .roomRedaction: return kMXEventTypeStringRoomRedaction
        case .roomThirdPartyInvite: return kMXEventTypeStringRoomThirdPartyInvite
        case .roomTag: return kMXEventTypeStringRoomTag
        case .presence: return kMXEventTypeStringPresence
        case .callInvite: return kMXEventTypeStringCallInvite
        case .callCandidates: return kMXEventTypeStringCallCandidates
        case .callAnswer: return kMXEventTypeStringCallAnswer
        case .callHangup: return kMXEventTypeStringCallHangup
        case .reaction: return kMXEventTypeStringReaction
        case .receipt: return kMXEventTypeStringReceipt
        case .roomTombStone: return kMXEventTypeStringRoomTombStone
        case .keyVerificationStart: return kMXEventTypeStringKeyVerificationStart
        case .keyVerificationAccept: return kMXEventTypeStringKeyVerificationAccept
        case .keyVerificationKey: return kMXEventTypeStringKeyVerificationKey
        case .keyVerificationMac: return kMXEventTypeStringKeyVerificationMac
        case .keyVerificationCancel: return kMXEventTypeStringKeyVerificationCancel
        case .keyVerificationDone: return kMXEventTypeStringKeyVerificationDone
            
        // Swift converts any constant with the suffix "Notification" as the type `Notification.Name`
        // The original value can be reached using the `rawValue` property.
        case .typing: return NSNotification.Name.mxEventTypeStringTyping.rawValue
            
        case .custom(let string): return string
        }
    }

    private static let lookupTable: [Identifier: Self] = [
        kMXEventTypeStringRoomName: .roomName,
        kMXEventTypeStringRoomTopic: .roomTopic,
        kMXEventTypeStringRoomAvatar: .roomAvatar,
        kMXEventTypeStringRoomMember: .roomMember,
        kMXEventTypeStringRoomCreate: .roomCreate,
        kMXEventTypeStringRoomJoinRules: .roomJoinRules,
        kMXEventTypeStringRoomPowerLevels: .roomPowerLevels,
        kMXEventTypeStringRoomAliases: .roomAliases,
        kMXEventTypeStringRoomCanonicalAlias: .roomCanonicalAlias,
        kMXEventTypeStringRoomEncrypted: .roomEncrypted,
        kMXEventTypeStringRoomEncryption: .roomEncryption,
        kMXEventTypeStringRoomGuestAccess: .roomGuestAccess,
        kMXEventTypeStringRoomHistoryVisibility: .roomHistoryVisibility,
        kMXEventTypeStringRoomKey: .roomKey,
        kMXEventTypeStringRoomForwardedKey: .roomForwardedKey,
        kMXEventTypeStringRoomKeyRequest: .roomKeyRequest,
        kMXEventTypeStringRoomMessage: .roomMessage,
        kMXEventTypeStringRoomMessageFeedback: .roomMessageFeedback,
        kMXEventTypeStringRoomRedaction: .roomRedaction,
        kMXEventTypeStringRoomThirdPartyInvite: .roomThirdPartyInvite,
        kMXEventTypeStringRoomTag: .roomTag,
        kMXEventTypeStringPresence: .presence,
        kMXEventTypeStringCallInvite: .callInvite,
        kMXEventTypeStringCallCandidates: .callCandidates,
        kMXEventTypeStringCallAnswer: .callAnswer,
        kMXEventTypeStringCallHangup: .callHangup,
        kMXEventTypeStringReaction: .reaction,
        kMXEventTypeStringReceipt: .receipt,
        kMXEventTypeStringRoomTombStone: .roomTombStone,
        kMXEventTypeStringKeyVerificationStart: .keyVerificationStart,
        kMXEventTypeStringKeyVerificationAccept: .keyVerificationAccept,
        kMXEventTypeStringKeyVerificationKey: .keyVerificationKey,
        kMXEventTypeStringKeyVerificationMac: .keyVerificationMac,
        kMXEventTypeStringKeyVerificationCancel: .keyVerificationCancel,
        kMXEventTypeStringKeyVerificationDone: .keyVerificationDone,
    ]

    public init(identifier: Identifier) {
        if let value = Self.lookupTable[identifier] {
            self = value
        } else {
            self = .custom(identifier)
        }
    }
}



/// Types of messages
public enum MXMessageType: Equatable, Hashable {
    public typealias Identifier = String

    case text, emote, notice, image, audio, video, location, file
    case custom(Identifier)

    public var identifier: Identifier {
        switch self {
        case .text: return kMXMessageTypeText
        case .emote: return kMXMessageTypeEmote
        case .notice: return kMXMessageTypeNotice
        case .image: return kMXMessageTypeImage
        case .audio: return kMXMessageTypeAudio
        case .video: return kMXMessageTypeVideo
        case .location: return kMXMessageTypeLocation
        case .file: return kMXMessageTypeFile
        case .custom(let value): return value
        }
    }

    private static let lookupTable: [Identifier: Self] = [
        kMXMessageTypeText: .text,
        kMXMessageTypeEmote: .emote,
        kMXMessageTypeNotice: .notice,
        kMXMessageTypeImage: .image,
        kMXMessageTypeAudio: .audio,
        kMXMessageTypeVideo: .video,
        kMXMessageTypeLocation: .location,
        kMXMessageTypeFile: .file,
    ]

    public init(identifier: Identifier) {
        if let value = Self.lookupTable[identifier] {
            self = value
        } else {
            self = .custom(identifier)
        }
    }
}



/// Membership definitions
public enum MXMembership: Equatable, Hashable {
    public typealias Identifier = __MXMembership

    case unknown, invite, join, leave, ban

    public var identifier: Identifier {
        switch self {
        case .unknown: return __MXMembershipUnknown
        case .invite: return __MXMembershipInvite
        case .join: return __MXMembershipJoin
        case .leave: return __MXMembershipLeave
        case .ban: return __MXMembershipBan
        }
    }

    private static let lookupTable: [Identifier: Self] = [
        __MXMembershipUnknown: .unknown,
        __MXMembershipInvite: .invite,
        __MXMembershipJoin: .join,
        __MXMembershipLeave: .leave,
        __MXMembershipBan: .ban,
    ]
    
    public init(identifier: Identifier) {
        if let value = Self.lookupTable[identifier] {
            self = value
        } else {
            self = .unknown
        }
    }
}

extension __MXMembership: Hashable {}
