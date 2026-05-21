/*
 Copyright 2014 OpenMarket Ltd
 Copyright 2018 New Vector Ltd
 
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

#import "MXEvent.h"

#import "MXTools.h"
#import "MXEventDecryptionResult.h"
#import "MXEncryptedContentFile.h"
#import "MXEventRelations.h"
#import "MXEventReferenceChunk.h"
#import "MXEventContentLocation.h"

#warning File has not been annotated with nullability, see MX_ASSUME_MISSING_NULLABILITY_BEGIN

#pragma mark - Constants definitions

NSString *const kMXEventTypeStringRoomName              = @"m.room.name";
NSString *const kMXEventTypeStringRoomTopic             = @"m.room.topic";
NSString *const kMXEventTypeStringRoomAvatar            = @"m.room.avatar";
NSString *const kMXEventTypeStringRoomBotOptions        = @"m.room.bot.options";
NSString *const kMXEventTypeStringRoomMember            = @"m.room.member";
NSString *const kMXEventTypeStringRoomCreate            = @"m.room.create";
NSString *const kMXEventTypeStringRoomJoinRules         = @"m.room.join_rules";
NSString *const kMXEventTypeStringRoomPowerLevels       = @"m.room.power_levels";
NSString *const kMXEventTypeStringRoomAliases           = @"m.room.aliases";
NSString *const kMXEventTypeStringRoomCanonicalAlias    = @"m.room.canonical_alias";
NSString *const kMXEventTypeStringRoomEncrypted         = @"m.room.encrypted";
NSString *const kMXEventTypeStringRoomEncryption        = @"m.room.encryption";
NSString *const kMXEventTypeStringRoomGuestAccess       = @"m.room.guest_access";
NSString *const kMXEventTypeStringRoomHistoryVisibility = @"m.room.history_visibility";
NSString *const kMXEventTypeStringRoomKey               = @"m.room_key";
NSString *const kMXEventTypeStringRoomForwardedKey      = @"m.forwarded_room_key";
NSString *const kMXEventTypeStringRoomKeyRequest        = @"m.room_key_request";
NSString *const kMXEventTypeStringRoomMessage           = @"m.room.message";
NSString *const kMXEventTypeStringRoomMessageFeedback   = @"m.room.message.feedback";
NSString *const kMXEventTypeStringRoomPlumbing          = @"m.room.plumbing";
NSString *const kMXEventTypeStringRoomRedaction         = @"m.room.redaction";
NSString *const kMXEventTypeStringRoomThirdPartyInvite  = @"m.room.third_party_invite";
NSString *const kMXEventTypeStringRoomRelatedGroups     = @"m.room.related_groups";
NSString *const kMXEventTypeStringRoomPinnedEvents      = @"m.room.pinned_events";
NSString *const kMXEventTypeStringRoomMembership        = @"m.room_membership";
NSString *const kMXEventTypeStringRoomTag               = @"m.tag";
NSString *const kMXEventTypeStringPresence              = @"m.presence";
NSString *const kMXEventTypeStringTypingNotification    = @"m.typing";
NSString *const kMXEventTypeStringReaction              = @"m.reaction";
NSString *const kMXEventTypeStringReceipt               = @"m.receipt";
NSString *const kMXEventTypeStringRead                  = @"m.read";
NSString *const kMXEventTypeStringReadMarker            = @"m.fully_read";
NSString *const kMXEventTypeStringCallInvite            = @"m.call.invite";
NSString *const kMXEventTypeStringCallCandidates        = @"m.call.candidates";
NSString *const kMXEventTypeStringCallAnswer            = @"m.call.answer";
NSString *const kMXEventTypeStringCallSelectAnswer      = @"m.call.select_answer";
NSString *const kMXEventTypeStringCallHangup            = @"m.call.hangup";
NSString *const kMXEventTypeStringCallReject            = @"m.call.reject";
NSString *const kMXEventTypeStringCallNegotiate         = @"m.call.negotiate";
NSString *const kMXEventTypeStringCallReplaces          = @"m.call.replaces";
NSString *const kMXEventTypeStringCallRejectReplacement = @"m.call.reject_replacement";
NSString *const kMXEventTypeStringCallAssertedIdentity  = @"m.call.asserted_identity";
NSString *const kMXEventTypeStringCallAssertedIdentityUnstable  = @"org.matrix.call.asserted_identity";
NSString *const kMXEventTypeStringSticker               = @"m.sticker";
NSString *const kMXEventTypeStringRoomTombStone         = @"m.room.tombstone";
NSString *const kMXEventTypeStringKeyVerificationRequest= @"m.key.verification.request";
NSString *const kMXEventTypeStringKeyVerificationReady  = @"m.key.verification.ready";
NSString *const kMXEventTypeStringKeyVerificationStart  = @"m.key.verification.start";
NSString *const kMXEventTypeStringKeyVerificationAccept = @"m.key.verification.accept";
NSString *const kMXEventTypeStringKeyVerificationKey    = @"m.key.verification.key";
NSString *const kMXEventTypeStringKeyVerificationMac    = @"m.key.verification.mac";
NSString *const kMXEventTypeStringKeyVerificationCancel = @"m.key.verification.cancel";
NSString *const kMXEventTypeStringKeyVerificationDone   = @"m.key.verification.done";
NSString *const kMXEventTypeStringSecretRequest         = @"m.secret.request";
NSString *const kMXEventTypeStringSecretSend            = @"m.secret.send";
NSString *const kMXEventTypeStringSecretStorageDefaultKey   = @"m.secret_storage.default_key";
NSString *const kMXEventTypeStringTaggedEvents          = @"m.tagged_events";
NSString *const kMXEventTypeStringSpaceChild            = @"m.space.child";
NSString *const kMXEventTypeStringSpaceOrder            = @"m.space_order";
NSString *const kMXEventTypeStringSpaceOrderMSC3230     = @"org.matrix.msc3230.space_order";
NSString *const kMXEventTypeStringSpaceOrderKey         = @"order";

NSString *const kMXEventTypeStringAutoJoinKey           = @"auto_join";
NSString *const kMXEventTypeStringSuggestedKey          = @"suggested";

NSString *const kMXEventTypeStringPollStart           = @"m.poll.start";
NSString *const kMXEventTypeStringPollStartMSC3381    = @"org.matrix.msc3381.poll.start";
NSString *const kMXEventTypeStringPollResponse        = @"m.poll.response";
NSString *const kMXEventTypeStringPollResponseMSC3381 = @"org.matrix.msc3381.poll.response";
NSString *const kMXEventTypeStringPollEnd             = @"m.poll.end";
NSString *const kMXEventTypeStringPollEndMSC3381      = @"org.matrix.msc3381.poll.end";

NSString *const kMXEventTypeStringBeaconInfo = @"m.beacon_info";
NSString *const kMXEventTypeStringBeaconInfoMSC3672 = @"org.matrix.msc3672.beacon_info";
NSString *const kMXEventTypeStringBeacon = @"m.beacon";
NSString *const kMXEventTypeStringBeaconMSC3672 = @"org.matrix.msc3672.beacon";

NSString *const kMXMessageTypeKey                    = @"msgtype";
NSString *const kMXMessageTypeText                   = @"m.text";
NSString *const kMXMessageTypeEmote                  = @"m.emote";
NSString *const kMXMessageTypeNotice                 = @"m.notice";
NSString *const kMXMessageTypeImage                  = @"m.image";
NSString *const kMXMessageTypeAudio                  = @"m.audio";
NSString *const kMXMessageTypeVideo                  = @"m.video";
NSString *const kMXMessageTypeLocation               = @"m.location";
NSString *const kMXMessageTypeFile                   = @"m.file";
NSString *const kMXMessageTypeServerNotice           = @"m.server_notice";
NSString *const kMXEventTypeStringRoomRetention      = @"m.room.retention";
NSString *const kMXMessageTypeKeyVerificationRequest = @"m.key.verification.request";

NSString *const kMXMessageBodyKey                    = @"body";
NSString *const kMXMessageGeoURIKey                  = @"geo_uri";

NSString *const kMXEventRelationRelatesToKey         = @"m.relates_to";
NSString *const MXEventRelationTypeAnnotation        = @"m.annotation";
NSString *const MXEventRelationTypeReference         = @"m.reference";
NSString *const MXEventRelationTypeReplace           = @"m.replace";
NSString *const kMXMessageContentKeyNewContent       = @"m.new_content";
//  TODO: Replace when the MSC merged
//  https://github.com/matrix-org/matrix-doc/pull/3440
NSString *const MXEventRelationTypeThread            = @"m.thread";

NSString *const kMXToDeviceMessageId                 = @"org.matrix.msgid";

NSString *const kMXEventLocalEventIdPrefix           = @"kMXEventLocalId_";

uint64_t const kMXUndefinedTimestamp = (uint64_t)-1;

NSString *const kMXEventDidChangeSentStateNotification  = @"kMXEventDidChangeSentStateNotification";
NSString *const kMXEventDidChangeIdentifierNotification = @"kMXEventDidChangeIdentifierNotification";
NSString *const kMXEventDidDecryptNotification          = @"kMXEventDidDecryptNotification";

NSString *const kMXEventIdentifierKey                   = @"kMXEventIdentifierKey";

NSString *const kMXMessageContentKeyVoiceMessage = @"m.voice";
NSString *const kMXMessageContentKeyVoiceMessageMSC2516 = @"org.matrix.msc2516.voice";
NSString *const kMXMessageContentKeyVoiceMessageMSC3245 = @"org.matrix.msc3245.voice";

NSString *const kMXMessageContentKeyExtensibleAudio = @"m.audio";
NSString *const kMXMessageContentKeyExtensibleAudioMSC1767 = @"org.matrix.msc1767.audio";
NSString *const kMXMessageContentKeyExtensibleAudioDuration = @"duration";
NSString *const kMXMessageContentKeyExtensibleAudioWaveform = @"waveform";

NSString *const kMXMessageContentKeyExtensibleText = @"m.text";
NSString *const kMXMessageContentKeyExtensibleTextMSC1767 = @"org.matrix.msc1767.text";

NSString *const kMXMessageContentKeyExtensibleTimestamp = @"m.ts";
NSString *const kMXMessageContentKeyExtensibleTimestampMSC3488 = @"org.matrix.msc3488.ts";

NSString *const kMXMessageContentKeyExtensibleFile = @"m.file";
NSString *const kMXMessageContentKeyExtensibleFileMSC1767 = @"org.matrix.msc1767.file";
NSString *const kMXMessageContentKeyExtensibleFileSize = @"size";
NSString *const kMXMessageContentKeyExtensibleFileName = @"name";
NSString *const kMXMessageContentKeyExtensibleFileURL = @"url";
NSString *const kMXMessageContentKeyExtensibleFileMimeType = @"mimetype";

// Polls

NSString *const kMXMessageContentKeyExtensiblePollStart = @"m.poll.start";
NSString *const kMXMessageContentKeyExtensiblePollStartMSC3381 = @"org.matrix.msc3381.poll.start";

NSString *const kMXMessageContentKeyExtensiblePollResponse = @"m.poll.response";
NSString *const kMXMessageContentKeyExtensiblePollResponseMSC3381 = @"org.matrix.msc3381.poll.response";

NSString *const kMXMessageContentKeyExtensiblePollEnd = @"m.poll.end";
NSString *const kMXMessageContentKeyExtensiblePollEndMSC3381 = @"org.matrix.msc3381.poll.end";

NSString *const kMXMessageContentKeyExtensiblePollQuestion = @"question";
NSString *const kMXMessageContentKeyExtensiblePollAnswers = @"answers";
NSString *const kMXMessageContentKeyExtensiblePollAnswerId = @"id";
NSString *const kMXMessageContentKeyExtensiblePollMaxSelections = @"max_selections";
NSString *const kMXMessageContentKeyExtensiblePollKind = @"kind";

NSString *const kMXMessageContentKeyExtensiblePollKindDisclosedMSC3381 = @"org.matrix.msc3381.poll.disclosed";
NSString *const kMXMessageContentKeyExtensiblePollKindDisclosed = @"m.poll.disclosed";
NSString *const kMXMessageContentKeyExtensiblePollKindUndisclosedMSC3381 = @"org.matrix.msc3381.poll.undisclosed";
NSString *const kMXMessageContentKeyExtensiblePollKindUndisclosed = @"m.poll.undisclosed";

// Location

NSString *const kMXMessageContentKeyExtensibleLocation = @"m.location";
NSString *const kMXMessageContentKeyExtensibleLocationMSC3488 = @"org.matrix.msc3488.location";
NSString *const kMXMessageContentKeyExtensibleLocationURI = @"uri";
NSString *const kMXMessageContentKeyExtensibleLocationDescription = @"description";

// Assets

NSString *const kMXMessageContentKeyExtensibleAsset = @"m.asset";
NSString *const kMXMessageContentKeyExtensibleAssetMSC3488 = @"org.matrix.msc3488.asset";
NSString *const kMXMessageContentKeyExtensibleAssetType = @"type";
NSString *const kMXMessageContentKeyExtensibleAssetTypeUser = @"m.self";
NSString *const kMXMessageContentKeyExtensibleAssetTypePin = @"m.pin";

// Join Rules

NSString *const kMXJoinRulesContentKeyAllow = @"allow";
NSString *const kMXJoinRulesContentKeyType = @"type";
NSString *const kMXJoinRulesContentKeyRoomId = @"room_id";

// Threads support

NSString *const kMXEventTimelineMain = @"main";
NSString *const kMXEventUnthreaded = @"unthreaded";

// Matrix RTC support

NSString *const kMXEventTypeStringCallNotify = @"m.call.notify";
NSString *const kMXEventTypeStringCallNotifyUnstable = @"org.matrix.msc4075.call.notify";

#pragma mark - MXEvent
@interface MXEvent ()
{
    /**
     Curve25519 key which we believe belongs to the sender of the event.
     See `senderKey` property.
     */
    NSString *senderCurve25519Key;

    /**
     Ed25519 key which the sender of this event (for olm) or the creator of the
     megolm session (for megolm) claims to own.
     See `claimedEd25519Key` property.
     */
    NSString *claimedEd25519Key;

    /**
     Curve25519 keys of devices involved in telling us about the senderCurve25519Key
     and claimedEd25519Key.
     See `forwardingCurve25519KeyChain` property.
     */
    NSArray<NSString *> *forwardingCurve25519KeyChain;
}

