/*
 Copyright 2017 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd

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

#import "MXRoomSummary.h"

#import "MXRoom.h"
#import "MXRoomState.h"
#import "MXSession.h"

#import <Security/Security.h>
#import <CommonCrypto/CommonCryptor.h>

NSString *const kMXRoomSummaryDidChangeNotification = @"kMXRoomSummaryDidChangeNotification";

@interface MXRoomSummary ()
{
    // Cache for the last event to avoid to read it from the store everytime
    MXEvent *lastMessageEvent;
}

@end

@implementation MXRoomSummary

- (instancetype)initWithRoomId:(NSString *)theRoomId andMatrixSession:(MXSession *)matrixSession
{
    self = [super init];
    if (self)
    {
        _roomId = theRoomId;
        _mxSession = matrixSession;
        _lastMessageOthers = [NSMutableDictionary dictionary];
        _others = [NSMutableDictionary dictionary];

        // Listen to the event sent state changes
        // This is used to follow evolution of local echo events
        // (ex: when a sentState change from sending to sentFailed)
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(eventDidChangeSentState:) name:kMXEventDidChangeSentStateNotification object:nil];
    }

    return self;
}

- (void)destroy
{
    NSLog(@"[MXKRoomSummary] Destroy %p - room id: %@", self, _roomId);

    [[NSNotificationCenter defaultCenter] removeObserver:self name:kMXEventDidChangeSentStateNotification object:nil];
}

- (void)setMatrixSession:(MXSession *)mxSession
{
    _mxSession = mxSession;
}

- (void)save:(BOOL)commit
{
    if ([_mxSession.store respondsToSelector:@selector(storeSummaryForRoom:summary:)])
    {
        [_mxSession.store storeSummaryForRoom:_roomId summary:self];
    }
    if (commit && [_mxSession.store respondsToSelector:@selector(commit)])
    {
        [_mxSession.store commit];
    }

    // Broadcast the change
    [[NSNotificationCenter defaultCenter] postNotificationName:kMXRoomSummaryDidChangeNotification object:self userInfo:nil];
}

- (MXRoom *)room
{
    // That makes self.room a really weak reference
    return [_mxSession roomWithRoomId:_roomId];
}


#pragma mark - Data related to room state

- (void)resetRoomStateData
{
    // Reset data
    MXRoom *room = self.room;

    _avatar = nil;
    _displayname = nil;
    _topic = nil;

    if ([_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withStateEvents:room.state.stateEvents])
    {
        [self save:YES];
    }
}


#pragma mark - Data related to the last message

- (MXEvent *)lastMessageEvent
{
    if (lastMessageEvent)
    {
        return lastMessageEvent;
    }
    
    // The storage of the event depends if it is a true matrix event or a local echo
    if (![_lastMessageEventId hasPrefix:kMXEventLocalEventIdPrefix])
    {
        lastMessageEvent = [_mxSession.store eventWithEventId:_lastMessageEventId inRoom:_roomId];
    }
    else
    {
        for (MXEvent *event in [_mxSession.store outgoingMessagesInRoom:_roomId])
        {
            if ([event.eventId isEqualToString:_lastMessageEventId])
            {
                lastMessageEvent = event;
                break;
            }
        }
    }

    // Decrypt event if necessary
    if (lastMessageEvent.eventType == MXEventTypeRoomEncrypted)
    {
        if (![_mxSession decryptEvent:lastMessageEvent inTimeline:nil])
        {
            NSLog(@"[MXRoomSummary] lastMessageEvent: Warning: Unable to decrypt event. Error: %@", lastMessageEvent.decryptionError);
        }
    }

    return lastMessageEvent;
}

- (void)setLastMessageEvent:(MXEvent *)event
{
    lastMessageEvent = event;
    _lastMessageEventId = lastMessageEvent.eventId;
    _lastMessageOriginServerTs = lastMessageEvent.originServerTs;
    _isLastMessageEncrypted = event.isEncrypted;
}

- (MXHTTPOperation *)resetLastMessage:(void (^)(void))complete failure:(void (^)(NSError *))failure commit:(BOOL)commit
{
    lastMessageEvent = nil;
    _lastMessageEventId = nil;
    _lastMessageOriginServerTs = -1;
    _lastMessageString = nil;
    _lastMessageAttributedString = nil;
    [_lastMessageOthers removeAllObjects];

    return [self fetchLastMessage:complete failure:failure lastEventIdChecked:nil operation:nil commit:commit];
}

/**
 Find the event to be used as last message.

 @param complete A block object called when the operation completes.
 @param failure A block object called when the operation fails.
 @param lastEventIdChecked the id of the last candidate event checked to be the last message.
        Nil means we will start checking from the last event in the store.
 @param operation the current http operation if any.
        The method may need several requests before fetching the right last message.
        If it happens, the first one is mutated to the others with [MXHTTPOperation mutateTo:].
 @param commit tell whether the updated room summary must be committed to the store. Use NO when a more
 global [MXStore commit] will happen. This optimises IO.
 @return a MXHTTPOperation
 */
