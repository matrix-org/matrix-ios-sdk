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
    case callSelectAnswer
    case callHangup
    case callReject
    case callNegotiate
    case callReplaces
    case callRejectReplacement
    case callAssertedIdentity
    case callAssertedIdentityUnstable
    case reaction
    case receipt
    case roomTombStone
    case keyVerificationRequest
    case keyVerificationReady
    case keyVerificationStart
    case keyVerificationAccept
    case keyVerificationKey
    case keyVerificationMac
    case keyVerificationCancel
    case keyVerificationDone
    case secretRequest
    case secretSend
    case secretStorageDefaultKey
    case taggedEvents
    case spaceChild
    case spaceOrder
    
    case pollStart
    case pollResponse
    case pollEnd
    
    case beaconInfo
    case beacon
    case roomRetention

    case custom(String)
    
    public var identifier: String {
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
        case .callSelectAnswer: return kMXEventTypeStringCallSelectAnswer
        case .callHangup: return kMXEventTypeStringCallHangup
        case .callReject: return kMXEventTypeStringCallReject
        case .callNegotiate: return kMXEventTypeStringCallNegotiate
        case .callReplaces: return kMXEventTypeStringCallReplaces
        case .callRejectReplacement: return kMXEventTypeStringCallRejectReplacement
        case .callAssertedIdentity: return kMXEventTypeStringCallAssertedIdentity
        case .callAssertedIdentityUnstable: return kMXEventTypeStringCallAssertedIdentityUnstable
        case .reaction: return kMXEventTypeStringReaction
        case .receipt: return kMXEventTypeStringReceipt
        case .roomTombStone: return kMXEventTypeStringRoomTombStone
        case .keyVerificationRequest: return kMXEventTypeStringKeyVerificationRequest
        case .keyVerificationReady: return kMXEventTypeStringKeyVerificationReady
        case .keyVerificationStart: return kMXEventTypeStringKeyVerificationStart
        case .keyVerificationAccept: return kMXEventTypeStringKeyVerificationAccept
        case .keyVerificationKey: return kMXEventTypeStringKeyVerificationKey
        case .keyVerificationMac: return kMXEventTypeStringKeyVerificationMac
        case .keyVerificationCancel: return kMXEventTypeStringKeyVerificationCancel
        case .keyVerificationDone: return kMXEventTypeStringKeyVerificationDone
        case .secretRequest: return kMXEventTypeStringSecretRequest
        case .secretSend: return kMXEventTypeStringSecretSend
        case .secretStorageDefaultKey: return kMXEventTypeStringSecretStorageDefaultKey
        case .taggedEvents: return kMXEventTypeStringTaggedEvents
        case .spaceChild: return kMXEventTypeStringSpaceChild
        case .spaceOrder: return kMXEventTypeStringSpaceOrderMSC3230
        case .roomRetention: return kMXEventTypeStringRoomRetention
            
        case .pollStart: return kMXEventTypeStringPollStartMSC3381
        case .pollResponse: return kMXEventTypeStringPollResponseMSC3381
        case .pollEnd: return kMXEventTypeStringPollEndMSC3381
        case .beaconInfo: return kMXEventTypeStringBeaconInfoMSC3672
        case .beacon: return kMXEventTypeStringBeaconMSC3672

        // Swift converts any constant with the suffix "Notification" as the type `Notification.Name`
        // The original value can be reached using the `rawValue` property.
        case .typing: return NSNotification.Name.mxEventTypeStringTyping.rawValue
            
        case .custom(let string): return string
        }
    }
    
    public init(identifier: String) {
        let events: [MXEventType] = [.roomName, .roomTopic, .roomAvatar, .roomMember, .roomCreate, .roomJoinRules, .roomPowerLevels, .roomAliases, .roomCanonicalAlias, .roomEncrypted, .roomEncryption, .roomGuestAccess, .roomHistoryVisibility, .roomKey, .roomForwardedKey, .roomKeyRequest, .roomMessage, .roomMessageFeedback, .roomRedaction, .roomThirdPartyInvite, .roomTag, .presence, .typing, .callInvite, .callCandidates, .callAnswer, .callSelectAnswer, .callHangup, .callReject, .callNegotiate, .callReplaces, .callRejectReplacement, .callAssertedIdentity, .callAssertedIdentityUnstable, .reaction, .receipt, .roomTombStone, .keyVerificationStart, .keyVerificationAccept, .keyVerificationKey, .keyVerificationMac, .keyVerificationCancel, .keyVerificationDone, .secretRequest, .secretSend, .secretStorageDefaultKey, .taggedEvents, .spaceChild, .spaceOrder, .pollStart, .pollResponse, .pollEnd, .beaconInfo, .beacon, .roomRetention]
        
        if let type = events.first(where: { $0.identifier == identifier }) {
            self = type
        } else {
            if identifier == kMXEventTypeStringPollStart {
                self = .pollStart
            } else if identifier == kMXEventTypeStringPollResponse {
                self = .pollResponse
            } else if identifier == kMXEventTypeStringPollEnd {
                self = .pollEnd
            } else if identifier == kMXEventTypeStringSpaceOrder {
                self = .spaceOrder
            } else {
                self = .custom(identifier)
            }
        }
    }
}



/// Types of messages
public enum MXMessageType: Equatable, Hashable {
    case text, emote, notice, image, audio, video, location, file
    case custom(String)
    
    public var identifier: String {
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

    public init(identifier: String) {
        let messages: [MXMessageType] = [.text, .emote, .notice, .image, .audio, .video, .location, .file]
        self = messages.first(where: { $0.identifier == identifier }) ?? .custom(identifier)
    }
}