@property (nonatomic, strong, readwrite) MXEventDecryptionDecoration *decryptionDecoration;

@end

@implementation MXEvent

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@: %@ - %@: %@", self.eventId, self.type, [NSDate dateWithTimeIntervalSince1970:self.originServerTs/1000], self.content];
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _ageLocalTs = -1;
        _decryptionDecoration = nil;
    }

    return self;
}

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXEvent *event = [[MXEvent alloc] init];
    if (event)
    {
        MXJSONModelSetString(event.eventId, JSONDictionary[@"event_id"]);
        MXJSONModelSetString(event.wireType, JSONDictionary[@"type"]);
        MXJSONModelSetString(event.roomId, JSONDictionary[@"room_id"]);
        MXJSONModelSetString(event.sender, JSONDictionary[@"sender"]);
        MXJSONModelSetDictionary(event.wireContent, JSONDictionary[@"content"]);
        MXJSONModelSetString(event.stateKey, JSONDictionary[@"state_key"]);
        MXJSONModelSetUInt64(event.originServerTs, JSONDictionary[@"origin_server_ts"]);
        MXJSONModelSetMXJSONModel(event.unsignedData, MXEventUnsignedData, JSONDictionary[@"unsigned"]);
        
        MXJSONModelSetString(event.redacts, JSONDictionary[@"redacts"]);

        // Data moved under unsigned
        MXJSONModelSetDictionary(event.prevContent, JSONDictionary[@"prev_content"]);
        MXJSONModelSetDictionary(event.redactedBecause, JSONDictionary[@"redacted_because"]);
        MXJSONModelSetDictionary(event.inviteRoomState, JSONDictionary[@"invite_room_state"]);
        if (JSONDictionary[@"age"])
        {
            MXJSONModelSetUInteger(event.age, JSONDictionary[@"age"]);
        }

        [event finalise];
    }

    return event;
}