- (MXHTTPOperation *)fetchLastMessage:(void (^)(void))complete failure:(void (^)(NSError *))failure lastEventIdChecked:(NSString*)lastEventIdChecked operation:(MXHTTPOperation *)operation commit:(BOOL)commit
{
    MXRoom *room = self.room;
    if (!room)
    {
        if (failure)
        {
            failure(nil);
        }
        return nil;
    }

    MXHTTPOperation *newOperation;

    // Start by checking events we have in the store
    MXRoomState *state = self.room.state;
    id<MXEventsEnumerator> messagesEnumerator = room.enumeratorForStoredMessages;
    NSUInteger messagesInStore = messagesEnumerator.remaining;
    MXEvent *event = messagesEnumerator.nextEvent;

    // 1.1 Find where we stopped at the previous call in the fetchLastMessage calls loop
    BOOL firstIteration = YES;
    if (lastEventIdChecked)
    {
        firstIteration = NO;
        while (event)
        {
            NSString *eventId = event.eventId;

            event = messagesEnumerator.nextEvent;

            if ([eventId isEqualToString:lastEventIdChecked])
            {
                break;
            }
        }
    }

    // 1.2 Check events one by one until finding the right last message for the room
    BOOL lastMessageUpdated = NO;
    while (event)
    {
        // Decrypt the event if necessary
        if (event.eventType == MXEventTypeRoomEncrypted)
        {
            if (![_mxSession decryptEvent:event inTimeline:nil])
            {
                NSLog(@"[MXRoomSummary] fetchLastMessage: Warning: Unable to decrypt event: %@\nError: %@", event.content[@"body"], event.decryptionError);
            }
        }

        if (event.isState)
        {
            // Need to go backward in the state to provide it as it was when the event occured
            if (state.isLive)
            {
                state = [state copy];
                state.isLive = NO;
            }

            [state handleStateEvent:event];
        }

        lastEventIdChecked = event.eventId;

        // Propose the event as last message
        lastMessageUpdated = [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withLastEvent:event eventState:state roomState:self.room.state];
        if (lastMessageUpdated)
        {
            // The event is accepted. We have our last message
            // The roomSummaryUpdateDelegate has stored the _lastMessageEventId
            break;
        }

        event = messagesEnumerator.nextEvent;
    }

    // 2.1 If lastMessageEventId is still nil, fetch events from the homeserver
    if (!_lastMessageEventId && [room.liveTimeline canPaginate:MXTimelineDirectionBackwards])
    {
        NSUInteger messagesToPaginate = 30;

        // Reset pagination the first time
        if (firstIteration)
        {
            [room.liveTimeline resetPagination];

            // Make sure we paginate more than the events we have already in the store
            messagesToPaginate += messagesInStore;
        }

        // Paginate events from the homeserver
        // XXX: Pagination on the timeline may conflict with request from the app
        newOperation = [room.liveTimeline paginate:messagesToPaginate direction:MXTimelineDirectionBackwards onlyFromStore:NO complete:^{

            // Received messages have been stored in the store. We can make a new loop
            [self fetchLastMessage:complete failure:failure
                lastEventIdChecked:lastEventIdChecked
                         operation:(operation ? operation : newOperation)
                            commit:commit];

        } failure:failure];

        // Update the current HTTP operation
        if (operation)
        {
            [operation mutateTo:newOperation];
        }
    }
    else
    {
        if (complete)
        {
            complete();
        }

        [self save:commit];
    }

    return operation ? operation : newOperation;
}

