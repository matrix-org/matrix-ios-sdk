/*
 Copyright 2017 OpenMarket Ltd

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

#import <objc/runtime.h>
#import <objc/message.h>

NSString *const kMXRoomSummaryDidChangeNotification = @"kMXRoomSummaryDidChangeNotification";

@implementation MXRoomSummary

- (instancetype)initWithRoomId:(NSString *)theRoomId andMatrixSession:(MXSession *)matrixSession
{
    self = [super init];
    if (self)
    {
        _roomId = theRoomId;
        _mxSession = matrixSession;
        _stateOthers = [NSMutableDictionary dictionary];
        _lastMessageOthers = [NSMutableDictionary dictionary];
        _others = [NSMutableDictionary dictionary];

        // Listen to the event sent state changes
        // This is used to follow evolution of local echo events
        // (ex: when a sentState change from sending to sentFailed)
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(eventDidChangeSentState:) name:kMXEventDidChangeSentStateNotification object:nil];
    }

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kMXEventDidChangeSentStateNotification object:nil];
}

- (void)setMatrixSession:(MXSession *)mxSession
{
    _mxSession = mxSession;
}

- (void)save
{
    if ([_mxSession.store respondsToSelector:@selector(storeSummaryForRoom:summary:)])
    {
        [_mxSession.store storeSummaryForRoom:_roomId summary:self];
    }
    if ([_mxSession.store respondsToSelector:@selector(commit)])
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
    [_stateOthers removeAllObjects];

    if ([_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withStateEvents:room.state.stateEvents])
    {
        [self save];
    }
}


#pragma mark - Data related to the last message

- (MXEvent *)lastMessageEvent
{
    MXEvent *lastMessageEvent;

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

    return lastMessageEvent;
}

- (MXHTTPOperation *)resetLastMessage:(void (^)())complete failure:(void (^)(NSError *))failure
{
    _lastMessageEventId = nil;
    _lastMessageString = nil;
    _lastMessageAttributedString = nil;
    [_lastMessageOthers removeAllObjects];

    return [self fetchLastMessage:complete failure:failure lastEventIdChecked:nil operation:nil];
}

/**
 Find the event to be used as last message.

 @param success A block object called when the operation completes.
 @param failure A block object called when the operation fails.
 @param lastEventIdChecked the id of the last candidate event checked to be the last message.
        Nil means we will start checking from the last event in the store.
 @param operation the current http operation if any.
        The method may need several requests before fetching the right last message.
        If it happens, the first one is mutated with [MXHTTPOperation mutateTo:].
 @return a MXHTTPOperation
 */
- (MXHTTPOperation *)fetchLastMessage:(void (^)())complete failure:(void (^)(NSError *))failure lastEventIdChecked:(NSString*)lastEventIdChecked operation:(MXHTTPOperation *)operation
{
    MXRoom *room = self.room;
    if (!room)
    {
        if (failure)
        {
            failure(nil);
        }
    }

    MXHTTPOperation *newOperation;

    // Start by checking events we have in the store
    MXRoomState *state = self.room.state;
    id<MXEventsEnumerator> messagesEnumerator = room.enumeratorForStoredMessages;
    NSUInteger messagesInStore = messagesEnumerator.remaining;
    MXEvent *event = messagesEnumerator.nextEvent;

    // 1.1 Find where we stopped at the previous call
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

    // Check events one by one until finding the right last message for the room
    BOOL lastMessageUpdated = NO;
    while (event)
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

        // Decrypt event if necessary
        if (event.eventType == MXEventTypeRoomEncrypted)
        {
            if (![self.mxSession decryptEvent:event inTimeline:nil])
            {
                NSLog(@"[MXRoomSummary] fetchLastMessage: Warning: Unable to decrypt event: %@\nError: %@", event.content[@"body"], event.decryptionError);
            }
        }

        lastEventIdChecked = event.eventId;

        // Propose the event as last message
        lastMessageUpdated = [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withLastEvent:event state:state];
        if (lastMessageUpdated)
        {
            break;
        }

        event = messagesEnumerator.nextEvent;
    }

    // If lastMessageEventId is still nil, fetch events from the homeserver
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
                         operation:(operation ? operation : newOperation)];

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

        [self save];
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

        lastMessageUpdated = [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withLastEvent:event state:state];
        if (lastMessageUpdated)
        {
            break;
        }
    }

    if (updated || lastMessageUpdated)
    {
        [self save];
    }
}

- (void)handleInvitedRoomSync:(MXInvitedRoomSync*)invitedRoomSync
{
    BOOL updated = [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withStateEvents:invitedRoomSync.inviteState.events];

    // Fake the last message with the invitation event contained in invitedRoomSync.inviteState
    updated |= [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withLastEvent:invitedRoomSync.inviteState.events.lastObject state:self.room.state];

    if (updated)
    {
        [self save];
    }
}


#pragma mark - Single update
- (void)handleEvent:(MXEvent*)event
{
    MXRoom *room = self.room;

    if (room)
    {
        BOOL updated = [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withLastEvent:event state:room.state];

        if (updated)
        {
            [self save];
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

        for (NSString *key in [MXRoomSummary propertyKeys])
        {
            id value = [aDecoder decodeObjectForKey:key];
            if (value)
            {
                [self setValue:value forKey:key];
            }
        }
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_roomId forKey:@"roomId"];

    for (NSString *key in [MXRoomSummary propertyKeys])
    {
        id value = [self valueForKey:key];
        if (value)
        {
            [aCoder encodeObject:value forKey:key];
        }
    }
}

// Took at http://stackoverflow.com/a/8938097
// in order to automatically NSCoding the class properties
+ (NSArray *)propertyKeys
{
    static NSMutableArray *propertyKeys;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{

        propertyKeys = [NSMutableArray array];
        Class class = [self class];
        while (class != [NSObject class])
        {
            unsigned int propertyCount;
            objc_property_t *properties = class_copyPropertyList(class, &propertyCount);
            for (int i = 0; i < propertyCount; i++)
            {
                //get property
                objc_property_t property = properties[i];
                const char *propertyName = property_getName(property);
                NSString *key = [NSString stringWithCString:propertyName encoding:NSUTF8StringEncoding];

                //check if read-only
                BOOL readonly = NO;
                const char *attributes = property_getAttributes(property);
                NSString *encoding = [NSString stringWithCString:attributes encoding:NSUTF8StringEncoding];
                if ([[encoding componentsSeparatedByString:@","] containsObject:@"R"])
                {
                    readonly = YES;
                }

                if (!readonly)
                {
                    //exclude read-only properties
                    [propertyKeys addObject:key];
                }
            }
            free(properties);
            class = [class superclass];
        }


        NSLog(@"[MXRoomSummary] Stored properties: %@", propertyKeys);
    });

    return propertyKeys;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ %@: %@ - %@", super.description, _roomId, _displayname, _lastMessageString];
}

@end