/**
 Finalise the parsing of a Matrix event.
 */
- (void)finalise
{
    _wireEventType = [MXTools eventType:_wireType];
    if (MXEventTypePresence == _wireEventType)
    {
        // Workaround: Presence events provided by the home server do not contain userId
        // in the root of the JSON event object but under its content sub object.
        // Set self.userId in order to follow other events format.
        if (nil == self.sender)
        {
            // userId may be in the event content
            self.sender = self.content[@"user_id"];
        }
    }

    // Clean JSON data by removing all null values
    _wireContent = [MXJSONModel removeNullValuesInJSON:_wireContent];
    _prevContent = [MXJSONModel removeNullValuesInJSON:_prevContent];
    
    // Clean JSON data by removing non-string msgtype values
    _wireContent = [MXEvent wireContentFixingNonStringMsgtypesIn:_wireContent];
    _prevContent = [MXEvent wireContentFixingNonStringMsgtypesIn:_prevContent];
}

- (void)setSentState:(MXEventSentState)sentState
{
    if (_sentState != sentState)
    {
        _sentState = sentState;
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXEventDidChangeSentStateNotification object:self userInfo:nil];
    }
}

- (void)setEventId:(NSString *)eventId
{
    if (self.isLocalEvent && eventId && ![eventId isEqualToString:_eventId])
    {
        NSString *previousId = _eventId;
        _eventId = eventId;
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXEventDidChangeIdentifierNotification object:self userInfo:@{kMXEventIdentifierKey:previousId}];
    }
    else
    {
        // Do not post the notification here, only the temporary local events are supposed to change their id.
        _eventId = eventId;
    }
}

- (MXEventTypeString)type
{
    // Return the decrypted version if any
    return _clearEvent ? _clearEvent.wireType : _wireType;
}

- (MXEventType)eventType
{
    // Return the decrypted version if any
    return _clearEvent ? _clearEvent.wireEventType : _wireEventType;
}

- (NSDictionary<NSString *, id> *)content
{
    // Return the decrypted version if any
    return _clearEvent ? _clearEvent.wireContent : _wireContent;
}