- (void)eventDidChangeSentState:(NSNotification *)notif
{
    MXEvent *event = notif.object;

    // If the last message is a local echo, update it.
    // Do nothing when its sentState becomes sent. In this case, the last message will be
    // updated by the true event coming back from the homeserver.
    if (event.sentState != MXEventSentStateSent && [event.eventId isEqualToString:_lastMessageEventId])
    {
        [self handleEvent:event];
    }
}


#pragma mark - Others
- (NSUInteger)localUnreadEventCount
{
    // Check for unread events in store
    return [_mxSession.store localUnreadEventCount:_roomId withTypeIn:_mxSession.unreadEventTypes];
}

- (BOOL)isDirect
{
    return (_directUserId != nil);
}

- (void)markAllAsRead
{
    [self.room markAllAsRead];
    
    _notificationCount = 0;
    _highlightCount = 0;
    
    // Broadcast the change
    [[NSNotificationCenter defaultCenter] postNotificationName:kMXRoomSummaryDidChangeNotification object:self userInfo:nil];
}

#pragma mark - Server sync
- (void)handleJoinedRoomSync:(MXRoomSync*)roomSync
{
    // Handle first changes due to state events
    BOOL updated = NO;

    NSMutableArray<MXEvent*> *stateEvents = [NSMutableArray arrayWithArray:roomSync.state.events];

    // There may be state events in the timeline too
    for (MXEvent *event in roomSync.timeline.events)
    {
        if (event.isState)
        {
            [stateEvents addObject:event];
        }
    }

    if (stateEvents.count)
    {
        updated = [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withStateEvents:stateEvents];
    }

    // Handle the last message starting by the most recent event.
    // Then, if the delegate refuses it as last message, pass the previous event.
    BOOL lastMessageUpdated = NO;
    MXRoomState *state = self.room.state;
    for (MXEvent *event in roomSync.timeline.events.reverseObjectEnumerator)
    {
        if (event.isState)
        {
            // Need to go backward in the state to provide it as it was when the event occured
            if (state.isLive)
            {
                state = [state copy];
                state.isLive = NO;
            }

            [state handleStateEvent:event];
        }

        lastMessageUpdated = [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withLastEvent:event eventState:state roomState:self.room.state];
        if (lastMessageUpdated)
        {
            break;
        }
    }

    // Store notification counts from unreadNotifications field in /sync response
    if (roomSync.unreadNotifications)
    {
        // Caution: the server may provide a not null count whereas we know locally the user has read all room messages
        // (see for example this issue https://github.com/matrix-org/synapse/issues/2193).
        // Patch: Ignore the server information when the user has read all messages.
        if (roomSync.unreadNotifications.notificationCount && self.localUnreadEventCount == 0)
        {
            if (_notificationCount != 0)
            {
                _notificationCount = 0;
                _highlightCount = 0;
                updated = YES;
            }
        }
        else if (_notificationCount != roomSync.unreadNotifications.notificationCount
                 || _highlightCount != roomSync.unreadNotifications.highlightCount)
        {
            _notificationCount = roomSync.unreadNotifications.notificationCount;
            _highlightCount = roomSync.unreadNotifications.highlightCount;
            updated = YES;
        }
    }

    if (updated || lastMessageUpdated)
    {
        [self save:NO];
    }
}

- (void)handleInvitedRoomSync:(MXInvitedRoomSync*)invitedRoomSync
{
    BOOL updated = [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withStateEvents:invitedRoomSync.inviteState.events];

    MXRoom *room = self.room;

    // Fake the last message with the invitation event contained in invitedRoomSync.inviteState
    updated |= [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withLastEvent:invitedRoomSync.inviteState.events.lastObject eventState:nil roomState:room.state];

    if (updated)
    {
        [self save:NO];
    }
}


#pragma mark - Single update
- (void)handleEvent:(MXEvent*)event
{
    MXRoom *room = self.room;

    if (room)
    {
        BOOL updated = [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withLastEvent:event eventState:nil roomState:room.state];

        if (updated)
        {
            [self save:YES];
        }
    }
}


