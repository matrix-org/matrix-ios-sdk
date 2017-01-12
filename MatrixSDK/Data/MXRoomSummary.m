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
    }

    return self;
}

- (void)setMatrixSession:(MXSession *)mxSession
{
    _mxSession = mxSession;
}

- (void)loadFromStore
{
    MXRoom *room = self.room;

    // Well, load it from the room state data
    // @TODO: Make MXStore manage room summaries
    [self updateFromRoomState];

    id<MXEventsEnumerator> messagesEnumerator = room.enumeratorForStoredMessages;
    MXEvent *event = messagesEnumerator.nextEvent;

    MXRoomState *state = self.room.state;

    BOOL lastEventUpdated = NO;
    while (event && !lastEventUpdated)
    {
        if (event.isState)
        {
            // @TODO: udpate state
        }

        lastEventUpdated = [_mxSession.roomSummaryUpdateDelegate session:_mxSession updateRoomSummary:self withLastEvent:event oldState:state];

        event = messagesEnumerator.nextEvent;
    }

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
    return [_mxSession.store eventWithEventId:_lastEventId inRoom:_roomId];
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