- (void)setWireType:(MXEventTypeString)type
{
    _wireType = type;

    // Compute eventType
    _wireEventType = [MXTools eventType:_wireType];
}

- (void)setWireEventType:(MXEventType)wireEventType
{
    _wireEventType = wireEventType;
    _wireType = [MXTools eventTypeString:_wireEventType];
}

#pragma mark - Data moved to `unsigned`

- (void)setAge:(NSUInteger)age
{
    // If the age has not been stored yet in local time stamp, do it now
    if (-1 == _ageLocalTs)
    {
        _ageLocalTs = [[NSDate date] timeIntervalSince1970] * 1000 - age;
    }
}

- (NSUInteger)age
{
    NSUInteger age = 0;
    if (-1 != _ageLocalTs)
    {
        age = [[NSDate date] timeIntervalSince1970] * 1000 - _ageLocalTs;
    }
    else
    {
        age = _unsignedData.age;
    }
    return age;
}

- (NSDictionary<NSString *,id> *)prevContent
{
    return _prevContent ? _prevContent : _unsignedData.prevContent;
}

- (NSDictionary *)redactedBecause
{
    return _redactedBecause ? _redactedBecause : _unsignedData.redactedBecause;
}

- (NSArray<MXEvent *> *)inviteRoomState
{
    return _inviteRoomState ? _inviteRoomState : _unsignedData.inviteRoomState;
}

- (MXEventContentRelatesTo *)relatesTo
{
    MXEventContentRelatesTo *relatesTo;
    if (self.wireContent[kMXEventRelationRelatesToKey])
    {
        MXJSONModelSetMXJSONModel(relatesTo, MXEventContentRelatesTo, self.wireContent[kMXEventRelationRelatesToKey])
    }
    return relatesTo;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];
    if (JSONDictionary)
    {
        JSONDictionary[@"event_id"] = _eventId;
        JSONDictionary[@"type"] = _wireType;
        JSONDictionary[@"room_id"] = _roomId;
        JSONDictionary[@"sender"] = _sender;
        JSONDictionary[@"content"] = _wireContent;
        JSONDictionary[@"state_key"] = _stateKey;
        JSONDictionary[@"origin_server_ts"] = @(_originServerTs);
        JSONDictionary[@"redacts"] = _redacts;
        JSONDictionary[@"unsigned"] = _unsignedData.JSONDictionary;

        // Manage data before they moved under unsigned
        if (_prevContent)
        {
            JSONDictionary[@"prev_content"] = _prevContent;
        }
        if (_ageLocalTs != -1)
        {
            JSONDictionary[@"age"] = @(self.age);
        }
        if (_redactedBecause)
        {
            JSONDictionary[@"redacted_because"] = _redactedBecause;
        }
        if (_inviteRoomState)
        {
            JSONDictionary[@"invite_room_state"] = _inviteRoomState;
        }
    }

    return JSONDictionary;
}

- (BOOL)isState
{
    // The event is a state event if has a state_key
    return (nil != self.stateKey);
}

- (BOOL)isLocalEvent
{
    return [_eventId hasPrefix:kMXEventLocalEventIdPrefix];
}

- (BOOL)isRedactedEvent
{
    // The event is redacted if its redactedBecause is filed (with a redaction event id)
    return (self.redactedBecause != nil);
}

- (BOOL)isEmote
{
    if (self.eventType == MXEventTypeRoomMessage)
    {
        NSString *msgtype;
        MXJSONModelSetString(msgtype, self.content[kMXMessageTypeKey]);
        
        if (msgtype && [msgtype isEqualToString:kMXMessageTypeEmote])
        {
            return YES;
        }
    }
    return NO;
}

- (BOOL)isUserProfileChange
{
    // Retrieve membership
    NSString* membership;
    MXJSONModelSetString(membership, self.content[@"membership"]);
    
    NSString *prevMembership = nil;
    if (self.prevContent)
    {
        MXJSONModelSetString(prevMembership, self.prevContent[@"membership"]);
    }
    
    // Check whether the sender has updated his profile (the membership is then unchanged)
    return (prevMembership && membership && [membership isEqualToString:prevMembership]);
}

- (BOOL)isMediaAttachment
{
    if (self.eventType == MXEventTypeRoomMessage)
    {
        NSString *msgtype = self.content[kMXMessageTypeKey];
        if ([msgtype isEqualToString:kMXMessageTypeImage] || [msgtype isEqualToString:kMXMessageTypeVideo] || [msgtype isEqualToString:kMXMessageTypeAudio] || [msgtype isEqualToString:kMXMessageTypeFile])
        {
            return YES;
        }
    }
    else if (self.eventType == MXEventTypeSticker)
    {
        return YES;
    }
    return NO;
}

- (BOOL)isEditEvent
{
    return [self.relatesTo.relationType isEqualToString:MXEventRelationTypeReplace];
}

- (BOOL)isReplyEvent
{
    return self.eventType == MXEventTypeRoomMessage && self.relatesTo.inReplyTo.eventId != nil &&
    //  add condition after new thread event fallbacks
    (self.isInThread ? !self.relatesTo.isReplyFallback : YES);
}

- (BOOL)isVoiceMessage
{
    NSString *msgtype = self.content[kMXMessageTypeKey];
    return [msgtype isEqualToString:kMXMessageTypeAudio] && (self.content[kMXMessageContentKeyVoiceMessage] ||
                                                             self.content[kMXMessageContentKeyVoiceMessageMSC2516] ||
                                                             self.content[kMXMessageContentKeyVoiceMessageMSC3245]);
}

- (MXEventContentLocation *)location
{
    return [MXEventContentLocation modelFromJSON:self.content];
}

- (BOOL)contentHasBeenEdited
{
    return self.unsignedData.relations.replace != nil;
}

- (NSArray *)readReceiptEventIds
{
    NSMutableArray* list = nil;
    
    if (_wireEventType == MXEventTypeReceipt)
    {
        NSArray* eventIds = [_wireContent allKeys];
        list = [[NSMutableArray alloc] initWithCapacity:eventIds.count];
        
        for (NSString* eventId in eventIds)
        {
            NSDictionary* eventDict = [_wireContent objectForKey:eventId];
            NSDictionary* readDict = [eventDict objectForKey:kMXEventTypeStringRead];
            
            if (readDict)
            {
                [list addObject:eventId];
            }
        }
    }
    
    return list;
}