#pragma mark - NSCoding
- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [self init];
    if (self)
    {
        _roomId = [aDecoder decodeObjectForKey:@"roomId"];

        _avatar = [aDecoder decodeObjectForKey:@"avatar"];
        _displayname = [aDecoder decodeObjectForKey:@"displayname"];
        _topic = [aDecoder decodeObjectForKey:@"topic"];

        _others = [aDecoder decodeObjectForKey:@"others"];
        _isEncrypted = [aDecoder decodeBoolForKey:@"isEncrypted"];
        _notificationCount = (NSUInteger)[aDecoder decodeIntegerForKey:@"notificationCount"];
        _highlightCount = (NSUInteger)[aDecoder decodeIntegerForKey:@"highlightCount"];
        _directUserId = [aDecoder decodeObjectForKey:@"directUserId"];

        _lastMessageEventId = [aDecoder decodeObjectForKey:@"lastMessageEventId"];
        _lastMessageOriginServerTs = [aDecoder decodeInt64ForKey:@"lastMessageOriginServerTs"];
        _isLastMessageEncrypted = [aDecoder decodeBoolForKey:@"isLastMessageEncrypted"];

        NSDictionary *lastMessageData;
        if (_isLastMessageEncrypted)
        {
            NSData *lastMessageEncryptedData = [aDecoder decodeObjectForKey:@"lastMessageEncryptedData"];
            NSData *lastMessageDataData = [self decrypt:lastMessageEncryptedData];
            lastMessageData = [NSKeyedUnarchiver unarchiveObjectWithData:lastMessageDataData];
        }
        else
        {
            lastMessageData = [aDecoder decodeObjectForKey:@"lastMessageData"];
        }
        _lastMessageString = lastMessageData[@"lastMessageString"];
        _lastMessageAttributedString = lastMessageData[@"lastMessageAttributedString"];
        _lastMessageOthers = lastMessageData[@"lastMessageOthers"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_roomId forKey:@"roomId"];

    [aCoder encodeObject:_avatar forKey:@"avatar"];
    [aCoder encodeObject:_displayname forKey:@"displayname"];
    [aCoder encodeObject:_topic forKey:@"topic"];

    [aCoder encodeObject:_others forKey:@"others"];
    [aCoder encodeBool:_isEncrypted forKey:@"isEncrypted"];
    [aCoder encodeInteger:(NSInteger)_notificationCount forKey:@"notificationCount"];
    [aCoder encodeInteger:(NSInteger)_highlightCount forKey:@"highlightCount"];
    [aCoder encodeObject:[self room].directUserId forKey:@"directUserId"];

    // Store last message metadata
    [aCoder encodeObject:_lastMessageEventId forKey:@"lastMessageEventId"];
    [aCoder encodeInt64:_lastMessageOriginServerTs forKey:@"lastMessageOriginServerTs"];
    [aCoder encodeBool:_isLastMessageEncrypted forKey:@"isLastMessageEncrypted"];

    // Build last message sensitive data
    NSMutableDictionary *lastMessageData = [NSMutableDictionary dictionary];
    if (_lastMessageString)
    {
        lastMessageData[@"lastMessageString"] = _lastMessageString;
    }
    if (_lastMessageAttributedString)
    {
        lastMessageData[@"lastMessageAttributedString"] = _lastMessageAttributedString;
    }
    if (_lastMessageString)
    {
        lastMessageData[@"lastMessageOthers"] = _lastMessageOthers;
    }

    // And encrypt it if necessary
    if (_isLastMessageEncrypted)
    {
        NSData *lastMessageDataData = [NSKeyedArchiver archivedDataWithRootObject:lastMessageData];
        NSData *lastMessageEncryptedData = [self encrypt:lastMessageDataData];

        if (lastMessageEncryptedData)
        {
            [aCoder encodeObject:lastMessageEncryptedData forKey:@"lastMessageEncryptedData"];
        }
    }
    else
    {
        [aCoder encodeObject:lastMessageData forKey:@"lastMessageData"];
    }
}


#pragma mark - Last message data encryption
/**
 The AES-256 key used for encrypting MXRoomSummary sensitive data.
 */
