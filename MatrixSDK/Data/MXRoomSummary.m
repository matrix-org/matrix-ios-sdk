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
    // @TODO: storage

    // Broadcast the change
    [[NSNotificationCenter defaultCenter] postNotificationName:kMXRoomSummaryDidChangeNotification object:self userInfo:nil];
}

- (MXRoom *)room
{
    // That makes self.room a really weak reference
    return [_mxSession roomWithRoomId:_roomId];
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

        for (NSString *key in [self propertyKeys])
        {
            id value = [aDecoder decodeObjectForKey:key];
            [self setValue:value forKey:key];
        }
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_roomId forKey:@"roomId"];

    for (NSString *key in [self propertyKeys])
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
- (NSArray *)propertyKeys
{
    NSMutableArray *array = [NSMutableArray array];
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

                //see if there is a backing ivar with a KVC-compliant name
                NSRange iVarRange = [encoding rangeOfString:@",V"];
                if (iVarRange.location != NSNotFound)
                {
                    NSString *iVarName = [encoding substringFromIndex:iVarRange.location + 2];
                    if ([iVarName isEqualToString:key] ||
                        [iVarName isEqualToString:[@"_" stringByAppendingString:key]])
                    {
                        //setValue:forKey: will still work
                        readonly = NO;
                    }
                }
            }

            if (!readonly)
            {
                //exclude read-only properties
                [array addObject:key];
            }
        }
        free(properties);
        class = [class superclass];
    }
    return array;
}


@end