- (NSArray *)readReceiptThreadIds
{
    NSMutableArray* list = nil;
    
    if (_wireEventType == MXEventTypeReceipt)
    {
        NSArray* eventIds = [_wireContent allKeys];
        list = [[NSMutableArray alloc] initWithCapacity:eventIds.count];
        
        for (NSString* eventId in eventIds)
        {
            NSDictionary* eventDict = [_wireContent objectForKey:eventId];
            NSDictionary* readDict = [eventDict objectForKey:kMXEventTypeStringRead];
            
            if (readDict)
            {
                NSArray<NSDictionary *>* userDicts = [readDict allValues];
                
                NSString *threadId;
                for (NSDictionary *userDict in userDicts)
                {
                    threadId = userDict[@"thread_id"];
                    if (threadId)
                    {
                        break;
                    }
                }
                
                [list addObject:threadId ?: kMXEventUnthreaded];
            }
        }
    }
    
    return list;
}

- (NSArray *)readReceiptSenders
{
    NSMutableArray* list = nil;
    
    if (_wireEventType == MXEventTypeReceipt)
    {
        NSArray* eventIds = [_wireContent allKeys];
        list = [[NSMutableArray alloc] initWithCapacity:eventIds.count];
        
        for(NSString* eventId in eventIds)
        {
            NSDictionary* eventDict = [_wireContent objectForKey:eventId];
            NSDictionary* readDict = [eventDict objectForKey:kMXEventTypeStringRead];
            
            if (readDict)
            {
                NSArray* userIds = [readDict allKeys];
                
                for(NSString* userId in userIds)
                {
                    if ([list indexOfObject:userId] == NSNotFound)
                    {
                        [list addObject:userId];
                    }
                }
            }
        }
    }
    
    return list;
}

- (MXEvent*)prune
{
    // Filter in event by keeping only the following keys
    NSArray *allowedKeys = @[@"event_id",
                             @"sender",
                             @"user_id",
                             @"room_id",
                             @"hashes",
                             @"signatures",
                             @"type",
                             @"state_key",
                             @"depth",
                             @"prev_events",
                             @"prev_state",
                             @"auth_events",
                             @"origin",
                             @"origin_server_ts"];
    NSMutableDictionary *prunedEventDict = [self filterInEventWithKeys:allowedKeys];
    
    // Add filtered content, allowed keys in content depends on the event type
    switch (_wireEventType)
    {
        case MXEventTypeRoomMember:
        {
            allowedKeys = @[@"membership"];
            break;
        }
            
        case MXEventTypeRoomCreate:
        {
            allowedKeys = @[@"creator"];
            break;
        }
            
        case MXEventTypeRoomJoinRules:
        {
            allowedKeys = @[@"join_rule"];
            break;
        }
            
        case MXEventTypeRoomPowerLevels:
        {
            allowedKeys = @[@"users",
                            @"users_default",
                            @"events",
                            @"events_default",
                            @"state_default",
                            @"ban",
                            @"kick",
                            @"redact",
                            @"invite"];
            break;
        }
            
        case MXEventTypeRoomAliases:
        {
            allowedKeys = @[@"aliases"];
            break;
        }
            
        case MXEventTypeRoomCanonicalAlias:
        {
            allowedKeys = @[@"alias"];
            break;
        }
            
        case MXEventTypeRoomMessageFeedback:
        {
            allowedKeys = @[@"type", @"target_event_id"];
            break;
        }
            
        default:
            allowedKeys = nil;
            break;
    }
    [prunedEventDict setObject:[self filterInContentWithKeys:allowedKeys] forKey:@"content"];
    
    // Add filtered prevContent (if any)
    if (self.prevContent)
    {
        [prunedEventDict setObject:[self filterInPrevContentWithKeys:allowedKeys] forKey:@"prev_content"];
    }
    
    // Note: Contrary to server, we ignore here the "unsigned" event level key.
    
    return [MXEvent modelFromJSON:prunedEventDict];
}

- (MXEvent*)editedEventFromReplacementEvent:(MXEvent*)replaceEvent
{
    MXEvent *editedEvent;
    MXEvent *event = self;
    NSDictionary *newContentDict;
    MXJSONModelSetDictionary(newContentDict, replaceEvent.content[kMXMessageContentKeyNewContent])
    NSDictionary *oldRelatesTo = self.relatesTo.JSONDictionary;
    
    MXEventDecryptionResult *replaceEventDecryptionResult;

    NSMutableDictionary *editedEventDict;
    if (replaceEvent.isEncrypted)
    {
        // For e2e, use the encrypted content from the replace event
        editedEventDict = [event.JSONDictionary mutableCopy];
        NSMutableDictionary *editedEventContentDict = [replaceEvent.wireContent mutableCopy];
        [editedEventContentDict removeObjectForKey:kMXEventRelationRelatesToKey];
        if (oldRelatesTo)
        {
            editedEventContentDict[kMXEventRelationRelatesToKey] = oldRelatesTo;
        }
        editedEventDict[@"content"] = editedEventContentDict;
        
        // Reuse its decryption data
        replaceEventDecryptionResult = [replaceEvent decryptionResult];
    }
    else if (newContentDict)
    {
        editedEventDict = [event.JSONDictionary mutableCopy];
        NSMutableDictionary *editedEventContentDict = [editedEventDict[@"content"] mutableCopy];
        editedEventContentDict[kMXMessageBodyKey] = newContentDict[kMXMessageBodyKey];
        editedEventContentDict[@"formatted_body"] = newContentDict[@"formatted_body"];
        editedEventContentDict[@"format"] = newContentDict[@"format"];
        editedEventContentDict[kMXEventTypeStringPollStart] = newContentDict[kMXEventTypeStringPollStart];
        editedEventContentDict[kMXEventTypeStringPollStartMSC3381] = newContentDict[kMXEventTypeStringPollStartMSC3381];
        editedEventDict[@"content"] = editedEventContentDict;
    }

    if (editedEventDict)
    {
        // Use the same type as the replace event
        // This is useful for local echoes in e2e room as local echoes are always non encrypted/
        // So, there are switching between "m.room.encrypted" and "m.room.message"
        editedEventDict[@"type"] = replaceEvent.isEncrypted ? @"m.room.encrypted" : replaceEvent.type;

        NSDictionary *replaceEventDict = @{ @"event_id": replaceEvent.eventId };
        
        if (event.unsignedData.relations)
        {
            editedEventDict[@"unsigned"][@"m.relations"][MXEventRelationTypeReplace] = replaceEventDict;
        }
        else if (event.unsignedData)
        {
            editedEventDict[@"unsigned"][@"m.relations"] = @{
                MXEventRelationTypeReplace: replaceEventDict
            };
        }
        else
        {
            editedEventDict[@"unsigned"] = @{
                @"m.relations": @{
                    MXEventRelationTypeReplace: replaceEventDict
                }
            };
        }
        
        editedEvent = [MXEvent modelFromJSON:editedEventDict];
        
        if (replaceEventDecryptionResult)
        {
            [editedEvent setClearData:replaceEventDecryptionResult];
        }
    }
    
    return editedEvent;
}

