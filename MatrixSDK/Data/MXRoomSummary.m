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

- (void)reset
{
    MXRoom *room = self.room;

    if (!room)
    {
        return;
    }

    // Reset data
    _lastEventId = nil;
    _lastEventString = nil;
    _lastEventAttribytedString = nil;
    [_others removeAllObjects];

    // Rebuild data related to room state
    [self updateFromRoomState];

    // Compute the last message again
    id<MXEventsEnumerator> messagesEnumerator = room.enumeratorForStoredMessages;
    MXEvent *event = messagesEnumerator.nextEvent;

    MXRoomState *state = self.room.state;

    BOOL lastEventUpdated = NO;
    while (event)
    {
        if (event.isState)
        {
            // @TODO: udpate state
        }

        // Decrypt event if necessary
        if (event.eventType == MXEventTypeRoomEncrypted)
        {
            if (![self.mxSession decryptEvent:event inTimeline:nil])
            {
                NSLog(@"[MXKRoomDataSource] lastMessageWithEventFormatter: Warning: Unable to decrypt event: %@\nError: %@", event.content[@"body"], event.decryptionError);
            }
        }

        lastEventUpdated = [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withLastEvent:event oldState:state];
        if (lastEventUpdated)
        {
            break;
        }

        event = messagesEnumerator.nextEvent;
    }

    // @TODO: fetch events from the hs if lastEventUpdated is still nil

    [self save];
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

- (MXEvent *)lastEvent
{
    MXEvent *lastEvent;

    // Is it a true matrix event or a local echo?
    if (![_lastEventId hasPrefix:kMXEventLocalEventIdPrefix])
    {
        lastEvent = [_mxSession.store eventWithEventId:_lastEventId inRoom:_roomId];
    }
    else
    {
        for (MXEvent *event in [_mxSession.store outgoingMessagesInRoom:_roomId])
        {
            if ([event.eventId isEqualToString:_lastEventId])
            {
                lastEvent = event;
                break;
            }
        }
    }

    return lastEvent;
}

- (void)eventDidChangeSentState:(NSNotification *)notif
{
    MXEvent *event = notif.object;

    // If the last event is a local echo, update it.
    // Do nothing when its sentState becomes sent. In this case, the last event will be
    // updated by the true event coming back from the homeserver.
    if (event.sentState != MXEventSentStateSent && [event.eventId isEqualToString:_lastEventId])
    {
        [self handleEvent:event];
    }
}

- (void)updateFromRoomState
{
    MXRoom *room = self.room;

    // @TODO: Manage all summary properties
    _avatar = room.state.avatar;
    _displayname = room.state.displayname;
    _topic = room.state.topic;
}

#pragma mark - Server sync
- (void)handleJoinedRoomSync:(MXRoomSync*)roomSync
{
    // Handle first changes due to state events
    BOOL updated = NO;
    for (MXEvent *event in roomSync.state.events)
    {
        updated |= [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withStateEvent:event];
    }

    // There may be state events in the timeline too
    for (MXEvent *event in roomSync.timeline.events)
    {
        if (event.isState)
        {
            updated |= [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withStateEvent:event];
        }
    }

    // Handle the last event starting by the more recent one
    // Then, if the delegate refuses it as last event, pass the previous event.
    BOOL lastEventUpdated = NO;
    MXRoomState *state = self.room.state;
    for (MXEvent *event in roomSync.timeline.events.reverseObjectEnumerator)
    {
        if (event.isState)
        {
            // @TODO: udpate state
        }

        lastEventUpdated = [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withLastEvent:event oldState:state];
        if (lastEventUpdated)
        {
            break;
        }
    }

    if (updated || lastEventUpdated)
    {
        [self save];
    }
}

- (void)handleInvitedRoomSync:(MXInvitedRoomSync*)invitedRoomSync
{
    BOOL updated = NO;

    for (MXEvent *event in invitedRoomSync.inviteState.events)
    {
        updated |= [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withStateEvent:event];
    }

    // Fake the last event with the invitation event contained in invitedRoomSync.inviteState
    // @TODO: Make sure that is true
    [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withLastEvent:invitedRoomSync.inviteState.events.lastObject oldState:self.room.state];

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
        BOOL updated = [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withLastEvent:event oldState:room.state];

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
    return [NSString stringWithFormat:@"%@ %@: %@ - %@", super.description, _roomId, _displayname, _lastEventString];
}


@end