+ (NSData*)encryptionKey
{
    NSData *encryptionKey;

    // Create a dictionary to look up the key in the keychain
    NSDictionary *searchDict = @{
                                 (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                 (__bridge id)kSecAttrService: @"org.matrix.sdk.keychain",
                                 (__bridge id)kSecAttrAccount: @"MXRoomSummary",
                                 (__bridge id)kSecReturnData: (__bridge id)kCFBooleanTrue,
                                 };

    // Make the search
    CFDataRef foundKey;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)searchDict, (CFTypeRef*)&foundKey);

    if (status == errSecSuccess)
    {
        // Use the found key
        encryptionKey = (__bridge NSData*)(foundKey);
    }
    else if (status == errSecItemNotFound)
    {
        NSLog(@"[MXRoomSummary] encryptionKey: Generate the key and store it to the keychain");

        // There is not yet a key in the keychain
        // Generate an AES key
        NSMutableData *newEncryptionKey = [[NSMutableData alloc] initWithLength:kCCKeySizeAES256];
        int retval = SecRandomCopyBytes(kSecRandomDefault, kCCKeySizeAES256, newEncryptionKey.mutableBytes);
        if (retval == 0)
        {
            encryptionKey = [NSData dataWithData:newEncryptionKey];

            // Store it to the keychain
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:searchDict];
            dict[(__bridge id)kSecValueData] = encryptionKey;

            status = SecItemAdd((__bridge CFDictionaryRef)dict, NULL);
            if (status != errSecSuccess)
            {
                // TODO: The iOS 10 simulator returns the -34018 (errSecMissingEntitlement) error.
                // We need to fix it but there is no issue with the app on real device nor with iOS 9 simulator.
                NSLog(@"[MXRoomSummary] encryptionKey: SecItemAdd failed. status: %i", (int)status);
            }
        }
        else
        {
            NSLog(@"[MXRoomSummary] encryptionKey: Cannot generate key. retval: %i", retval);
        }
    }
    else
    {
        NSLog(@"[MXRoomSummary] encryptionKey: Keychain failed. OSStatus: %i", (int)status);
    }

    return encryptionKey;
}

- (NSData*)encrypt:(NSData*)data
{
    NSData *encryptedData;

    CCCryptorRef cryptor;
    CCCryptorStatus status;

    NSData *key = [MXRoomSummary encryptionKey];

    status = CCCryptorCreateWithMode(kCCDecrypt, kCCModeCTR, kCCAlgorithmAES,
                                     ccNoPadding, NULL, key.bytes, key.length,
                                     NULL, 0, 0, kCCModeOptionCTR_BE, &cryptor);
    if (status == kCCSuccess)
    {
        size_t bufferLength = CCCryptorGetOutputLength(cryptor, data.length, false);
        NSMutableData *buffer = [NSMutableData dataWithLength:bufferLength];

        size_t outLength;
        status |= CCCryptorUpdate(cryptor,
                                  data.bytes,
                                  data.length,
                                  [buffer mutableBytes],
                                  [buffer length],
                                  &outLength);

        status |= CCCryptorRelease(cryptor);

        if (status == kCCSuccess)
        {
            encryptedData = buffer;
        }
        else
        {
            NSLog(@"[MXRoomSummary] encrypt: CCCryptorUpdate failed. status: %i", status);
        }
    }
    else
    {
        NSLog(@"[MXRoomSummary] encrypt: CCCryptorCreateWithMode failed. status: %i", status);
    }

    return encryptedData;
}

- (NSData*)decrypt:(NSData*)encryptedData
{
    NSData *data;

    CCCryptorRef cryptor;
    CCCryptorStatus status;

    NSData *key = [MXRoomSummary encryptionKey];

    status = CCCryptorCreateWithMode(kCCDecrypt, kCCModeCTR, kCCAlgorithmAES,
                                     ccNoPadding, NULL, key.bytes, key.length,
                                     NULL, 0, 0, kCCModeOptionCTR_BE, &cryptor);
    if (status == kCCSuccess)
    {
        size_t bufferLength = CCCryptorGetOutputLength(cryptor, encryptedData.length, false);
        NSMutableData *buffer = [NSMutableData dataWithLength:bufferLength];

        size_t outLength;
        status |= CCCryptorUpdate(cryptor,
                                  encryptedData.bytes,
                                  encryptedData.length,
                                  [buffer mutableBytes],
                                  [buffer length],
                                  &outLength);

        status |= CCCryptorRelease(cryptor);

        if (status == kCCSuccess)
        {
            data = buffer;
        }
        else
        {
            NSLog(@"[MXRoomSummary] decrypt: CCCryptorUpdate failed. status: %i", status);
        }
    }
    else
    {
        NSLog(@"[MXRoomSummary] decrypt: CCCryptorCreateWithMode failed. status: %i", status);
    }
    
    return data;
}


- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ %@: %@ - %@", super.description, _roomId, _displayname, _lastMessageString];
}

@end