- (MXEvent*)eventWithNewReferenceRelation:(MXEvent*)referenceEvent
{
    MXEvent *newEvent;

    MXEventReferenceChunk *references = self.unsignedData.relations.reference;
    NSMutableArray<MXEventReference*> *newChunk = [references.chunk mutableCopy] ?: [NSMutableArray new];

    MXEventReference *newReference = [[MXEventReference alloc] initWithEventId:referenceEvent.eventId type:referenceEvent.type];
    [newChunk addObject:newReference];

    MXEventReferenceChunk *newReferences = [[MXEventReferenceChunk alloc] initWithChunk:newChunk
                                                                                  count:references.count + 1
                                                                                limited:references.limited];

    NSDictionary *newReferenceDict = newReferences.JSONDictionary;

    NSMutableDictionary *newEventDict = [self.JSONDictionary mutableCopy];
    if (self.unsignedData.relations)
    {
        newEventDict[@"unsigned"][@"m.relations"][MXEventRelationTypeReference] = newReferenceDict;
    }
    else if (self.unsignedData)
    {
        newEventDict[@"unsigned"][@"m.relations"] = @{
            MXEventRelationTypeReference: newReferenceDict
        };
    }
    else
    {
        newEventDict[@"unsigned"] = @{
            @"m.relations": @{
                MXEventRelationTypeReference: newReferenceDict
            }
        };
    }

    newEvent = [MXEvent modelFromJSON:newEventDict];
    
    if (self.isEncrypted)
    {
        [newEvent setClearData:[self decryptionResult]];
    }
    
    return newEvent;
}

- (NSComparisonResult)compareOriginServerTs:(MXEvent *)otherEvent
{
    NSComparisonResult result = NSOrderedAscending;
    if (otherEvent.originServerTs > _originServerTs)
    {
        result = NSOrderedDescending;
    }
    else if (otherEvent.originServerTs == _originServerTs)
    {
        result = NSOrderedSame;
    }
    return result;
}

- (NSArray<NSString*>*)getMediaURLs
{
    NSMutableArray<NSString*> *mediaURLs = [NSMutableArray new];
    
    if ([self.type isEqualToString:kMXEventTypeStringRoomMessage])
    {
        NSString *messageType;
        MXJSONModelSetString(messageType, self.content[kMXMessageTypeKey])
        
        if ([messageType isEqualToString:kMXMessageTypeImage] || [messageType isEqualToString:kMXMessageTypeVideo])
        {
            NSString *mediaURL;
            NSString *mediaThumbnailURL;
            
            NSDictionary *info;
            MXJSONModelSetDictionary(info, self.content[@"info"]);
            
            if (self.isEncrypted)
            {
                NSDictionary *file;
                MXJSONModelSetDictionary(file, self.content[@"file"]);
                
                MXJSONModelSetString(mediaURL, file[@"url"]);
                
                NSDictionary *thubmnailFile;
                MXJSONModelSetDictionary(thubmnailFile, info[@"thumbnail_file"]);
                
                if (thubmnailFile)
                {
                    MXJSONModelSetString(mediaThumbnailURL, thubmnailFile[@"url"]);
                }
            }
            else
            {
                MXJSONModelSetString(mediaURL, self.content[@"url"]);
                MXJSONModelSetString(mediaThumbnailURL, info[@"thumbnail_url"]);
            }
            
            if (mediaURL)
            {
                [mediaURLs addObject:mediaURL];
            }
            
            if (mediaThumbnailURL)
            {
                [mediaURLs addObject:mediaThumbnailURL];
            }
        }
        else if ([messageType isEqualToString:kMXMessageTypeFile] || [messageType isEqualToString:kMXMessageTypeAudio])
        {
            NSString *mediaURL;
            
            if (self.isEncrypted)
            {
                NSDictionary *file;
                MXJSONModelSetDictionary(file, self.content[@"file"]);
                MXJSONModelSetString(mediaURL, file[@"url"]);
            }
            else
            {
                MXJSONModelSetString(mediaURL, self.content[@"url"]);
            }
            
            if (mediaURL)
            {
                [mediaURLs addObject:mediaURL];
            }
        }
    }
    else if ([self.type isEqualToString:kMXEventTypeStringSticker])
    {
        NSString *mediaURL;
        NSString *mediaThumbnailURL;
        
        NSDictionary *info;
        MXJSONModelSetDictionary(info, self.content[@"info"]);
        
        if (self.isEncrypted)
        {
            NSDictionary *file;
            MXJSONModelSetDictionary(file, self.content[@"file"]);
            
            MXJSONModelSetString(mediaURL, file[@"url"]);
            
            NSDictionary *thubmnailFile;
            MXJSONModelSetDictionary(thubmnailFile, info[@"thumbnail_file"]);
            
            if (thubmnailFile)
            {
                MXJSONModelSetDictionary(mediaThumbnailURL, thubmnailFile[@"url"]);
            }
        }
        else
        {
            MXJSONModelSetString(mediaURL, self.content[@"url"]);
            MXJSONModelSetString(mediaThumbnailURL, info[@"thumbnail_url"]);
        }
        
        if (mediaURL)
        {
            [mediaURLs addObject:mediaURL];
        }
        
        if (mediaThumbnailURL)
        {
            [mediaURLs addObject:mediaThumbnailURL];
        }
    }
    
    return mediaURLs;
}

