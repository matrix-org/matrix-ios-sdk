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


/// Represents a login flow
public enum MXLoginFlowType: Equatable, Hashable {
    case password
    case recaptcha
    case OAuth2
    case emailIdentity
    case token
    case dummy
    case emailCode
    case other(String)
    
    public var identifier: String {
        switch self {
        case .password: return kMXLoginFlowTypePassword
        case .recaptcha: return kMXLoginFlowTypeRecaptcha
        case .OAuth2: return kMXLoginFlowTypeOAuth2
        case .emailIdentity: return kMXLoginFlowTypeEmailIdentity
        case .token: return kMXLoginFlowTypeToken
        case .dummy: return kMXLoginFlowTypeDummy
        case .emailCode: return kMXLoginFlowTypeEmailCode
        case .other(let value): return value
        }
    }

    public init(identifier: String) {
        let flowTypess: [MXLoginFlowType] = [.password, .recaptcha, .OAuth2, .emailIdentity, .token, .dummy, .emailCode]
        self = flowTypess.first(where: { $0.identifier == identifier }) ?? .other(identifier)
    }
}




/// Represents a mode for forwarding push notifications.
public enum MXPusherKind: Equatable, Hashable {
    case http, none, custom(String)
    
    public var objectValue: NSObject {
        switch self {
        case .http: return "http" as NSString
        case .none: return NSNull()
        case .custom(let value): return value as NSString
        }
    }
}


/**
 Push rules kind.
 
 Push rules are separated into different kinds of rules. These categories have a priority order: override rules
 have the highest priority.
 Some category may define implicit conditions.
 */
public enum MXPushRuleKind: Equatable, Hashable {
    case override, content, room, sender, underride
    
    public var identifier: __MXPushRuleKind {
        switch self  {
        case .override: return __MXPushRuleKindOverride
        case .content: return __MXPushRuleKindContent
        case .room: return __MXPushRuleKindRoom
        case .sender: return __MXPushRuleKindSender
        case .underride: return __MXPushRuleKindUnderride
        }
    }

    public init?(identifier: __MXPushRuleKind?) {
        let pushRules: [MXPushRuleKind] = [.override, .content, .room, .sender, .underride]
        guard let pushRule = pushRules.first(where: { $0.identifier == identifier }) else { return nil }
        self = pushRule
    }
}

/// Push rules conditions type.
///
/// Condition kinds are exchanged as strings with the home server. The kinds of conditions
/// specified by Matrix are listed here as an enum in order to ease
/// their handling.
///
/// Custom condition kind, out of the specification, may exist. In this case,
/// `MXPushRuleConditionString` must be checked.
public enum MXPushRuleConditionType: Equatable, Hashable {
    case eventMatch
    case profileTag
    case containsDisplayName
    case roomMemberCount
    case senderNotificationPermission
    case custom(String)
    
    public var identifier: String {
        switch self  {
        case .eventMatch: return kMXPushRuleConditionStringEventMatch
        case .profileTag: return kMXPushRuleConditionStringProfileTag
        case .containsDisplayName: return kMXPushRuleConditionStringContainsDisplayName
        case .roomMemberCount: return kMXPushRuleConditionStringRoomMemberCount
        case .senderNotificationPermission: return kMXPushRuleConditionStringSenderNotificationPermission
        case .custom(let value): return value
        }
    }

    public init(identifier: String) {
        let pushRules: [MXPushRuleConditionType] = [.eventMatch, .profileTag, .containsDisplayName, .roomMemberCount, .senderNotificationPermission]
        if let pushRule = pushRules.first(where: { $0.identifier == identifier }) {
            self = pushRule
        } else {
            self = .custom(identifier)
        }
    }
}


/**
 Scope for a specific push rule.
 
 Push rules can be applied globally, or to a spefific device given a `profileTag`
 */
public enum MXPushRuleScope: Equatable, Hashable {
    case global, device(profileTag: String)
    
    public var identifier: String {
        switch self {
        case .global: return "global"
        case .device(let profileTag): return "device/\(profileTag)"
        }
    }

    public init(identifier: String) {
        let scopes: [MXPushRuleScope] = [.global]
        self = scopes.first(where: { $0.identifier == identifier }) ?? .device(profileTag: identifier)
    }
}

/// Hangup reason definitions
public enum MXCallHangupReason: Equatable, Hashable {
    case userHangup
    case iceFailed
    case inviteTimeout
    case iceTimeout
    case userMediaFailed
    case unknownError

    public var identifier: String {
        switch self {
        case .userHangup:
            return kMXCallHangupReasonStringUserHangup
        case .iceFailed:
            return kMXCallHangupReasonStringIceFailed
        case .inviteTimeout:
            return kMXCallHangupReasonStringInviteTimeout
        case .iceTimeout:
            return kMXCallHangupReasonStringIceTimeout
        case .userMediaFailed:
            return kMXCallHangupReasonStringUserMediaFailed
        case .unknownError:
            return kMXCallHangupReasonStringUnknownError
        }
    }

    public init(identifier: String) {
        let reasons: [MXCallHangupReason] = [.userHangup, .iceFailed, .inviteTimeout, .iceTimeout, .userMediaFailed, .unknownError]
        self = reasons.first(where: { $0.identifier == identifier }) ?? .userHangup
    }

}

/// Call reject replacement reason
public enum MXCallRejectReplacementReason: Equatable, Hashable {
    case declined
    case failedRoomInvite
    case failedCallInvite
    case failedCall

    public var identifier: String {
        switch self {
        case .declined:
            return kMXCallRejectReplacementReasonStringDeclined
        case .failedRoomInvite:
            return kMXCallRejectReplacementReasonStringFailedRoomInvite
        case .failedCallInvite:
            return kMXCallRejectReplacementReasonStringFailedCallInvite
        case .failedCall:
            return kMXCallRejectReplacementReasonStringFailedCall
        }
    }

    public init(identifier: String) {
        let reasons: [MXCallRejectReplacementReason] = [.declined, .failedRoomInvite, .failedCallInvite, .failedCall]
        self = reasons.first(where: { $0.identifier == identifier }) ?? .declined
    }

}
