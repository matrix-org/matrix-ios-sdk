/*
 Copyright 2014 OpenMarket Ltd
 Copyright 2018 New Vector Ltd
 Copyright 2019 The Matrix.org Foundation C.I.C

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
#import "MXTools.h"

#import <AVFoundation/AVFoundation.h>

#if TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>
#endif

#if defined(__IPHONE_13_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_13_0
#import <os/proc.h>
#endif

#warning File has not been annotated with nullability, see MX_ASSUME_MISSING_NULLABILITY_BEGIN

#pragma mark - Constant definition
NSString *const kMXToolsRegexStringForEmailAddress              = @"^[a-zA-Z0-9_!#$%&'*+/=?`{|}~^-]+(?:\\.[a-zA-Z0-9_!#$%&'*+/=?`{|}~^-]+)*@[a-zA-Z0-9-]+(?:\\.[a-zA-Z0-9-]+)*$";

// The HS domain part in Matrix identifiers
#define MATRIX_HOMESERVER_DOMAIN_REGEX                            @"[A-Z0-9]+((\\.|\\-)[A-Z0-9]+){0,}(:[0-9]{2,5})?"

NSString *const kMXToolsRegexStringForMatrixUserIdentifier      = @"@[\\x21-\\x39\\x3B-\\x7F]+:" MATRIX_HOMESERVER_DOMAIN_REGEX;
NSString *const kMXToolsRegexStringForMatrixRoomAlias           = @"#[A-Z0-9._%#@=+-]+:" MATRIX_HOMESERVER_DOMAIN_REGEX;
NSString *const kMXToolsRegexStringForMatrixRoomIdentifier      = @"![A-Z0-9]+:" MATRIX_HOMESERVER_DOMAIN_REGEX;
NSString *const kMXToolsRegexStringForMatrixEventIdentifier     = @"\\$[A-Z0-9]+:" MATRIX_HOMESERVER_DOMAIN_REGEX;
NSString *const kMXToolsRegexStringForMatrixEventIdentifierV3   = @"\\$[A-Z0-9\\/+]+";
NSString *const kMXToolsRegexStringForMatrixGroupIdentifier     = @"\\+[A-Z0-9=_\\-./]+:" MATRIX_HOMESERVER_DOMAIN_REGEX;


#pragma mark - MXTools static private members
// Mapping from MXEventTypeString to MXEventType and vice versa
static NSDictionary<MXEventTypeString, NSNumber *> *eventTypeMapStringToEnum;
static NSDictionary<NSNumber *, MXEventTypeString> *eventTypeMapEnumToString;

static NSRegularExpression *isEmailAddressRegex;
static NSRegularExpression *isMatrixUserIdentifierRegex;
static NSRegularExpression *isMatrixRoomAliasRegex;
static NSRegularExpression *isMatrixRoomIdentifierRegex;
static NSRegularExpression *isMatrixEventIdentifierRegex;
static NSRegularExpression *isMatrixEventIdentifierV3Regex;
static NSRegularExpression *isMatrixGroupIdentifierRegex;

// A regex to find new lines
static NSRegularExpression *newlineCharactersRegex;

static NSUInteger transactionIdCount;

// Character set to use to encode/decide URI component
NSString *const uriComponentCharsetExtra = @"-_.!~*'()";
NSCharacterSet *uriComponentCharset;


@implementation MXTools

+ (void)initialize
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        eventTypeMapEnumToString = @{
            @(MXEventTypeRoomName) : kMXEventTypeStringRoomName,
            @(MXEventTypeRoomTopic) : kMXEventTypeStringRoomTopic,
            @(MXEventTypeRoomAvatar) : kMXEventTypeStringRoomAvatar,
            @(MXEventTypeRoomBotOptions) : kMXEventTypeStringRoomBotOptions,
            @(MXEventTypeRoomMember) : kMXEventTypeStringRoomMember,
            @(MXEventTypeRoomCreate) : kMXEventTypeStringRoomCreate,
            @(MXEventTypeRoomJoinRules) : kMXEventTypeStringRoomJoinRules,
            @(MXEventTypeRoomPowerLevels) : kMXEventTypeStringRoomPowerLevels,
            @(MXEventTypeRoomAliases) : kMXEventTypeStringRoomAliases,
            @(MXEventTypeRoomCanonicalAlias) : kMXEventTypeStringRoomCanonicalAlias,
            @(MXEventTypeRoomEncrypted) : kMXEventTypeStringRoomEncrypted,
            @(MXEventTypeRoomEncryption) : kMXEventTypeStringRoomEncryption,
            @(MXEventTypeRoomGuestAccess) : kMXEventTypeStringRoomGuestAccess,
            @(MXEventTypeRoomHistoryVisibility) : kMXEventTypeStringRoomHistoryVisibility,
            @(MXEventTypeRoomKey) : kMXEventTypeStringRoomKey,
            @(MXEventTypeRoomForwardedKey) : kMXEventTypeStringRoomForwardedKey,
            @(MXEventTypeRoomKeyRequest) : kMXEventTypeStringRoomKeyRequest,
            @(MXEventTypeRoomMessage) : kMXEventTypeStringRoomMessage,
            @(MXEventTypeRoomMessageFeedback) : kMXEventTypeStringRoomMessageFeedback,
            @(MXEventTypeRoomPlumbing) : kMXEventTypeStringRoomPlumbing,
            @(MXEventTypeRoomRedaction) : kMXEventTypeStringRoomRedaction,
            @(MXEventTypeRoomThirdPartyInvite) : kMXEventTypeStringRoomThirdPartyInvite,
            @(MXEventTypeRoomRelatedGroups) : kMXEventTypeStringRoomRelatedGroups,
            @(MXEventTypeRoomPinnedEvents) : kMXEventTypeStringRoomPinnedEvents,
            @(MXEventTypeRoomTag) : kMXEventTypeStringRoomTag,
            @(MXEventTypeRoomTombStone) : kMXEventTypeStringRoomTombStone,
            
            @(MXEventTypePresence) : kMXEventTypeStringPresence,
            @(MXEventTypeTypingNotification) : kMXEventTypeStringTypingNotification,
            @(MXEventTypeReaction) : kMXEventTypeStringReaction,
            @(MXEventTypeReceipt) : kMXEventTypeStringReceipt,
            @(MXEventTypeRead) : kMXEventTypeStringRead,
            @(MXEventTypeReadMarker) : kMXEventTypeStringReadMarker,
            @(MXEventTypeSticker) : kMXEventTypeStringSticker,
            @(MXEventTypeTaggedEvents) : kMXEventTypeStringTaggedEvents,
            @(MXEventTypeSpaceChild) : kMXEventTypeStringSpaceChild,
            
            @(MXEventTypeCallInvite) : kMXEventTypeStringCallInvite,
            @(MXEventTypeCallCandidates) : kMXEventTypeStringCallCandidates,
            @(MXEventTypeCallAnswer) : kMXEventTypeStringCallAnswer,
            @(MXEventTypeCallSelectAnswer) : kMXEventTypeStringCallSelectAnswer,
            @(MXEventTypeCallHangup) : kMXEventTypeStringCallHangup,
            @(MXEventTypeCallReject) : kMXEventTypeStringCallReject,
            @(MXEventTypeCallNegotiate) : kMXEventTypeStringCallNegotiate,
            @(MXEventTypeCallReplaces) : kMXEventTypeStringCallReplaces,
            @(MXEventTypeCallRejectReplacement) : kMXEventTypeStringCallRejectReplacement,
            @(MXEventTypeCallAssertedIdentity) : kMXEventTypeStringCallAssertedIdentity,
            @(MXEventTypeCallAssertedIdentityUnstable) : kMXEventTypeStringCallAssertedIdentityUnstable,
            // MatrixRTC call events
            @(MXEventTypeCallNotify) : kMXEventTypeStringCallNotifyUnstable,
            
            @(MXEventTypeKeyVerificationRequest) : kMXEventTypeStringKeyVerificationRequest,
            @(MXEventTypeKeyVerificationReady) : kMXEventTypeStringKeyVerificationReady,
            @(MXEventTypeKeyVerificationStart) : kMXEventTypeStringKeyVerificationStart,
            @(MXEventTypeKeyVerificationAccept) : kMXEventTypeStringKeyVerificationAccept,
            @(MXEventTypeKeyVerificationKey) : kMXEventTypeStringKeyVerificationKey,
            @(MXEventTypeKeyVerificationMac) : kMXEventTypeStringKeyVerificationMac,
            @(MXEventTypeKeyVerificationCancel) : kMXEventTypeStringKeyVerificationCancel,
            @(MXEventTypeKeyVerificationDone) : kMXEventTypeStringKeyVerificationDone,
            
            @(MXEventTypeSecretRequest) : kMXEventTypeStringSecretRequest,
            @(MXEventTypeSecretSend) : kMXEventTypeStringSecretSend,
            @(MXEventTypeSecretStorageDefaultKey) : kMXEventTypeStringSecretStorageDefaultKey,
            
            @(MXEventTypePollStart) : kMXEventTypeStringPollStartMSC3381,
            @(MXEventTypePollResponse) : kMXEventTypeStringPollResponseMSC3381,
            @(MXEventTypePollEnd) : kMXEventTypeStringPollEndMSC3381,
            @(MXEventTypeBeaconInfo) : kMXEventTypeStringBeaconInfoMSC3672,
            @(MXEventTypeBeacon) : kMXEventTypeStringBeaconMSC3672,
            
            @(MXEventTypeRoomRetention): kMXEventTypeStringRoomRetention
        };

        eventTypeMapStringToEnum = @{
            kMXEventTypeStringRoomName : @(MXEventTypeRoomName),
            kMXEventTypeStringRoomTopic : @(MXEventTypeRoomTopic),
            kMXEventTypeStringRoomAvatar : @(MXEventTypeRoomAvatar),
            kMXEventTypeStringRoomBotOptions : @(MXEventTypeRoomBotOptions),
            kMXEventTypeStringRoomMember : @(MXEventTypeRoomMember),
            kMXEventTypeStringRoomCreate : @(MXEventTypeRoomCreate),
            kMXEventTypeStringRoomJoinRules : @(MXEventTypeRoomJoinRules),
            kMXEventTypeStringRoomPowerLevels : @(MXEventTypeRoomPowerLevels),
            kMXEventTypeStringRoomAliases : @(MXEventTypeRoomAliases),
            kMXEventTypeStringRoomCanonicalAlias : @(MXEventTypeRoomCanonicalAlias),
            kMXEventTypeStringRoomEncrypted : @(MXEventTypeRoomEncrypted),
            kMXEventTypeStringRoomEncryption : @(MXEventTypeRoomEncryption),
            kMXEventTypeStringRoomGuestAccess : @(MXEventTypeRoomGuestAccess),
            kMXEventTypeStringRoomHistoryVisibility : @(MXEventTypeRoomHistoryVisibility),
            kMXEventTypeStringRoomKey : @(MXEventTypeRoomKey),
            kMXEventTypeStringRoomForwardedKey : @(MXEventTypeRoomForwardedKey),
            kMXEventTypeStringRoomKeyRequest : @(MXEventTypeRoomKeyRequest),
            kMXEventTypeStringRoomMessage : @(MXEventTypeRoomMessage),
            kMXEventTypeStringRoomMessageFeedback : @(MXEventTypeRoomMessageFeedback),
            kMXEventTypeStringRoomPlumbing : @(MXEventTypeRoomPlumbing),
            kMXEventTypeStringRoomRedaction : @(MXEventTypeRoomRedaction),
            kMXEventTypeStringRoomThirdPartyInvite : @(MXEventTypeRoomThirdPartyInvite),
            kMXEventTypeStringRoomRelatedGroups : @(MXEventTypeRoomRelatedGroups),
            kMXEventTypeStringRoomPinnedEvents : @(MXEventTypeRoomPinnedEvents),
            kMXEventTypeStringRoomTag : @(MXEventTypeRoomTag),
            kMXEventTypeStringRoomTombStone : @(MXEventTypeRoomTombStone),
            
            kMXEventTypeStringPresence : @(MXEventTypePresence),
            kMXEventTypeStringTypingNotification : @(MXEventTypeTypingNotification),
            kMXEventTypeStringReaction : @(MXEventTypeReaction),
            kMXEventTypeStringReceipt : @(MXEventTypeReceipt),
            kMXEventTypeStringRead : @(MXEventTypeRead),
            kMXEventTypeStringReadMarker : @(MXEventTypeReadMarker),
            kMXEventTypeStringSticker : @(MXEventTypeSticker),
            kMXEventTypeStringTaggedEvents : @(MXEventTypeTaggedEvents),
            kMXEventTypeStringSpaceChild : @(MXEventTypeSpaceChild),
            
            kMXEventTypeStringCallInvite : @(MXEventTypeCallInvite),
            kMXEventTypeStringCallCandidates : @(MXEventTypeCallCandidates),
            kMXEventTypeStringCallAnswer : @(MXEventTypeCallAnswer),
            kMXEventTypeStringCallSelectAnswer : @(MXEventTypeCallSelectAnswer),
            kMXEventTypeStringCallHangup : @(MXEventTypeCallHangup),
            kMXEventTypeStringCallReject : @(MXEventTypeCallReject),
            kMXEventTypeStringCallNegotiate : @(MXEventTypeCallNegotiate),
            kMXEventTypeStringCallReplaces : @(MXEventTypeCallReplaces),
            kMXEventTypeStringCallRejectReplacement : @(MXEventTypeCallRejectReplacement),
            kMXEventTypeStringCallAssertedIdentity : @(MXEventTypeCallAssertedIdentity),
            kMXEventTypeStringCallAssertedIdentityUnstable : @(MXEventTypeCallAssertedIdentityUnstable),
            // MatrixRTC call events
            kMXEventTypeStringCallNotify : @(MXEventTypeCallNotify),
            kMXEventTypeStringCallNotifyUnstable : @(MXEventTypeCallNotify),
            
            kMXEventTypeStringKeyVerificationRequest : @(MXEventTypeKeyVerificationRequest),
            kMXEventTypeStringKeyVerificationReady : @(MXEventTypeKeyVerificationReady),
            kMXEventTypeStringKeyVerificationStart : @(MXEventTypeKeyVerificationStart),
            kMXEventTypeStringKeyVerificationAccept : @(MXEventTypeKeyVerificationAccept),
            kMXEventTypeStringKeyVerificationKey : @(MXEventTypeKeyVerificationKey),
            kMXEventTypeStringKeyVerificationMac : @(MXEventTypeKeyVerificationMac),
            kMXEventTypeStringKeyVerificationCancel : @(MXEventTypeKeyVerificationCancel),
            kMXEventTypeStringKeyVerificationDone : @(MXEventTypeKeyVerificationDone),
            
            kMXEventTypeStringSecretRequest : @(MXEventTypeSecretRequest),
            kMXEventTypeStringSecretSend : @(MXEventTypeSecretSend),
            kMXEventTypeStringSecretStorageDefaultKey : @(MXEventTypeSecretStorageDefaultKey),
            
            kMXEventTypeStringPollStart : @(MXEventTypePollStart),
            kMXEventTypeStringPollStartMSC3381 : @(MXEventTypePollStart),
            kMXEventTypeStringPollResponse : @(MXEventTypePollResponse),
            kMXEventTypeStringPollResponseMSC3381 : @(MXEventTypePollResponse),
            kMXEventTypeStringPollEnd : @(MXEventTypePollEnd),
            kMXEventTypeStringPollEndMSC3381 : @(MXEventTypePollEnd),
            kMXEventTypeStringBeaconInfoMSC3672 : @(MXEventTypeBeaconInfo),
            kMXEventTypeStringBeaconInfo : @(MXEventTypeBeaconInfo),
            kMXEventTypeStringBeaconMSC3672 : @(MXEventTypeBeacon),
            kMXEventTypeStringBeacon : @(MXEventTypeBeacon),
            kMXEventTypeStringRoomRetention: @(MXEventTypeRoomRetention),
        };

        isEmailAddressRegex =  [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"^%@$", kMXToolsRegexStringForEmailAddress]
                                                                         options:NSRegularExpressionCaseInsensitive error:nil];
        isMatrixUserIdentifierRegex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"^%@$", kMXToolsRegexStringForMatrixUserIdentifier]
                                                                                options:NSRegularExpressionCaseInsensitive error:nil];
        isMatrixRoomAliasRegex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"^%@$", kMXToolsRegexStringForMatrixRoomAlias]
                                                                           options:NSRegularExpressionCaseInsensitive error:nil];
        isMatrixRoomIdentifierRegex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"^%@$", kMXToolsRegexStringForMatrixRoomIdentifier]
                                                                                options:NSRegularExpressionCaseInsensitive error:nil];
        isMatrixEventIdentifierRegex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"^%@$", kMXToolsRegexStringForMatrixEventIdentifier]
                                                                                 options:NSRegularExpressionCaseInsensitive error:nil];
        isMatrixEventIdentifierV3Regex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"^%@$", kMXToolsRegexStringForMatrixEventIdentifierV3]
                                                                                 options:NSRegularExpressionCaseInsensitive error:nil];

        isMatrixGroupIdentifierRegex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"^%@$", kMXToolsRegexStringForMatrixGroupIdentifier]
                                                                                options:NSRegularExpressionCaseInsensitive error:nil];

        newlineCharactersRegex = [NSRegularExpression regularExpressionWithPattern:@" *[\n\r]+[\n\r ]*"
                                                                           options:0 error:nil];

        transactionIdCount = 0;

        // Set up charset for URI component coding
        NSMutableCharacterSet *allowedCharacterSet = [NSMutableCharacterSet alphanumericCharacterSet];
        [allowedCharacterSet addCharactersInString:uriComponentCharsetExtra];
        uriComponentCharset = allowedCharacterSet;
    });
}

+ (MXEventTypeString)eventTypeString:(MXEventType)eventType
{
    return eventTypeMapEnumToString[@(eventType)];
}

+ (MXEventType)eventType:(MXEventTypeString)eventTypeString
{
    MXEventType eventType = MXEventTypeCustom;

    NSNumber *number = [eventTypeMapStringToEnum objectForKey:eventTypeString];
    if (number)
    {
        eventType = [number unsignedIntegerValue];
    }
    return eventType;
}


+ (MXMembership)membership:(MXMembershipString)membershipString
{
    MXMembership membership = MXMembershipUnknown;
    
    if ([membershipString isEqualToString:kMXMembershipStringInvite])
    {
        membership = MXMembershipInvite;
    }
    else if ([membershipString isEqualToString:kMXMembershipStringJoin])
    {
        membership = MXMembershipJoin;
    }
    else if ([membershipString isEqualToString:kMXMembershipStringLeave])
    {
        membership = MXMembershipLeave;
    }
    else if ([membershipString isEqualToString:kMXMembershipStringBan])
    {
        membership = MXMembershipBan;
    }
    return membership;
}


+ (MXMembershipString)membershipString:(MXMembership)membership
{
    MXMembershipString membershipString;
    
    switch (membership)
    {
        case MXMembershipInvite:
            membershipString = kMXMembershipStringInvite;
            break;
            
        case MXMembershipJoin:
            membershipString = kMXMembershipStringJoin;
            break;
            
        case MXMembershipLeave:
            membershipString = kMXMembershipStringLeave;
            break;
            
        case MXMembershipBan:
            membershipString = kMXMembershipStringBan;
            break;
            
        default:
            break;
    }
    
    return membershipString;
}

+ (MXPresence)presence:(MXPresenceString)presenceString
{
    MXPresence presence = MXPresenceUnknown;
    
    // Convert presence string into enum value
    if ([presenceString isEqualToString:kMXPresenceOnline])
    {
        presence = MXPresenceOnline;
    }
    else if ([presenceString isEqualToString:kMXPresenceUnavailable])
    {
        presence = MXPresenceUnavailable;
    }
    else if ([presenceString isEqualToString:kMXPresenceOffline])
    {
        presence = MXPresenceOffline;
    }
    
    return presence;
}

+ (MXPresenceString)presenceString:(MXPresence)presence
{
    MXPresenceString presenceString;
    
    switch (presence)
    {
        case MXPresenceOnline:
            presenceString = kMXPresenceOnline;
            break;
            
        case MXPresenceUnavailable:
            presenceString = kMXPresenceUnavailable;
            break;
            
        case MXPresenceOffline:
            presenceString = kMXPresenceOffline;
            break;
            
        default:
            break;
    }
    
    return presenceString;
}

+ (MXCallHangupReason)callHangupReason:(MXCallHangupReasonString)reasonString
{
    MXCallHangupReason reason = MXCallHangupReasonUserHangup;
    
    if ([reasonString isEqualToString:kMXCallHangupReasonStringUserHangup])
    {
        reason = MXCallHangupReasonUserHangup;
    }
    else if ([reasonString isEqualToString:kMXCallHangupReasonStringIceFailed])
    {
        reason = MXCallHangupReasonIceFailed;
    }
    else if ([reasonString isEqualToString:kMXCallHangupReasonStringInviteTimeout])
    {
        reason = MXCallHangupReasonInviteTimeout;
    }
    else if ([reasonString isEqualToString:kMXCallHangupReasonStringIceTimeout])
    {
        reason = MXCallHangupReasonIceTimeout;
    }
    else if ([reasonString isEqualToString:kMXCallHangupReasonStringUserMediaFailed])
    {
        reason = MXCallHangupReasonUserMediaFailed;
    }
    else if ([reasonString isEqualToString:kMXCallHangupReasonStringUnknownError])
    {
        reason = MXCallHangupReasonUnknownError;
    }
    
    return reason;
}

+ (MXCallHangupReasonString)callHangupReasonString:(MXCallHangupReason)reason
{
    MXCallHangupReasonString string;
    
    switch (reason) 
    {
        case MXCallHangupReasonUserHangup:
            string = kMXCallHangupReasonStringUserHangup;
            break;
        case MXCallHangupReasonUserBusy:
            string = kMXCallHangupReasonStringUserBusy;
            break;
        case MXCallHangupReasonIceFailed:
            string = kMXCallHangupReasonStringIceFailed;
            break;
        case MXCallHangupReasonInviteTimeout:
            string = kMXCallHangupReasonStringInviteTimeout;
            break;
        case MXCallHangupReasonIceTimeout:
            string = kMXCallHangupReasonStringIceTimeout;
            break;
        case MXCallHangupReasonUserMediaFailed:
            string = kMXCallHangupReasonStringUserMediaFailed;
            break;
        case MXCallHangupReasonUnknownError:
            string = kMXCallHangupReasonStringUnknownError;
            break;
        default:
            break;
    }
    
    return string;
}

+ (MXCallSessionDescriptionType)callSessionDescriptionType:(MXCallSessionDescriptionTypeString)typeString
{
    MXCallSessionDescriptionType type = MXCallSessionDescriptionTypeOffer;
    
    if ([typeString isEqualToString:kMXCallSessionDescriptionTypeStringOffer])
    {
        type = MXCallSessionDescriptionTypeOffer;
    }
    else if ([typeString isEqualToString:kMXCallSessionDescriptionTypeStringPrAnswer])
    {
        type = MXCallSessionDescriptionTypePrAnswer;
    }
    else if ([typeString isEqualToString:kMXCallSessionDescriptionTypeStringAnswer])
    {
        type = MXCallSessionDescriptionTypeAnswer;
    }
    else if ([typeString isEqualToString:kMXCallSessionDescriptionTypeStringRollback])
    {
        type = MXCallSessionDescriptionTypeRollback;
    }
    
    return type;
}

+ (MXCallSessionDescriptionTypeString)callSessionDescriptionTypeString:(MXCallSessionDescriptionType)type
{
    MXCallSessionDescriptionTypeString string;
    
    switch (type)
    {
        case MXCallSessionDescriptionTypeOffer:
            string = kMXCallSessionDescriptionTypeStringOffer;
            break;
        case MXCallSessionDescriptionTypePrAnswer:
            string = kMXCallSessionDescriptionTypeStringPrAnswer;
            break;
        case MXCallSessionDescriptionTypeAnswer:
            string = kMXCallSessionDescriptionTypeStringAnswer;
            break;
        case MXCallSessionDescriptionTypeRollback:
            string = kMXCallSessionDescriptionTypeStringRollback;
            break;
    }
    
    return string;
}

+ (MXCallRejectReplacementReason)callRejectReplacementReason:(MXCallRejectReplacementReasonString)reasonString
{
    MXCallRejectReplacementReason type = MXCallRejectReplacementReasonDeclined;
    
    if ([reasonString isEqualToString:kMXCallRejectReplacementReasonStringDeclined])
    {
        type = MXCallRejectReplacementReasonDeclined;
    }
    else if ([reasonString isEqualToString:kMXCallRejectReplacementReasonStringFailedRoomInvite])
    {
        type = MXCallRejectReplacementReasonFailedRoomInvite;
    }
    else if ([reasonString isEqualToString:kMXCallRejectReplacementReasonStringFailedCallInvite])
    {
        type = MXCallRejectReplacementReasonFailedCallInvite;
    }
    else if ([reasonString isEqualToString:kMXCallRejectReplacementReasonStringFailedCall])
    {
        type = MXCallRejectReplacementReasonFailedCall;
    }
    
    return type;
}

+ (MXCallRejectReplacementReasonString)callRejectReplacementReasonString:(MXCallRejectReplacementReason)reason
{
    MXCallRejectReplacementReasonString string;
    
    switch (reason)
    {
        case MXCallRejectReplacementReasonDeclined:
            string = kMXCallRejectReplacementReasonStringDeclined;
            break;
        case MXCallRejectReplacementReasonFailedRoomInvite:
            string = kMXCallRejectReplacementReasonStringFailedRoomInvite;
            break;
        case MXCallRejectReplacementReasonFailedCallInvite:
            string = kMXCallRejectReplacementReasonStringFailedCallInvite;
            break;
        case MXCallRejectReplacementReasonFailedCall:
            string = kMXCallRejectReplacementReasonStringFailedCall;
            break;
    }
    
    return string;
}

+ (NSString *)generateSecret
{
    return [[NSProcessInfo processInfo] globallyUniqueString];
}

+ (NSString * _Nonnull)generateTransactionId
{
    return [NSString stringWithFormat:@"m%u.%tu", arc4random_uniform(INT32_MAX), transactionIdCount++];
}

+ (NSString*)stripNewlineCharacters:(NSString *)inputString
{
    NSString *string;
    if (inputString)
    {
        string = [newlineCharactersRegex stringByReplacingMatchesInString:inputString
                                                                  options:0
                                                                    range:NSMakeRange(0, inputString.length)
                                                             withTemplate:@" "];
    }
    return string;
}

+ (NSString*)addWhiteSpacesToString:(NSString *)inputString every:(NSUInteger)characters
{
    NSMutableString *whiteSpacedString = [NSMutableString new];
    for (int i = 0; i < inputString.length / characters + 1; i++)
    {
        NSUInteger fromIndex = i * characters;
        NSUInteger len = inputString.length - fromIndex;
        if (len > characters)
        {
            len = characters;
        }

        NSString *whiteFormat = @"%@ ";
        if (fromIndex + characters >= inputString.length)
        {
            whiteFormat = @"%@";
        }
        [whiteSpacedString appendFormat:whiteFormat, [inputString substringWithRange:NSMakeRange(fromIndex, len)]];
    }

    return whiteSpacedString;
}


#pragma mark - String kinds check

+ (BOOL)isEmailAddress:(NSString *)inputString
{
    if (inputString)
    {
        return (nil != [isEmailAddressRegex firstMatchInString:inputString options:0 range:NSMakeRange(0, inputString.length)]);
    }
    return NO;
}

+ (BOOL)isMatrixUserIdentifier:(NSString *)inputString
{
    if (inputString)
    {
        return (nil != [isMatrixUserIdentifierRegex firstMatchInString:inputString options:0 range:NSMakeRange(0, inputString.length)]);
    }
    return NO;
}

+ (BOOL)isMatrixRoomAlias:(NSString *)inputString
{
    if (inputString)
    {
        return (nil != [isMatrixRoomAliasRegex firstMatchInString:inputString options:0 range:NSMakeRange(0, inputString.length)]);
    }
    return NO;
}

+ (BOOL)isMatrixRoomIdentifier:(NSString *)inputString
{
    if (inputString)
    {
        return (nil != [isMatrixRoomIdentifierRegex firstMatchInString:inputString options:0 range:NSMakeRange(0, inputString.length)]);
    }
    return NO;
}

+ (BOOL)isMatrixEventIdentifier:(NSString *)inputString
{
    if (inputString)
    {
        return (nil != [isMatrixEventIdentifierRegex firstMatchInString:inputString options:0 range:NSMakeRange(0, inputString.length)])
        || (nil != [isMatrixEventIdentifierV3Regex firstMatchInString:inputString options:0 range:NSMakeRange(0, inputString.length)]);
    }
    return NO;
}

+ (BOOL)isMatrixGroupIdentifier:(NSString *)inputString
{
    if (inputString)
    {
        return (nil != [isMatrixGroupIdentifierRegex firstMatchInString:inputString options:0 range:NSMakeRange(0, inputString.length)]);
    }
    return NO;
}

+ (NSString*)serverNameInMatrixIdentifier:(NSString *)identifier
{
    // This converts something:example.org into a server domain
    //  by splitting on colons and ignoring the first entry ("something").
    return [identifier componentsSeparatedByString:@":"].lastObject;
}


#pragma mark - Strings encoding
+ (NSString *)encodeURIComponent:(NSString *)string
{
    return [string stringByAddingPercentEncodingWithAllowedCharacters:uriComponentCharset];
}


#pragma mark - Permalink

+ (NSString *)permalinkToRoom:(NSString *)roomIdOrAlias
{
    NSString *clientBaseUrl = [MXSDKOptions sharedInstance].clientPermalinkBaseUrl;
    NSString *format = clientBaseUrl != nil ? @"%@/#/room/%@" : @"%@/#/%@";
    NSString *baseUrl = clientBaseUrl != nil ? clientBaseUrl : kMXMatrixDotToUrl;
    return [NSString stringWithFormat:format, baseUrl, [MXTools encodeURIComponent:roomIdOrAlias]];
}

+ (NSString *)permalinkToEvent:(NSString *)eventId inRoom:(NSString *)roomIdOrAlias
{
    NSString *clientBaseUrl = [MXSDKOptions sharedInstance].clientPermalinkBaseUrl;
    NSString *format = clientBaseUrl != nil ? @"%@/#/room/%@/%@" : @"%@/#/%@/%@";
    NSString *baseUrl = clientBaseUrl != nil ? clientBaseUrl : kMXMatrixDotToUrl;
    return [NSString stringWithFormat:format, baseUrl, [MXTools encodeURIComponent:roomIdOrAlias], [MXTools encodeURIComponent:eventId]];
}

+ (NSString*)permalinkToUserWithUserId:(NSString*)userId
{
    NSString *clientBaseUrl = [MXSDKOptions sharedInstance].clientPermalinkBaseUrl;
    NSString *format = clientBaseUrl != nil ? @"%@/#/user/%@" : @"%@/#/%@";
    NSString *baseUrl = clientBaseUrl != nil ? clientBaseUrl : kMXMatrixDotToUrl;
    return [NSString stringWithFormat:format, baseUrl, userId];
}

#pragma mark - File

// return an array of files attributes
+ (NSArray*)listAttributesFiles:(NSString *)folderPath
{
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folderPath error:nil];
    NSEnumerator *contentsEnumurator = [contents objectEnumerator];
    
    NSString *file;
    NSMutableArray* res = [[NSMutableArray alloc] init];
    
    while (file = [contentsEnumurator nextObject])
        
    {
        NSString* itemPath = [folderPath stringByAppendingPathComponent:file];
        
        NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:itemPath error:nil];
        
        // is directory
        if ([[fileAttributes objectForKey:NSFileType] isEqual:NSFileTypeDirectory])
            
        {
            [res addObjectsFromArray:[MXTools listAttributesFiles:itemPath]];
        }
        else
            
        {
            NSMutableDictionary* att = [fileAttributes mutableCopy];
            // add the file path
            [att setObject:itemPath forKey:@"NSFilePath"];
            [res addObject:att];
        }
    }
    
    return res;
}

+ (long long)roundFileSize:(long long)filesize
{
    static long long roundedFactor = (100 * 1024);
    static long long smallRoundedFactor = (10 * 1024);
    long long roundedFileSize = filesize;
    
    if (filesize > roundedFactor)
    {
        roundedFileSize = ((filesize + (roundedFactor /2)) / roundedFactor) * roundedFactor;
    }
    else if (filesize > smallRoundedFactor)
    {
        roundedFileSize = ((filesize + (smallRoundedFactor /2)) / smallRoundedFactor) * smallRoundedFactor;
    }
    
    return roundedFileSize;
}

+ (NSString*)fileSizeToString:(long)fileSize
{
    if (fileSize < 0)
    {
        return @"";
    }
    
    NSByteCountFormatter *formatter = [NSByteCountFormatter new];
    return [formatter stringFromByteCount:fileSize];
}

+ (NSString*)fileSizeToString:(long)fileSize round:(BOOL)round
{
    if (fileSize < 0)
    {
        return @"";
    }
    else if (fileSize < 1024)
    {
        return [NSString stringWithFormat:@"%ld bytes", fileSize];
    }
    else if (fileSize < (1024 * 1024))
    {
        if (round)
        {
            return [NSString stringWithFormat:@"%.0f KB", ceil(fileSize / 1024.0)];
        }
        else
        {
            return [NSString stringWithFormat:@"%.2f KB", (fileSize / 1024.0)];
        }
    }
    else
    {
        if (round)
        {
            return [NSString stringWithFormat:@"%.0f MB", ceil(fileSize / 1024.0 / 1024.0)];
        }
        else
        {
            return [NSString stringWithFormat:@"%.2f MB", (fileSize / 1024.0 / 1024.0)];
        }
    }
}

// recursive method to compute the folder content size
+ (long long)folderSize:(NSString *)folderPath
{
    long long folderSize = 0;
    NSArray *fileAtts = [MXTools listAttributesFiles:folderPath];
    
    for(NSDictionary *fileAtt in fileAtts)
    {
        folderSize += [[fileAtt objectForKey:NSFileSize] intValue];
    }
    
    return folderSize;
}

// return the list of files by name
// isTimeSorted : the files are sorted by creation date from the oldest to the most recent one
// largeFilesFirst: move the largest file to the list head (large > 100KB). It can be combined isTimeSorted
+ (NSArray*)listFiles:(NSString *)folderPath timeSorted:(BOOL)isTimeSorted largeFilesFirst:(BOOL)largeFilesFirst
{
    NSArray* attFilesList = [MXTools listAttributesFiles:folderPath];
    
    if (attFilesList.count > 0)
    {
        
        // sorted by timestamp (oldest first)
        if (isTimeSorted)
        {
            NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"NSFileCreationDate" ascending:YES selector:@selector(compare:)];
            attFilesList = [attFilesList sortedArrayUsingDescriptors:@[ sortDescriptor]];
        }
        
        // list the large files first
        if (largeFilesFirst)
        {
            NSMutableArray* largeFilesAttList = [[NSMutableArray alloc] init];
            NSMutableArray* smallFilesAttList = [[NSMutableArray alloc] init];
            
            for (NSDictionary* att in attFilesList)
            {
                if ([[att objectForKey:NSFileSize] intValue] > 100 * 1024)
                {
                    [largeFilesAttList addObject:att];
                }
                else
                {
                    [smallFilesAttList addObject:att];
                }
            }
            
            NSMutableArray* mergedList = [[NSMutableArray alloc] init];
            [mergedList addObjectsFromArray:largeFilesAttList];
            [mergedList addObjectsFromArray:smallFilesAttList];
            attFilesList = mergedList;
        }
        
        // list filenames
        NSMutableArray* res = [[NSMutableArray alloc] init];
        for (NSDictionary* att in attFilesList)
        {
            [res addObject:[att valueForKey:@"NSFilePath"]];
        }
        
        return res;
    }
    else
    {
        return nil;
    }
}


// cache the value to improve the UX.
static NSMutableDictionary *fileExtensionByContentType = nil;

// return the file extension from a contentType
+ (NSString*)fileExtensionFromContentType:(NSString*)contentType
{
    // sanity checks
    if (!contentType || (0 == contentType.length))
    {
        return @"";
    }
    
    NSString* fileExt = nil;
    
    if (!fileExtensionByContentType)
    {
        fileExtensionByContentType  = [[NSMutableDictionary alloc] init];
    }
    
    fileExt = fileExtensionByContentType[contentType];
    
    if (!fileExt)
    {
        fileExt = @"";
        
        // else undefined type
        if ([contentType isEqualToString:@"application/jpeg"])
        {
            fileExt = @".jpg";
        }
        else if ([contentType isEqualToString:@"audio/x-alaw-basic"])
        {
            fileExt = @".alaw";
        }
        else if ([contentType isEqualToString:@"audio/x-caf"])
        {
            fileExt = @".caf";
        }
        else if ([contentType isEqualToString:@"audio/aac"])
        {
            fileExt =  @".aac";
        }
        else
        {
            CFStringRef mimeType = (__bridge CFStringRef)contentType;
            CFStringRef uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimeType, NULL);
            
            if (uti) {
                NSString* extension = (__bridge_transfer NSString *)UTTypeCopyPreferredTagWithClass(uti, kUTTagClassFilenameExtension);
            
                CFRelease(uti);
            
                if (extension)
                {
                    fileExt = [NSString stringWithFormat:@".%@", extension];
                }
            }
        }
        
        [fileExtensionByContentType setObject:fileExt forKey:contentType];
    }
    
    return fileExt;
}

#pragma mark - Video processing

+ (void)convertVideoToMP4:(NSURL*)videoLocalURL
       withTargetFileSize:(NSInteger)targetFileSize
                  success:(void(^)(NSURL *videoLocalURL, NSString *mimetype, CGSize size, double durationInMs))success
                  failure:(void(^)(NSError *error))failure
{
    AVURLAsset *videoAsset = [AVURLAsset assetWithURL:videoLocalURL];
    [self convertVideoAssetToMP4:videoAsset withTargetFileSize:targetFileSize success:success failure:failure];
}

+ (void)convertVideoAssetToMP4:(AVAsset*)videoAsset
            withTargetFileSize:(NSInteger)targetFileSize
                       success:(void(^)(NSURL *videoLocalURL, NSString *mimetype, CGSize size, double durationInMs))success
                       failure:(void(^)(NSError *error))failure
{
    NSParameterAssert(success);
    NSParameterAssert(failure);
    
    NSURL *outputVideoLocalURL;
    NSString *mimetype;
    
    // Define a random output URL in the cache foler
    NSString * outputFileName = [NSString stringWithFormat:@"%.0f.mp4",[[NSDate date] timeIntervalSince1970]];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheRoot = [paths objectAtIndex:0];
    outputVideoLocalURL = [NSURL fileURLWithPath:[cacheRoot stringByAppendingPathComponent:outputFileName]];
    
    // Convert video container to mp4 using preset from MXSDKOptions.
    NSString *presetName = [MXSDKOptions sharedInstance].videoConversionPresetName;
    AVAssetExportSession *exportSession = [AVAssetExportSession exportSessionWithAsset:videoAsset presetName:presetName];
    exportSession.outputURL = outputVideoLocalURL;
    
    if (targetFileSize > 0)
    {
        // Reduce the target file size by 10% as fileLengthLimit isn't a hard limit
        exportSession.fileLengthLimit = targetFileSize * 0.9;
    }
    
    // Check output file types supported by the device
    NSArray *supportedFileTypes = exportSession.supportedFileTypes;
    if ([supportedFileTypes containsObject:AVFileTypeMPEG4])
    {
        exportSession.outputFileType = AVFileTypeMPEG4;
        mimetype = @"video/mp4";
    }
    else
    {
        MXLogDebug(@"[MXTools] convertVideoAssetToMP4: Warning: MPEG-4 file format is not supported. Use QuickTime format.");
        
        // Fallback to QuickTime format
        exportSession.outputFileType = AVFileTypeQuickTimeMovie;
        mimetype = @"video/quicktime";
    }
    
    // Export video file
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        
        AVAssetExportSessionStatus status = exportSession.status;
        
        // Come back to the UI thread to avoid race conditions
        dispatch_async(dispatch_get_main_queue(), ^{
            
            // Check status
            if (status == AVAssetExportSessionStatusCompleted)
            {
                
                AVURLAsset* asset = [AVURLAsset URLAssetWithURL:outputVideoLocalURL
                                                        options:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                 [NSNumber numberWithBool:YES],
                                                                 AVURLAssetPreferPreciseDurationAndTimingKey,
                                                                 nil]
                                     ];
                
                double durationInMs = (1000 * CMTimeGetSeconds(asset.duration));
                
                // Extract the video size
                CGSize videoSize;
                NSArray *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
                if (videoTracks.count > 0)
                {
                    
                    AVAssetTrack *videoTrack = [videoTracks objectAtIndex:0];
                    videoSize = videoTrack.naturalSize;
                    
                    // The operation is complete
                    success(outputVideoLocalURL, mimetype, videoSize, durationInMs);
                }
                else
                {
                    
                    MXLogDebug(@"[MXTools] convertVideoAssetToMP4: Video export failed. Cannot extract video size.");
                    
                    // Remove output file (if any)
                    [[NSFileManager defaultManager] removeItemAtPath:[outputVideoLocalURL path] error:nil];
                    
                    NSError *error = [[NSError alloc] initWithDomain:AVFoundationErrorDomain code:0 userInfo:@{
                        NSLocalizedDescriptionKey: @"Unable to calculate video size."
                    }];
                    
                    failure(exportSession.error ?: error);
                }
            }
            else
            {
                
                MXLogDebug(@"[MXTools] convertVideoAssetToMP4: Video export failed. exportSession.status: %tu", status);
                
                // Remove output file (if any)
                [[NSFileManager defaultManager] removeItemAtPath:[outputVideoLocalURL path] error:nil];
                failure(exportSession.error);
            }
        });
        
    }];
}

#pragma mark - JSON Serialisation

+ (NSString*)serialiseJSONObject:(id)jsonObject
{
    NSString *jsonString;

    if ([NSJSONSerialization isValidJSONObject:jsonObject])
    {
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonObject options:0 error:nil];
        jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
    return jsonString;
}

+ (id)deserialiseJSONString:(NSString*)jsonString
{
    NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    return [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
}


#pragma mark - OS

+ (NSUInteger)memoryAvailable
{
#if defined(__IPHONE_13_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_13_0
    if (__builtin_available(iOS 13.0, *)) {
        return os_proc_available_memory();
    }
#endif
    return 0;
}


+ (BOOL)isRunningUnitTests
{
#if DEBUG
    NSDictionary* environment = [[NSProcessInfo processInfo] environment];
    return (environment[@"XCTestConfigurationFilePath"] != nil);
#else
    return NO;
#endif
}

@end