- (BOOL)isContentScannable
{
    return [self getMediaURLs].count != 0;
}

#pragma mark - Threading

- (BOOL)isInThread
{
    return [self.relatesTo.relationType isEqualToString:MXEventRelationTypeThread];
}

- (NSString *)threadId
{
    if (self.isInThread)
    {
        return self.relatesTo.eventId;
    }
    return nil;
}

#pragma mark - Crypto
- (BOOL)isEncrypted
{
    return (self.wireEventType == MXEventTypeRoomEncrypted);
}

- (void)setClearData:(MXEventDecryptionResult *)decryptionResult
{
    _clearEvent = nil;
    
    if (decryptionResult.error)
    {
        _decryptionError = decryptionResult.error;
        return;
    }
    
    if (decryptionResult.clearEvent)
    {
        NSDictionary *clearEventJSON, *clearEventJSONContent;
        MXJSONModelSetDictionary(clearEventJSON, decryptionResult.clearEvent);
        MXJSONModelSetDictionary(clearEventJSONContent, clearEventJSON[@"content"]);

        if (clearEventJSONContent[kMXMessageContentKeyNewContent] && !_wireContent[kMXEventRelationRelatesToKey])
        {
            // If the event has been edited, use the new content
            // This can be done only on client side
            // TODO: Remove this with the coming update of MSC1849.
            NSDictionary *clearEventJSONNewContent;
            MXJSONModelSetDictionary(clearEventJSONNewContent, clearEventJSONContent[kMXMessageContentKeyNewContent]);
            
            if (clearEventJSONNewContent)
            {
                NSMutableDictionary *clearEventUpdatedJSON = [clearEventJSON mutableCopy];
                clearEventUpdatedJSON[@"content"] = clearEventJSONNewContent;
                clearEventJSON = clearEventUpdatedJSON;
            }
        }

        NSDictionary *decryptionClearEventJSON;
        NSDictionary *encryptedContentRelatesToJSON;
        MXJSONModelSetDictionary(encryptedContentRelatesToJSON, _wireContent[kMXEventRelationRelatesToKey]);
        
        // Add "m.relates_to" data from e2e event to the unencrypted content event
        if (encryptedContentRelatesToJSON)
        {
            NSMutableDictionary *decryptionClearEventUpdatedJSON = [clearEventJSON mutableCopy];
            NSMutableDictionary *clearEventContentUpdatedJSON = [decryptionClearEventUpdatedJSON[@"content"] mutableCopy];
            
            clearEventContentUpdatedJSON[kMXEventRelationRelatesToKey] = encryptedContentRelatesToJSON;
            decryptionClearEventUpdatedJSON[@"content"] = [clearEventContentUpdatedJSON copy];
            decryptionClearEventJSON = [decryptionClearEventUpdatedJSON copy];
        }
        else
        {
            decryptionClearEventJSON = clearEventJSON;
        }
        
        _clearEvent = [MXEvent modelFromJSON:decryptionClearEventJSON];
    }

    if (_clearEvent)
    {
        _clearEvent->senderCurve25519Key = decryptionResult.senderCurve25519Key;
        _clearEvent->claimedEd25519Key = decryptionResult.claimedEd25519Key;
        _clearEvent->forwardingCurve25519KeyChain = decryptionResult.forwardingCurve25519KeyChain ? decryptionResult.forwardingCurve25519KeyChain : @[];
        _clearEvent.decryptionDecoration = decryptionResult.decoration;
    }

    // Notify only for events that are lately decrypted
    BOOL notify = (_decryptionError != nil);

    // Reset previous decryption error
    _decryptionError = nil;

    if (notify)
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXEventDidDecryptNotification object:self userInfo:nil];
    }
}

- (NSString *)senderKey
{
    if (_clearEvent)
    {
        return _clearEvent->senderCurve25519Key;
    }
    else
    {
        return senderCurve25519Key;
    }
}

- (NSDictionary *)keysClaimed
{
    NSDictionary *keysClaimed;
    NSString *selfClaimedEd25519Key = self.claimedEd25519Key;
    if (selfClaimedEd25519Key)
    {
        keysClaimed =  @{
                         @"ed25519": selfClaimedEd25519Key
                         };
    }
    return keysClaimed;
}

- (NSString *)claimedEd25519Key
{
    if (_clearEvent)
    {
        return _clearEvent->claimedEd25519Key;
    }
    else
    {
        return claimedEd25519Key;
    }
}

- (NSArray<NSString *> *)forwardingCurve25519KeyChain
{
    if (_clearEvent)
    {
        return _clearEvent->forwardingCurve25519KeyChain;
    }
    else
    {
        return forwardingCurve25519KeyChain;
    }
}

- (MXEncryptedContentFile*)getEncryptedThumbnailFile
{
    MXEncryptedContentFile *encryptedContentFile;
    
    NSDictionary *contentInfo;
    MXJSONModelSetDictionary(contentInfo, self.content[@"info"]);
    
    if (contentInfo)
    {
        MXJSONModelSetMXJSONModel(encryptedContentFile, MXEncryptedContentFile, contentInfo[@"thumbnail_file"]);
    }
    
    return encryptedContentFile;
}

- (MXEncryptedContentFile*)getEncryptedContentFile
{
    MXEncryptedContentFile *encryptedContentFile;
    
    MXJSONModelSetMXJSONModel(encryptedContentFile, MXEncryptedContentFile, self.content[@"file"]);
    
    return encryptedContentFile;
}

- (NSArray<MXEncryptedContentFile *>*)getEncryptedContentFiles
{
    NSMutableArray<MXEncryptedContentFile*> *encryptedContentFiles = [NSMutableArray new];
    
    MXEncryptedContentFile *contentFile = [self getEncryptedContentFile];
    
    if (contentFile)
    {
        [encryptedContentFiles addObject:contentFile];
    }
    
    MXEncryptedContentFile *thumbnailFile = [self getEncryptedThumbnailFile];
    
    if (thumbnailFile)
    {
        [encryptedContentFiles addObject:thumbnailFile];
    }
    
    return encryptedContentFiles;
}

- (MXEventDecryptionResult*)decryptionResult
{
    MXEventDecryptionResult *decryptionResult = [MXEventDecryptionResult new];
    
    if (_clearEvent)
    {
        decryptionResult.clearEvent = _clearEvent.JSONDictionary;
        decryptionResult.senderCurve25519Key = _clearEvent->senderCurve25519Key;
        decryptionResult.claimedEd25519Key = _clearEvent->claimedEd25519Key;
        decryptionResult.forwardingCurve25519KeyChain = _clearEvent->forwardingCurve25519KeyChain;
        decryptionResult.decoration = _clearEvent.decryptionDecoration;
    }
    
    decryptionResult.error = _decryptionError;
    
    return decryptionResult;
}

- (MXEventDecryptionDecoration *)decryptionDecoration
{
    if (self.isEncrypted && _clearEvent)
    {
        return _clearEvent.decryptionDecoration;
    }
    return _decryptionDecoration;
}

#pragma mark - private
- (NSMutableDictionary*)filterInEventWithKeys:(NSArray*)keys
{
    NSDictionary *originalDict = self.JSONDictionary;
    NSMutableDictionary *filteredEvent = [NSMutableDictionary dictionary];
    
    for (NSString* key in keys)
    {
        if (originalDict[key])
        {
            [filteredEvent setObject:originalDict[key] forKey:key];
        }
    }
    
    return filteredEvent;
}

- (NSDictionary*)filterInContentWithKeys:(NSArray*)contentKeys
{
    NSMutableDictionary *filteredContent = [NSMutableDictionary dictionary];
    
    for (NSString* key in contentKeys)
    {
        if (self.content[key])
        {
            [filteredContent setObject:self.content[key] forKey:key];
        }
    }
    
    return filteredContent;
}

- (NSDictionary*)filterInPrevContentWithKeys:(NSArray*)contentKeys
{
    NSMutableDictionary *filteredPrevContent = [NSMutableDictionary dictionary];
    
    for (NSString* key in contentKeys)
    {
        if (self.prevContent[key])
        {
            [filteredPrevContent setObject:self.prevContent[key] forKey:key];
        }
    }
    
    return filteredPrevContent;
}

#pragma mark - Validation

+ (NSDictionary *)wireContentFixingNonStringMsgtypesIn:(NSDictionary *)content
{
    if (content[kMXMessageTypeKey] && ![content[kMXMessageTypeKey] isKindOfClass:[NSString class]])
    {
        NSMutableDictionary *mutableContent = [NSMutableDictionary dictionaryWithDictionary:content];
        [mutableContent removeObjectForKey:kMXMessageTypeKey];
        return [NSDictionary dictionaryWithDictionary:mutableContent];
    }
    return content;
}

#pragma mark - NSCoding
// Overriding MTLModel NSCoding operation makes serialisation going 20% faster
- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _eventId = [aDecoder decodeObjectForKey:@"eventId"];
        _roomId = [aDecoder decodeObjectForKey:@"roomId"];
        _sender = [aDecoder decodeObjectForKey:@"userId"];
        _sentState = (MXEventSentState)[aDecoder decodeIntegerForKey:@"sentState"];
        _wireContent = [aDecoder decodeObjectForKey:@"content"];
        _wireContent = [MXEvent wireContentFixingNonStringMsgtypesIn:_wireContent];
        _prevContent = [aDecoder decodeObjectForKey:@"prevContent"];
        _prevContent = [MXEvent wireContentFixingNonStringMsgtypesIn:_prevContent];
        _stateKey = [aDecoder decodeObjectForKey:@"stateKey"];
        _originServerTs = (uint64_t)[aDecoder decodeInt64ForKey:@"originServerTs"];
        _ageLocalTs = (uint64_t)[aDecoder decodeInt64ForKey:@"ageLocalTs"];
        _unsignedData = [aDecoder decodeObjectForKey:@"unsigned"];
        _redacts = [aDecoder decodeObjectForKey:@"redacts"];
        _redactedBecause = [aDecoder decodeObjectForKey:@"redactedBecause"];
        _inviteRoomState = [aDecoder decodeObjectForKey:@"inviteRoomState"];
        _sentError = [aDecoder decodeObjectForKey:@"sentError"];

        _wireEventType = (MXEventType)[aDecoder decodeIntegerForKey:@"eventType"];
        if (_wireEventType == MXEventTypeCustom)
        {
            self.wireType = [aDecoder decodeObjectForKey:@"type"];
        }
        else
        {
            // Retrieve the type string from the enum
            self.wireEventType = _wireEventType;
        }

    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_eventId forKey:@"eventId"];
    [aCoder encodeObject:_roomId forKey:@"roomId"];
    [aCoder encodeObject:_sender forKey:@"userId"];
    [aCoder encodeInteger:(NSInteger)_sentState forKey:@"sentState"];
    [aCoder encodeObject:_wireContent forKey:@"content"];
    [aCoder encodeObject:_prevContent forKey:@"prevContent"];
    [aCoder encodeObject:_stateKey forKey:@"stateKey"];
    [aCoder encodeInt64:(int64_t)_originServerTs forKey:@"originServerTs"];
    [aCoder encodeInt64:(int64_t)_ageLocalTs forKey:@"ageLocalTs"];
    [aCoder encodeObject:_unsignedData forKey:@"unsigned"];
    [aCoder encodeObject:_redacts forKey:@"redacts"];
    [aCoder encodeObject:_redactedBecause forKey:@"redactedBecause"];
    [aCoder encodeObject:_inviteRoomState forKey:@"inviteRoomState"];
    [aCoder encodeObject:_sentError forKey:@"sentError"];

    [aCoder encodeInteger:(NSInteger)_wireEventType forKey:@"eventType"];
    if (_wireEventType == MXEventTypeCustom)
    {
        // Store the type string only if it does not have an enum
        [aCoder encodeObject:_wireType forKey:@"type"];
    }
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone
{
    MXEvent *event = [MXEvent modelFromJSON:self.JSONDictionary];
    
    if (self.isEncrypted && self.clearEvent.JSONDictionary)
    {
        event->_clearEvent = [MXEvent modelFromJSON:self.clearEvent.JSONDictionary];
    }
    
    return event;
}

@end
